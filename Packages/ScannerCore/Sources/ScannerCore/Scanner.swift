import Foundation
import Darwin

public final class Scanner: Sendable {
    public init() {}
    
    public func scan(root: URL, options: ScanOptions) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                await runScan(root: root, options: options, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    private func runScan(root: URL, options: ScanOptions, continuation: AsyncStream<ScanEvent>.Continuation) async {
        let builder = TreeBuilder()
        let rootPath = root.standardizedFileURL.path
        
        let rootId = await builder.addRoot(name: root.lastPathComponent)
        
        await withTaskGroup(of: [(String, UInt32)].self) { group in
            group.addTask {
                await self.scanDir(path: rootPath, nodeId: rootId, options: options, builder: builder)
            }
            
            for await subdirs in group {
                for (subPath, subId) in subdirs {
                    group.addTask {
                        await self.scanDir(path: subPath, nodeId: subId, options: options, builder: builder)
                    }
                }
            }
        }
        
        if Task.isCancelled {
            continuation.finish()
            return
        }
        
        let store = await builder.buildStore()
        continuation.yield(.done(store: store))
        continuation.finish()
    }
    
    private func scanDir(path: String, nodeId: UInt32, options: ScanOptions, builder: TreeBuilder) async -> [(String, UInt32)] {
        guard !Task.isCancelled else { return [] }
        
        let dir = opendir(path)
        guard let dirPtr = dir else {
            await builder.markUnreadable(nodeId: nodeId)
            return []
        }
        defer { closedir(dirPtr) }
        
        var childrenBuffer: [(name: [UInt8], isDir: Bool, kind: UInt8, allocated: UInt64, logical: UInt64, path: String)] = []
        
        while let entry = readdir(dirPtr) {
            let nameTuple = entry.pointee.d_name
            let nameBytes = withUnsafeBytes(of: nameTuple) { rawPtr -> [UInt8] in
                let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
                let len = strlen(ptr)
                return [UInt8](UnsafeBufferPointer(start: rawPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), count: Int(len)))
            }
            
            if nameBytes == [46] || nameBytes == [46, 46] { continue }
            if !options.includeHiddenFiles && nameBytes.first == 46 { continue }
            
            let nameStr = String(cString: nameBytes + [0])
            let childPath = path == "/" ? "/" + nameStr : path + "/" + nameStr
            
            // Prevent APFS Firmlink double-counting (only Data volume) and cross-disk mounts
            if childPath == "/System/Volumes/Data" || childPath == "/Volumes" || childPath == "/dev" || childPath == "/net" || childPath == "/home" {
                continue
            }
            
            var statBuf = stat()
            if lstat(childPath, &statBuf) != 0 { continue }
            
            let isSymlink = (statBuf.st_mode & S_IFMT) == S_IFLNK
            if isSymlink { continue }
            
            var isDir = (statBuf.st_mode & S_IFMT) == S_IFDIR
            
            var allocated = UInt64(statBuf.st_blocks * 512)
            var logical = UInt64(statBuf.st_size)
            var kind = isDir ? NodeKind.dir.rawValue : NodeKind.file.rawValue
            
            if isDir && !options.lookInsidePackages {
                let url = URL(fileURLWithPath: childPath)
                if let vals = try? url.resourceValues(forKeys: [.isPackageKey]), vals.isPackage == true {
                    isDir = false
                    kind = NodeKind.package.rawValue
                    
                    // Fast sync size compute without allocating nodes
                    var stack = [childPath]
                    while let current = stack.popLast() {
                        guard let pkgDir = opendir(current) else { continue }
                        while let entry = readdir(pkgDir) {
                            let pkgName = withUnsafeBytes(of: entry.pointee.d_name) { rawPtr -> [UInt8] in
                                let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
                                return Array(String(cString: ptr).utf8)
                            }
                            if pkgName.count == 1 && pkgName[0] == 46 { continue }
                            if pkgName.count == 2 && pkgName[0] == 46 && pkgName[1] == 46 { continue }
                            
                            let pkgNameStr = String(decoding: pkgName, as: UTF8.self)
                            let pPath = current + "/" + pkgNameStr
                            
                            var pStat = stat()
                            if lstat(pPath, &pStat) == 0 {
                                allocated += UInt64(pStat.st_blocks * 512)
                                logical += UInt64(pStat.st_size)
                                if (pStat.st_mode & S_IFMT) == S_IFDIR {
                                    stack.append(pPath)
                                }
                            }
                        }
                        closedir(pkgDir)
                    }
                }
            }
            
            childrenBuffer.append((nameBytes, isDir, kind, allocated, logical, childPath))
        }
        
        let startChildId = await builder.reserveChildren(parentId: nodeId, count: childrenBuffer.count)
        
        var currentChildId = startChildId
        var totalAllocated: UInt64 = 0
        var totalLogical: UInt64 = 0
        var totalItems: UInt32 = 0
        
        var subdirsToScan: [(String, UInt32)] = []
        
        for child in childrenBuffer {
            let node = Node(
                id: currentChildId,
                parent: nodeId,
                nameBytes: child.name,
                kind: child.kind,
                flags: 0,
                allocatedBytes: child.allocated,
                logicalBytes: child.logical,
                itemCount: 1,
                children: 0..<0
            )
            
            await builder.updateNode(id: currentChildId, node: node)
            
            totalAllocated += child.allocated
            totalLogical += child.logical
            totalItems += 1
            
            if child.isDir {
                subdirsToScan.append((child.path, currentChildId))
            }
            currentChildId += 1
        }
        
        await builder.addSizes(nodeId: nodeId, allocated: totalAllocated, logical: totalLogical, items: totalItems)
        return subdirsToScan
    }
}

actor TreeBuilder {
    var nodes: [Node] = []
    
    func addRoot(name: String) -> UInt32 {
        let nameBytes = Array(name.utf8)
        let root = Node(id: 0, parent: 0, nameBytes: nameBytes, kind: NodeKind.dir.rawValue, flags: 0, allocatedBytes: 0, logicalBytes: 0, itemCount: 1, children: 0..<0)
        nodes.append(root)
        return 0
    }
    
    func reserveChildren(parentId: UInt32, count: Int) -> UInt32 {
        let start = nodes.count
        let emptyNode = Node(id: 0, parent: 0, nameBytes: [], kind: 0, flags: 0, allocatedBytes: 0, logicalBytes: 0, itemCount: 0, children: 0..<0)
        nodes.append(contentsOf: Array(repeating: emptyNode, count: count))
        
        let pId = Int(parentId)
        nodes[pId] = Node(id: nodes[pId].id, parent: nodes[pId].parent, nameBytes: nodes[pId].nameBytes, kind: nodes[pId].kind, flags: nodes[pId].flags, allocatedBytes: nodes[pId].allocatedBytes, logicalBytes: nodes[pId].logicalBytes, itemCount: nodes[pId].itemCount, children: UInt32(start)..<UInt32(start + count))
        
        return UInt32(start)
    }
    
    func updateNode(id: UInt32, node: Node) {
        nodes[Int(id)] = node
    }
    
    func markUnreadable(nodeId: UInt32) {
        let id = Int(nodeId)
        var flags = NodeFlags(rawValue: nodes[id].flags)
        flags.insert(.unreadable)
        nodes[id] = Node(id: nodes[id].id, parent: nodes[id].parent, nameBytes: nodes[id].nameBytes, kind: nodes[id].kind, flags: flags.rawValue, allocatedBytes: nodes[id].allocatedBytes, logicalBytes: nodes[id].logicalBytes, itemCount: nodes[id].itemCount, children: nodes[id].children)
    }
    
    func addSizes(nodeId: UInt32, allocated: UInt64, logical: UInt64, items: UInt32) {
        var current = Int(nodeId)
        while true {
            nodes[current] = Node(
                id: nodes[current].id,
                parent: nodes[current].parent,
                nameBytes: nodes[current].nameBytes,
                kind: nodes[current].kind,
                flags: nodes[current].flags,
                allocatedBytes: nodes[current].allocatedBytes + allocated,
                logicalBytes: nodes[current].logicalBytes + logical,
                itemCount: nodes[current].itemCount + items,
                children: nodes[current].children
            )
            if current == 0 { break }
            current = Int(nodes[current].parent)
        }
    }
    
    func buildStore() -> TreeStore {
        return TreeStore(nodes: nodes)
    }
}

import SwiftUI
import ScannerCore
import AppKit

public enum AppState {
    case start
    case scanning
    case results
}

@MainActor
@Observable
public final class AppModel {
    public var currentState: AppState = .start
    
    // Scan context
    public var rootURL: URL?
    public var hasFDA: Bool = false
    public var volumeInfo: VolumeInfo?
    public var currentPath: String = ""
    public var scannedBytes: UInt64 = 0
    public var scannedFiles: Int = 0
    private var scanTask: Task<Void, Never>?
    
    // Results
    public var treeStore: TreeStore?
    public var lastError: String?
    public var focusID: UInt32 = 0
    public var selectedID: UInt32? = nil
    
    // Derived UI state
    public var currentSegments: [Segment] = []
    public var currentChildren: [Node] = []
    
    // Collector State
    public var collectorNodes: Set<UInt32> = []
    
    public var currentTotalBytes: UInt64 {
        guard let store = treeStore, store.nodes.count > Int(focusID) else { return 0 }
        let scanned = store.nodes[Int(focusID)].allocatedBytes
        if focusID == 0, let vol = volumeInfo {
            return max(vol.capacity, scanned + vol.free)
        }
        return scanned
    }
    
    public var collectorTotalSize: UInt64 {
        guard let store = treeStore else { return 0 }
        return collectorNodes.reduce(0) { $0 + store.nodes[Int($1)].allocatedBytes }
    }
    
    public init() {}
    
    public func startScan(url: URL) {
        rootURL = url
        hasFDA = Permissions.hasFullDiskAccess()
        volumeInfo = VolumeService.info(for: url)
        
        currentState = .scanning
        scannedBytes = 0
        scannedFiles = 0
        
        let scanner = Scanner()
        var options = ScanOptions()
        options.lookInsidePackages = UserDefaults.standard.bool(forKey: "lookInsidePackages")
        // AppStorage booleans default to false if absent, but our includeHiddenFiles default should be true.
        // If it's not set in standard, it returns false. So we should register default:
        UserDefaults.standard.register(defaults: ["includeHiddenFiles": true])
        options.includeHiddenFiles = UserDefaults.standard.bool(forKey: "includeHiddenFiles")
        
        let stream = scanner.scan(root: url, options: options)
        
        scanTask = Task {
            var lastUpdate = Date()
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .progress(let fileCount, let bytes, let path):
                    let now = Date()
                    if now.timeIntervalSince(lastUpdate) > 0.1 {
                        self.scannedFiles = fileCount
                        self.scannedBytes = bytes
                        self.currentPath = path
                        lastUpdate = now
                    }
                case .done(let store):
                    self.treeStore = store
                    self.focusID = 0
                    self.updateFocus()
                    self.currentState = .results
                case .error(let path, let reason):
                    print("Error: \(path) - \(reason)")
                }
            }
        }
    }
    
    public func stopScan() {
        scanTask?.cancel()
        if treeStore != nil {
            currentState = .results
        } else {
            currentState = .start
        }
    }
    
    public func updateFocus() {
        guard let store = treeStore else { return }
        currentSegments = store.segments(for: focusID, maxDepth: 6, minAngleDegrees: 1.0, volumeInfo: focusID == 0 ? volumeInfo : nil)
        
        let node = store.nodes[Int(focusID)]
        var children = node.children.map { store.nodes[Int($0)] }
        // Default sort by size
        children.sort { $0.allocatedBytes > $1.allocatedBytes }
        
        // F6: Virtual Nodes
        if focusID == 0, let vol = volumeInfo {
            let scannedBytes = node.allocatedBytes
            let actualTotal = max(vol.capacity, scannedBytes + vol.free)
            
            var purgeableBytes = vol.purgeable
            var freeBytes = vol.free
            if purgeableBytes > freeBytes { purgeableBytes = 0 }
            let strictFree = freeBytes - purgeableBytes
            
            let hiddenBytes = (actualTotal > scannedBytes + freeBytes) ? actualTotal - scannedBytes - freeBytes : 0
            
            if hiddenBytes > 0 {
                let hiddenNode = Node(id: UInt32.max - 1, parent: 0, nameBytes: Array("hidden space...".utf8), kind: 5, flags: 0, allocatedBytes: hiddenBytes, logicalBytes: hiddenBytes, itemCount: 0, children: 0..<0)
                children.append(hiddenNode)
            }
            if purgeableBytes > 0 {
                let purgeableNode = Node(id: UInt32.max - 2, parent: 0, nameBytes: Array("purgeable space".utf8), kind: 6, flags: 0, allocatedBytes: purgeableBytes, logicalBytes: purgeableBytes, itemCount: 0, children: 0..<0)
                children.append(purgeableNode)
            }
            if strictFree > 0 {
                let freeNode = Node(id: UInt32.max, parent: 0, nameBytes: Array("free space".utf8), kind: 4, flags: 0, allocatedBytes: strictFree, logicalBytes: strictFree, itemCount: 0, children: 0..<0)
                children.append(freeNode)
            }
        }
        
        self.currentChildren = children
    }
    
    public func drillIn(to nodeID: UInt32) {
        focusID = nodeID
        selectedID = nil
        updateFocus()
    }
    
    public func goUp() {
        guard let store = treeStore, focusID != 0 else {
            currentState = .start
            return 
        }
        focusID = store.nodes[Int(focusID)].parent
        selectedID = nil
        updateFocus()
    }
    
    // System Actions (F6)
    public func buildURL(for nodeID: UInt32) -> URL? {
        guard let store = treeStore, let root = rootURL else { return nil }
        var parts: [String] = []
        var current = Int(nodeID)
        
        while current != 0 {
            let name = String(decoding: store.nodes[current].nameBytes, as: UTF8.self)
            parts.append(name)
            current = Int(store.nodes[current].parent)
        }
        
        var url = root
        for part in parts.reversed() {
            url = url.appendingPathComponent(part)
        }
        return url
    }
    
    public func revealInFinder(nodeID: UInt32) {
        if let url = buildURL(for: nodeID) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    public func name(for nodeID: UInt32) -> String {
        guard let store = treeStore else { return "" }
        return String(decoding: store.nodes[Int(nodeID)].nameBytes, as: UTF8.self)
    }
    
    public func addToCollector(nodeID: UInt32) {
        guard let store = treeStore else { return }
        
        // F7.2 Deduplication: Reject if any ancestor is already in the collector
        var current = Int(store.nodes[Int(nodeID)].parent)
        while current != 0 {
            if collectorNodes.contains(UInt32(current)) { return }
            current = Int(store.nodes[current].parent)
        }
        
        // F7.2 Deduplication: Remove any descendants already in the collector
        let toRemove = collectorNodes.filter { queuedID in
            var qCur = Int(store.nodes[Int(queuedID)].parent)
            while qCur != 0 {
                if qCur == Int(nodeID) { return true }
                qCur = Int(store.nodes[qCur].parent)
            }
            return false
        }
        collectorNodes.subtract(toRemove)
        collectorNodes.insert(nodeID)
    }
    
    public func removeFromCollector(nodeID: UInt32) {
        collectorNodes.remove(nodeID)
    }
    
    public func deleteNode(_ nodeID: UInt32, immediately: Bool = false, force: Bool = false) async {
        guard treeStore != nil, let url = buildURL(for: nodeID) else { return }
        
        if !force {
            let runningBundles = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path.lowercased() }
            let targetPath = url.resolvingSymlinksInPath().path.lowercased()
            for bundle in runningBundles {
                if targetPath == bundle || targetPath.hasPrefix(bundle + "/") {
                    DispatchQueue.main.async {
                        self.lastError = "Cannot delete:\n\(url.lastPathComponent) is part of a currently running application."
                    }
                    return
                }
            }
        }
        
        let result = immediately ? FileActions.deleteNow([url]).first : FileActions.trash([url]).first
        if let res = result {
            switch res {
            case .success(_):
                // Optional: remove from collector if it was there
                collectorNodes.remove(nodeID)
                // Optional: UI trigger
                DispatchQueue.main.async {
                    self.updateFocus()
                }
            case .failure(let u, let err):
                DispatchQueue.main.async {
                    self.lastError = "Deletion failed:\n\(u.lastPathComponent): \(err)"
                }
            }
        }
    }
    
    public func deleteCollected(immediately: Bool = false, force: Bool = false) async {
        guard treeStore != nil else { return }
        let urls = collectorNodes.compactMap { buildURL(for: $0) }
        
        // F7.7: Warn if an item is inside a running app's bundle
        if !force {
            let runningBundles = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path.lowercased() }
            
            for url in urls {
                let targetPath = url.resolvingSymlinksInPath().path.lowercased()
                for bundle in runningBundles {
                    if targetPath == bundle || targetPath.hasPrefix(bundle + "/") {
                        DispatchQueue.main.async {
                            self.lastError = "Cannot delete:\n\(url.lastPathComponent) is part of a currently running application."
                        }
                        return 
                    }
                }
            }
        }
        
        let results = immediately ? FileActions.deleteNow(urls) : FileActions.trash(urls)
        
        var errorMessages = [String]()
        
        for result in results {
            switch result {
            case .success(let url):
                if let id = collectorNodes.first(where: { buildURL(for: $0) == url }) {
                    collectorNodes.remove(id)
                }
            case .failure(let url, let err):
                errorMessages.append("\(url.lastPathComponent): \(err)")
            }
        }
        
        if !errorMessages.isEmpty {
            DispatchQueue.main.async {
                self.lastError = "Deletion failed:\n" + errorMessages.joined(separator: "\n")
            }
        }
        
        // In-place tree re-flow (F7.6) would go here.
        updateFocus()
    }
}

import Foundation

public struct Node: Sendable {
    public let id: UInt32
    public let parent: UInt32
    public let nameBytes: [UInt8]
    public let kind: UInt8
    public let flags: UInt8
    public var allocatedBytes: UInt64
    public var logicalBytes: UInt64
    public var itemCount: UInt32
    public var children: Range<UInt32>
    
    public init(id: UInt32, parent: UInt32, nameBytes: [UInt8], kind: UInt8, flags: UInt8, allocatedBytes: UInt64, logicalBytes: UInt64, itemCount: UInt32, children: Range<UInt32>) {
        self.id = id
        self.parent = parent
        self.nameBytes = nameBytes
        self.kind = kind
        self.flags = flags
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.itemCount = itemCount
        self.children = children
    }
}

public enum NodeKind: UInt8, Sendable {
    case file = 0, dir, package, symlink, free, hidden, purgeable, smallerObjects
}

public struct NodeFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    
    public static let unreadable = NodeFlags(rawValue: 1 << 0)
    public static let hardLinkDeduped = NodeFlags(rawValue: 1 << 1)
    public static let package = NodeFlags(rawValue: 1 << 2)
}

public struct ScanOptions: Sendable {
    public var lookInsidePackages: Bool = false
    public var includeHiddenFiles: Bool = true
    public var crossVolumes: Bool = false
    public init() {}
}

public final class TreeStore: Sendable {
    public let nodes: [Node]
    public init(nodes: [Node]) { self.nodes = nodes }
}

public enum ScanEvent: Sendable {
    case progress(fileCount: Int, bytes: UInt64, currentPath: String)
    case done(store: TreeStore)
    case error(path: String, reason: String)
}

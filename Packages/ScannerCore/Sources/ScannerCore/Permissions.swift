import Foundation
import Darwin

public struct VolumeInfo: Sendable, Equatable {
    public let capacity: UInt64
    public let free: UInt64
    public let purgeable: UInt64
    
    public init(capacity: UInt64, free: UInt64, purgeable: UInt64) {
        self.capacity = capacity
        self.free = free
        self.purgeable = purgeable
    }
}

public struct Permissions: Sendable {
    public static func hasFullDiskAccess() -> Bool {
        let testPath = "/Library/Application Support/com.apple.TCC"
        let dir = opendir(testPath)
        if let dir = dir {
            closedir(dir)
            return true
        }
        return false
    }
    
    public static func openFDASettings() {
        let urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [urlString]
        try? process.run()
    }
}

public struct VolumeService: Sendable {
    public static func info(for url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        
        let capacity = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacity ?? 0)
        let important = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        
        let purgeable = important > free ? important - free : 0
        
        return VolumeInfo(capacity: capacity, free: free, purgeable: purgeable)
    }
}

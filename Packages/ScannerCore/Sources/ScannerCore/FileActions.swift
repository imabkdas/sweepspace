import Foundation
import Darwin

public enum ProtectedReason: String, Sendable, Equatable {
    case volumeRoot = "Cannot delete a volume root."
    case system = "System folders are protected."
    case userHome = "Cannot delete your home folder."
    case sip = "Protected by System Integrity Protection."
}

public enum ItemResult: Sendable, Equatable {
    case success(URL)
    case failure(URL, String)
}

public struct FileActions {
    public static func isProtected(_ url: URL) -> ProtectedReason? {
        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path
        
        let lowerPath = path.lowercased()
        
        if lowerPath == "/" { return .volumeRoot }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path.lowercased()
        if lowerPath == home || lowerPath == home + "/" { return .userHome }
        
        let systemPrefixes = [
            "/system", "/usr", "/bin", "/sbin", "/library", "/private/var/db"
        ]
        
        for prefix in systemPrefixes {
            if lowerPath == prefix || lowerPath.hasPrefix(prefix + "/") {
                return .system
            }
        }
        
        var statBuf = stat()
        if lstat(path, &statBuf) == 0 {
            // Check for system restricted flag (SIP)
            if statBuf.st_flags & UInt32(SF_RESTRICTED) != 0 {
                return .sip
            }
        }
        
        return nil
    }
    
    public static func trash(_ urls: [URL]) -> [ItemResult] {
        var results: [ItemResult] = []
        for url in urls {
            if let reason = isProtected(url) {
                results.append(.failure(url, reason.rawValue))
                continue
            }
            do {
                var outURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &outURL)
                results.append(.success(url))
            } catch {
                results.append(.failure(url, error.localizedDescription))
            }
        }
        return results
    }
    
    public static func deleteNow(_ urls: [URL]) -> [ItemResult] {
        var results: [ItemResult] = []
        for url in urls {
            if let reason = isProtected(url) {
                results.append(.failure(url, reason.rawValue))
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                results.append(.success(url))
            } catch {
                results.append(.failure(url, error.localizedDescription))
            }
        }
        return results
    }
}

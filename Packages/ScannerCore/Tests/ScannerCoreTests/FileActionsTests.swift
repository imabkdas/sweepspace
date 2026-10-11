import Testing
import Foundation
@testable import ScannerCore

@Suite struct FileActionsTests {
    @Test func testProtectedPaths() async throws {
        // System paths
        #expect(FileActions.isProtected(URL(fileURLWithPath: "/System")) == .system)
        #expect(FileActions.isProtected(URL(fileURLWithPath: "/usr/local/bin")) == .system)
        #expect(FileActions.isProtected(URL(fileURLWithPath: "/Library/Application Support")) == .system)
        
        // Root
        #expect(FileActions.isProtected(URL(fileURLWithPath: "/")) == .volumeRoot)
        
        // User home
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(FileActions.isProtected(home) == .userHome)
        
        // Allowed path
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        #expect(FileActions.isProtected(tempDir) == nil)
    }
    
    @Test func testTrashSafety() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }
        
        let testFile = tempRoot.appendingPathComponent("test.txt")
        try "hello".write(to: testFile, atomically: true, encoding: .utf8)
        
        let results = FileActions.trash([testFile])
        #expect(results.count == 1)
        
        if case .success(let url) = results[0] {
            #expect(url == testFile)
            #expect(!fm.fileExists(atPath: testFile.path))
        } else {
            Issue.record("Trash action failed")
        }
    }
}

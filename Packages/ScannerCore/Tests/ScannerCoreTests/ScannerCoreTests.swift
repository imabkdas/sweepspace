import Testing
import Foundation
@testable import ScannerCore

@Suite struct ScannerTests {
    
    @Test func testScannerEdgeCases() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Clean up after test
        defer {
            // Restore permissions so it can be deleted
            let unreadableDir = tempDir.appendingPathComponent("secret")
            try? fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: unreadableDir.path)
            try? fm.removeItem(at: tempDir)
        }
        
        // Edge Case 1: Emoji file names
        let emojiPath = tempDir.appendingPathComponent("📁🚀.txt")
        try "hello".write(to: emojiPath, atomically: true, encoding: .utf8)
        
        // Edge Case 2: Symlink loop (Scanner should ignore symlinks)
        let linkA = tempDir.appendingPathComponent("linkA")
        let linkB = tempDir.appendingPathComponent("linkB")
        try fm.createSymbolicLink(at: linkA, withDestinationURL: linkB)
        try fm.createSymbolicLink(at: linkB, withDestinationURL: linkA)
        
        // Edge Case 3: Unreadable directory
        let unreadableDir = tempDir.appendingPathComponent("secret")
        try fm.createDirectory(at: unreadableDir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableDir.path)
        
        // Edge Case 4: Deep nesting (Iterative safety check)
        var deepPath = tempDir
        for _ in 0..<100 {
            deepPath = deepPath.appendingPathComponent("dir")
            try fm.createDirectory(at: deepPath, withIntermediateDirectories: true)
        }
        
        // Run Scanner
        let scanner = Scanner()
        let stream = scanner.scan(root: tempDir, options: ScanOptions())
        
        var finalStore: TreeStore?
        for await event in stream {
            if case .done(let store) = event {
                finalStore = store
            }
        }
        
        let store = try #require(finalStore)
        let root = store.nodes[0]
        
        #expect(root.itemCount > 0, "Root should have items")
        
        // Verify unreadable dir was flagged
        let unreadableNode = store.nodes.first { 
            String(bytes: $0.nameBytes, encoding: .utf8) == "secret" 
        }
        let unreadableFound = try #require(unreadableNode)
        #expect(NodeFlags(rawValue: unreadableFound.flags).contains(.unreadable), "Secret folder should be flagged as unreadable")
        
        // Verify emoji file was safely processed
        let emojiNode = store.nodes.first { 
            String(bytes: $0.nameBytes, encoding: .utf8) == "📁🚀.txt" 
        }
        #expect(emojiNode != nil, "Emoji file should be scanned correctly")
    }
}

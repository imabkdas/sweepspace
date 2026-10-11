import Testing
@testable import ScannerCore

@Suite struct LayoutTests {
    @Test func testSegmentAngles() async throws {
        // Manually build a small tree
        // Root (100) -> Child A (60) -> Grandchild A1 (60)
        //            -> Child B (39)
        //            -> Child C (1)  <- Merged into smaller objects if < 1% (3.6 deg)
        let root = Node(id: 0, parent: 0, nameBytes: [], kind: 1, flags: 0, allocatedBytes: 100, logicalBytes: 100, itemCount: 4, children: 1..<4)
        let childA = Node(id: 1, parent: 0, nameBytes: [65], kind: 1, flags: 0, allocatedBytes: 60, logicalBytes: 60, itemCount: 1, children: 4..<5)
        let childB = Node(id: 2, parent: 0, nameBytes: [66], kind: 0, flags: 0, allocatedBytes: 39, logicalBytes: 39, itemCount: 0, children: 0..<0)
        let childC = Node(id: 3, parent: 0, nameBytes: [67], kind: 0, flags: 0, allocatedBytes: 1, logicalBytes: 1, itemCount: 0, children: 0..<0)
        let grandChildA1 = Node(id: 4, parent: 1, nameBytes: [68], kind: 0, flags: 0, allocatedBytes: 60, logicalBytes: 60, itemCount: 0, children: 0..<0)
        
        let store = TreeStore(nodes: [root, childA, childB, childC, grandChildA1])
        
        // 1 degree threshold = 1/360 * 100 = 0.27 size. Child C (1) > 0.27, so NO merge if minAngle is 1.0!
        // Let's set minAngle to 5.0 (which is 1.38 size limit). Child C (1) should be merged.
        let segments = store.segments(for: 0, maxDepth: 6, minAngleDegrees: 5.0)
        
        #expect(segments.count == 4)
        
        // Find Child A
        let segA = try #require(segments.first { $0.nodeID == 1 })
        #expect(segA.startDegrees == 0.0)
        #expect(segA.endDegrees == 216.0) // 60/100 * 360
        #expect(segA.ring == 1)
        
        // Find Child B
        let segB = try #require(segments.first { $0.nodeID == 2 })
        #expect(segB.startDegrees == 216.0)
        #expect(segB.endDegrees == 356.4) // 39/100 * 360 = 140.4 + 216
        
        // Find Smaller Objects (Child C merged)
        let segC = try #require(segments.first { $0.kind == NodeKind.smallerObjects.rawValue })
        #expect(segC.startDegrees == 356.4)
        #expect(segC.endDegrees == 360.0)
        
        // Find Grandchild A1
        let segA1 = try #require(segments.first { $0.nodeID == 4 })
        #expect(segA1.startDegrees == 0.0)
        #expect(segA1.endDegrees == 216.0)
        #expect(segA1.ring == 2)
    }
}

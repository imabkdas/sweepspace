import Testing
import Foundation
@testable import ScannerCore

@Suite struct HitTesterTests {
    @Test func testHitTesting() async throws {
        let tester = HitTester(centerRadius: 40.0, ringWidth: 30.0)
        let cx = 100.0, cy = 100.0
        
        let segments = [
            // Top right quadrant (0 to 90 degrees)
            Segment(nodeID: 1, ring: 1, startDegrees: 0, endDegrees: 90, kind: 1, hueKey: 0),
            // Bottom half (90 to 270)
            Segment(nodeID: 2, ring: 1, startDegrees: 90, endDegrees: 270, kind: 1, hueKey: 1),
            // Boundary wrapping segment (350 to 10 degrees)
            Segment(nodeID: 3, ring: 2, startDegrees: 350, endDegrees: 10, kind: 1, hueKey: 2)
        ]
        
        // Center hit
        #expect(tester.hitTest(x: 100, y: 100, centerX: cx, centerY: cy, segments: segments) == 0)
        
        // Hit top-right quadrant (Node 1) -> 45 degrees
        // dx = sin(45) * 55, dy = -cos(45) * 55
        #expect(tester.hitTest(x: 100 + 38.89, y: 100 - 38.89, centerX: cx, centerY: cy, segments: segments) == 1)
        
        // Hit bottom half (Node 2) -> 180 degrees (straight down)
        #expect(tester.hitTest(x: 100, y: 100 + 55, centerX: cx, centerY: cy, segments: segments) == 2)
        
        // Hit boundary wrapper (Node 3) -> ring 2, 355 degrees (slightly left of top)
        #expect(tester.hitTest(x: 100 - 5.0, y: 100 - 80, centerX: cx, centerY: cy, segments: segments) == 3)
        
        // Miss completely (outside rings)
        #expect(tester.hitTest(x: 100, y: 500, centerX: cx, centerY: cy, segments: segments) == nil)
    }
}

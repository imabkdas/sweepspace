import Foundation

public struct HitTester: Sendable {
    public let centerRadius: Double
    public let ringWidth: Double
    
    public init(centerRadius: Double = 40.0, ringWidth: Double = 32.0) {
        self.centerRadius = centerRadius
        self.ringWidth = ringWidth
    }
    
    // Returns the nodeID hit by the coordinates, or 0 for the center disc, or nil for empty space.
    public func hitTest(x: Double, y: Double, centerX: Double, centerY: Double, segments: [Segment]) -> UInt32? {
        let dx = x - centerX
        let dy = y - centerY
        let radius = sqrt(dx*dx + dy*dy)
        
        if radius <= centerRadius { return 0 } // Center disc
        
        // Convert to polar. In UI, 0 degrees is often "top", so we adjust by +90.
        var angle = atan2(dy, dx) * 180 / .pi
        angle += 90 
        
        // Normalize angle to 0..<360
        if angle < 0 { angle += 360 }
        if angle >= 360 { angle -= 360 }
        
        let ringIndex = Int((radius - centerRadius) / ringWidth) + 1
        guard ringIndex > 0 else { return nil }
        
        for seg in segments where seg.ring == ringIndex {
            // Check boundary wrapping if start > end (edge case)
            if seg.startDegrees <= seg.endDegrees {
                if angle >= seg.startDegrees && angle < seg.endDegrees {
                    return seg.nodeID
                }
            } else {
                // Wraps across the 0/360 boundary
                if angle >= seg.startDegrees || angle < seg.endDegrees {
                    return seg.nodeID
                }
            }
        }
        
        return nil
    }
}

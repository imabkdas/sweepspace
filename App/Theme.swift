import SwiftUI

public struct Theme {
    // Generate a consistent, depth-aware color based on the hueKey (branch index) and ring depth
    public static func color(for hueKey: Int, ring: Int, kind: UInt8) -> Color {
        // Special case for free/hidden/purgeable space (0 = smaller objects, etc)
        if kind == 4 || kind == 5 || kind == 6 {
            return Color.gray.opacity(0.3) // In a full implementation, this uses a hatched fill
        }
        
        // Root / Center
        if hueKey < 0 {
            return Color.gray.opacity(0.8)
        }
        
        // Base hues mapped around the color wheel to ensure distinct branches
        let hues: [Double] = [0.6, 0.1, 0.3, 0.8, 0.5, 0.9, 0.15, 0.45, 0.7, 0.2]
        let baseHue = hues[hueKey % hues.count]
        
        // Saturation drops slightly as rings get deeper to create a gradient effect
        let sat = max(0.3, 0.85 - Double(ring) * 0.08)
        
        // Lightness shifts to make deeper rings distinct
        let lit = min(0.8, 0.5 + Double(ring) * 0.05)
        
        return Color(hue: baseHue, saturation: sat, brightness: lit)
    }
}

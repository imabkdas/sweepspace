import SwiftUI
import ScannerCore

public struct SunburstView: View {
    public var segments: [Segment]
    public var focusID: UInt32
    public var selectedID: UInt32?
    
    public var onHover: (UInt32?) -> Void
    public var onSelect: (UInt32) -> Void
    public var onUp: () -> Void
    public var onReveal: (UInt32) -> Void
    public var onCollect: (UInt32) -> Void
    public var onTrash: (UInt32) -> Void
    public var onDelete: (UInt32) -> Void
    
    @State private var hoveredID: UInt32?
    
    let centerRadius: CGFloat = 60.0
    let ringWidth: CGFloat = 40.0
    
    public init(
        segments: [Segment],
        focusID: UInt32,
        selectedID: UInt32? = nil,
        onHover: @escaping (UInt32?) -> Void = { _ in },
        onSelect: @escaping (UInt32) -> Void = { _ in },
        onUp: @escaping () -> Void = {},
        onReveal: @escaping (UInt32) -> Void = { _ in },
        onCollect: @escaping (UInt32) -> Void = { _ in },
        onTrash: @escaping (UInt32) -> Void = { _ in },
        onDelete: @escaping (UInt32) -> Void = { _ in }
    ) {
        self.segments = segments
        self.focusID = focusID
        self.selectedID = selectedID
        self.onHover = onHover
        self.onSelect = onSelect
        self.onUp = onUp
        self.onReveal = onReveal
        self.onCollect = onCollect
        self.onTrash = onTrash
        self.onDelete = onDelete
    }
    
    public var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            
            Canvas { context, size in
                var centerPath = Path()
                centerPath.addArc(
                    center: center,
                    radius: centerRadius,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                
                let isCenterHovered = (hoveredID == 0)
                context.fill(centerPath, with: .color(isCenterHovered ? .gray : .gray.opacity(0.8)))
                context.stroke(centerPath, with: .color(.black.opacity(0.5)), lineWidth: 1)
                
                for seg in segments {
                    let inner = centerRadius + CGFloat(seg.ring - 1) * ringWidth
                    let outer = inner + ringWidth
                    
                    var path = Path()
                    path.addArc(center: center, radius: inner, startAngle: .degrees(seg.startDegrees - 90), endAngle: .degrees(seg.endDegrees - 90), clockwise: false)
                    path.addArc(center: center, radius: outer, startAngle: .degrees(seg.endDegrees - 90), endAngle: .degrees(seg.startDegrees - 90), clockwise: true)
                    path.closeSubpath()
                    
                    let baseColor = Theme.color(for: seg.hueKey, ring: seg.ring, kind: seg.kind)
                    var finalColor = baseColor
                    
                    if let hid = hoveredID {
                        if hid == seg.nodeID {
                            finalColor = baseColor
                        } else {
                            finalColor = baseColor.opacity(0.3)
                        }
                    } else if let sid = selectedID {
                        if sid == seg.nodeID {
                            finalColor = baseColor
                        } else {
                            finalColor = baseColor.opacity(0.5)
                        }
                    }
                    
                    context.fill(path, with: .color(finalColor))
                    context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 0.5)
                }
            }
            .onContinuousHover { phase in
                let tester = HitTester(centerRadius: Double(centerRadius), ringWidth: Double(ringWidth))
                switch phase {
                case .active(let loc):
                    let hit = tester.hitTest(
                        x: Double(loc.x),
                        y: Double(loc.y),
                        centerX: Double(center.x),
                        centerY: Double(center.y),
                        segments: segments
                    )
                    
                    if hoveredID != hit {
                        hoveredID = hit
                        onHover(hit)
                    }
                case .ended:
                    if hoveredID != nil {
                        hoveredID = nil
                        onHover(nil)
                    }
                }
            }
            .contextMenu {
                if let target = hoveredID ?? selectedID, target != 0 {
                    Button("Reveal in Finder") {
                        onReveal(target)
                    }
                    Button("Move to Collector Tray") {
                        onCollect(target)
                    }
                    Divider()
                    Button("Move to Trash") {
                        onTrash(target)
                    }
                    Button("Delete Immediately") {
                        onDelete(target)
                    }
                }
            }
            .gesture(
                SpatialTapGesture(count: 1).onEnded { event in
                    let tester = HitTester(centerRadius: Double(centerRadius), ringWidth: Double(ringWidth))
                    let hit = tester.hitTest(
                        x: Double(event.location.x),
                        y: Double(event.location.y),
                        centerX: Double(center.x),
                        centerY: Double(center.y),
                        segments: segments
                    )
                    
                    if let hitID = hit {
                        if hitID == 0 {
                            onUp()
                        } else {
                            onSelect(hitID)
                        }
                    }
                }
            )
        }
    }
}

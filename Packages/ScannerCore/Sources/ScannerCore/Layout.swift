import Foundation

public struct Segment: Sendable, Equatable {
    public let nodeID: UInt32
    public let ring: Int
    public let startDegrees: Double
    public let endDegrees: Double
    public let kind: UInt8
    public let hueKey: Int
    
    public init(nodeID: UInt32, ring: Int, startDegrees: Double, endDegrees: Double, kind: UInt8, hueKey: Int) {
        self.nodeID = nodeID
        self.ring = ring
        self.startDegrees = startDegrees
        self.endDegrees = endDegrees
        self.kind = kind
        self.hueKey = hueKey
    }
}

extension TreeStore {
    public func segments(for rootID: UInt32, maxDepth: Int = 6, minAngleDegrees: Double = 1.0, volumeInfo: VolumeInfo? = nil) -> [Segment] {
        var result: [Segment] = []
        result.reserveCapacity(5000)
        
        guard Int(rootID) < nodes.count else { return [] }
        let rootNode = nodes[Int(rootID)]
        guard rootNode.allocatedBytes > 0 else { return [] }
        
        var effectiveTotalAngle = 360.0
        var rootRatio = 1.0
        
        if let vInfo = volumeInfo {
            let actualTotal = max(vInfo.capacity, rootNode.allocatedBytes + vInfo.free)
            rootRatio = Double(rootNode.allocatedBytes) / Double(actualTotal)
            effectiveTotalAngle = 360.0 * rootRatio
        }
        
        struct State {
            let nodeID: UInt32
            let ring: Int
            let startAngle: Double
            let totalAngle: Double
            let hueKey: Int
        }
        
        // Start at ring 0 (which is the center disc, but we only return rings 1+ as segments)
        var stack: [State] = [
            State(nodeID: rootID, ring: 0, startAngle: 0.0, totalAngle: effectiveTotalAngle, hueKey: -1)
        ]
        
        while let current = stack.popLast() {
            // Stop if we hit max depth or segment limit
            if current.ring > maxDepth { continue }
            if result.count >= 5000 { break }
            
            let node = nodes[Int(current.nodeID)]
            
            // Emit segment (skip the center disc itself, UI handles it separately)
            if current.ring > 0 {
                result.append(Segment(
                    nodeID: current.nodeID,
                    ring: current.ring,
                    startDegrees: current.startAngle,
                    endDegrees: current.startAngle + current.totalAngle,
                    kind: node.kind,
                    hueKey: current.hueKey
                ))
            }
            
            // Stop recursing if children would be beyond max depth
            if current.ring >= maxDepth { continue }
            
            let childrenRange = node.children
            if childrenRange.isEmpty { continue }
            
            // Fetch and sort children deterministically: size descending, name ascending
            var childNodes = childrenRange.map { nodes[Int($0)] }
            childNodes.sort { 
                if $0.allocatedBytes != $1.allocatedBytes {
                    return $0.allocatedBytes > $1.allocatedBytes
                }
                for (a, b) in zip($0.nameBytes, $1.nameBytes) {
                    if a != b { return a < b }
                }
                return $0.nameBytes.count < $1.nameBytes.count
            }
            
            var currentAngle = current.startAngle
            var mergedSize: UInt64 = 0
            var mergedStartAngle: Double = -1
            
            var nextStack: [State] = []
            
            for (idx, child) in childNodes.enumerated() {
                // Defensive division
                guard node.allocatedBytes > 0 else { continue }
                
                let childRatio = Double(child.allocatedBytes) / Double(node.allocatedBytes)
                let childAngle = current.totalAngle * childRatio
                
                // Assign a hueKey based on the top-level branch (ring 1)
                let hue = (current.ring == 0) ? idx : current.hueKey
                
                if childAngle < minAngleDegrees {
                    // Start accumulating small items
                    if mergedStartAngle == -1 {
                        mergedStartAngle = currentAngle
                    }
                    mergedSize += child.allocatedBytes
                } else {
                    // Valid segment, push to stack to process its children later
                    nextStack.append(State(
                        nodeID: child.id,
                        ring: current.ring + 1,
                        startAngle: currentAngle,
                        totalAngle: childAngle,
                        hueKey: hue
                    ))
                }
                
                currentAngle += childAngle
            }
            
            // Emit the "Smaller Objects" merged segment if there are any
            if mergedSize > 0 && mergedStartAngle != -1 {
                let mergedRatio = Double(mergedSize) / Double(node.allocatedBytes)
                let mergedAngle = current.totalAngle * mergedRatio
                
                if result.count < 5000 {
                    result.append(Segment(
                        nodeID: current.nodeID, // Use parent ID to represent the collection
                        ring: current.ring + 1,
                        startDegrees: mergedStartAngle,
                        endDegrees: mergedStartAngle + mergedAngle,
                        kind: NodeKind.smallerObjects.rawValue,
                        hueKey: current.ring == 0 ? childNodes.count : current.hueKey
                    ))
                }
            }
            
            // Push children in reverse order so DFS pops them sequentially (largest first)
            stack.append(contentsOf: nextStack.reversed())
        }
        
        // M6: Inject virtual segments for Volume Free/Hidden space
        if let vInfo = volumeInfo, rootID == 0 {
            let actualTotal = max(vInfo.capacity, rootNode.allocatedBytes + vInfo.free)
            
            let hiddenBytes = (vInfo.capacity > vInfo.free + rootNode.allocatedBytes) ? (vInfo.capacity - vInfo.free - rootNode.allocatedBytes) : 0
            
            let strictFree = (vInfo.free > vInfo.purgeable) ? vInfo.free - vInfo.purgeable : 0
            let purgeable = vInfo.purgeable
            
            var currentVirtualAngle = effectiveTotalAngle
            
            // Hidden Space (Kind 5)
            if hiddenBytes > 0 {
                let hiddenAngle = 360.0 * (Double(hiddenBytes) / Double(actualTotal))
                result.append(Segment(nodeID: UInt32.max - 1, ring: 1, startDegrees: currentVirtualAngle, endDegrees: currentVirtualAngle + hiddenAngle, kind: 5, hueKey: -1))
                currentVirtualAngle += hiddenAngle
            }
            
            // Purgeable Space (Kind 6)
            if purgeable > 0 {
                let purgeableAngle = 360.0 * (Double(purgeable) / Double(actualTotal))
                result.append(Segment(nodeID: UInt32.max - 2, ring: 1, startDegrees: currentVirtualAngle, endDegrees: currentVirtualAngle + purgeableAngle, kind: 6, hueKey: -1))
                currentVirtualAngle += purgeableAngle
            }
            
            // Free Space (Kind 4)
            if strictFree > 0 {
                let freeAngle = 360.0 * (Double(strictFree) / Double(actualTotal))
                result.append(Segment(nodeID: UInt32.max, ring: 1, startDegrees: currentVirtualAngle, endDegrees: currentVirtualAngle + freeAngle, kind: 4, hueKey: -1))
            }
        }
        
        return result
    }
}

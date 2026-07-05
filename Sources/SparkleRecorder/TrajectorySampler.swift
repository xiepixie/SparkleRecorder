import Foundation
import CoreGraphics

public struct DragSnapshot {
    public let event: CGEvent
    public let type: CGEventType
    public let elapsed: Double
}

public class TrajectorySampler {
    private var lastDragTime: TimeInterval = 0
    private var lastDragLocation: CGPoint = .zero
    private var lastSentDragVector: CGPoint = .zero
    private var hasSentDragSinceDown: Bool = false
    public private(set) var lastIgnoredDrag: DragSnapshot? = nil
    
    // Thresholds
    private let timeThreshold: TimeInterval = 0.016 // 60Hz
    private let distThreshold: CGFloat = 2.0
    private let highSpeedDistThreshold: CGFloat = 12.0
    private let angleThreshold: CGFloat = 0.9 // dot product threshold for curve detection
    
    public init() {}
    
    public func reset(location: CGPoint, time: TimeInterval) {
        hasSentDragSinceDown = false
        lastDragTime = time
        lastDragLocation = location
        lastSentDragVector = .zero
        lastIgnoredDrag = nil
    }
    
    public func processMouseDown(location: CGPoint, time: TimeInterval) {
        reset(location: location, time: time)
    }
    
    public func processMouseUp() -> DragSnapshot? {
        let snapshot = lastIgnoredDrag
        lastIgnoredDrag = nil
        return snapshot
    }
    
    public func shouldSampleDrag(event: CGEvent, type: CGEventType, location: CGPoint, time: TimeInterval) -> Bool {
        let dt = time - lastDragTime
        let dx = location.x - lastDragLocation.x
        let dy = location.y - lastDragLocation.y
        let dist2 = dx*dx + dy*dy
        let dist = sqrt(dist2)
        
        // 1. Always sample the first drag
        if !hasSentDragSinceDown {
            acceptSample(location: location, time: time, dx: dx, dy: dy)
            return true
        }
        
        // 2. High-speed protection (if distance is large enough, ignore time threshold)
        if dist >= highSpeedDistThreshold {
            acceptSample(location: location, time: time, dx: dx, dy: dy)
            return true
        }
        
        // 3. Curve protection (check direction change)
        if dist > 1.0 && lastSentDragVector != .zero {
            let len1 = sqrt(lastSentDragVector.x * lastSentDragVector.x + lastSentDragVector.y * lastSentDragVector.y)
            if len1 > 0 {
                let dot = ((dx * lastSentDragVector.x) + (dy * lastSentDragVector.y)) / (dist * len1)
                if dot < angleThreshold {
                    // Significant direction change -> keep sample to preserve curve
                    acceptSample(location: location, time: time, dx: dx, dy: dy)
                    return true
                }
            }
        }
        
        // 4. Default sampling rate
        if dt >= timeThreshold && dist >= distThreshold {
            acceptSample(location: location, time: time, dx: dx, dy: dy)
            return true
        }
        
        // Ignore sample, but save as lastIgnoredDrag
        if let copy = event.copy() {
            lastIgnoredDrag = DragSnapshot(event: copy, type: type, elapsed: time)
        }
        return false
    }
    
    private func acceptSample(location: CGPoint, time: TimeInterval, dx: CGFloat, dy: CGFloat) {
        hasSentDragSinceDown = true
        lastDragTime = time
        lastDragLocation = location
        if dx != 0 || dy != 0 {
            lastSentDragVector = CGPoint(x: dx, y: dy)
        }
        lastIgnoredDrag = nil
    }
}

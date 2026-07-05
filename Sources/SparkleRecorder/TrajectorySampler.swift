import Foundation
import CoreGraphics
import SparkleRecorderCore

public struct DragSnapshot {
    public let event: CGEvent
    public let type: CGEventType
    public let elapsed: Double
}

public class TrajectorySampler {
    private var sampler: RecordingDragSampler
    public private(set) var lastIgnoredDrag: DragSnapshot? = nil

    public init(configuration: RecordingDragSamplingConfiguration = .default) {
        self.sampler = RecordingDragSampler(configuration: configuration)
    }
    
    public func reset(location: CGPoint, time: TimeInterval) {
        sampler.reset(location: location, time: time)
        lastIgnoredDrag = nil
    }
    
    public func processMouseDown(location: CGPoint, time: TimeInterval) {
        reset(location: location, time: time)
    }
    
    public func processMouseUp() -> DragSnapshot? {
        _ = sampler.processMouseUp()
        let snapshot = lastIgnoredDrag
        lastIgnoredDrag = nil
        return snapshot
    }
    
    public func shouldSampleDrag(event: CGEvent, type: CGEventType, location: CGPoint, time: TimeInterval) -> Bool {
        if sampler.processDrag(location: location, time: time).shouldKeep {
            lastIgnoredDrag = nil
            return true
        }
        
        if let copy = event.copy() {
            lastIgnoredDrag = DragSnapshot(event: copy, type: type, elapsed: time)
        }
        return false
    }
}

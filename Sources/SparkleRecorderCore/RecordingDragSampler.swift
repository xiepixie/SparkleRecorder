import CoreGraphics
import Foundation

public struct RecordingDragSamplingConfiguration: Equatable, Sendable {
    public static let `default` = RecordingDragSamplingConfiguration()

    public var timeThreshold: TimeInterval
    public var distanceThreshold: CGFloat
    public var highSpeedDistanceThreshold: CGFloat
    public var angleDotThreshold: CGFloat

    public init(
        timeThreshold: TimeInterval = 0.016,
        distanceThreshold: CGFloat = 2.0,
        highSpeedDistanceThreshold: CGFloat = 12.0,
        angleDotThreshold: CGFloat = 0.9
    ) {
        self.timeThreshold = timeThreshold
        self.distanceThreshold = distanceThreshold
        self.highSpeedDistanceThreshold = highSpeedDistanceThreshold
        self.angleDotThreshold = angleDotThreshold
    }
}

public struct RecordingDragSample: Equatable, Sendable {
    public var location: CGPoint
    public var time: TimeInterval

    public init(location: CGPoint, time: TimeInterval) {
        self.location = location
        self.time = time
    }
}

public enum RecordingDragSamplingReason: Equatable, Sendable {
    case firstDrag
    case highSpeed
    case directionChange
    case threshold
}

public enum RecordingDragSamplingDecision: Equatable, Sendable {
    case keep(RecordingDragSamplingReason)
    case drop

    public var shouldKeep: Bool {
        if case .keep = self { return true }
        return false
    }
}

public struct RecordingDragSampler: Equatable, Sendable {
    public var configuration: RecordingDragSamplingConfiguration
    public private(set) var lastDroppedSample: RecordingDragSample?

    private var lastDragTime: TimeInterval = 0
    private var lastDragLocation: CGPoint = .zero
    private var lastSentDragVector: CGPoint = .zero
    private var hasSentDragSinceDown = false

    public init(configuration: RecordingDragSamplingConfiguration = .default) {
        self.configuration = configuration
    }

    public mutating func reset(location: CGPoint, time: TimeInterval) {
        hasSentDragSinceDown = false
        lastDragTime = time
        lastDragLocation = location
        lastSentDragVector = .zero
        lastDroppedSample = nil
    }

    public mutating func processMouseDown(location: CGPoint, time: TimeInterval) {
        reset(location: location, time: time)
    }

    public mutating func processMouseUp() -> RecordingDragSample? {
        let sample = lastDroppedSample
        lastDroppedSample = nil
        return sample
    }

    @discardableResult
    public mutating func processDrag(location: CGPoint, time: TimeInterval) -> RecordingDragSamplingDecision {
        let sample = RecordingDragSample(location: location, time: time)
        let delta = CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
        let distance = hypot(delta.x, delta.y)

        if !hasSentDragSinceDown {
            acceptSample(location: location, time: time, delta: delta)
            return .keep(.firstDrag)
        }

        if distance >= configuration.highSpeedDistanceThreshold {
            acceptSample(location: location, time: time, delta: delta)
            return .keep(.highSpeed)
        }

        if shouldPreserveDirectionChange(delta: delta, distance: distance) {
            acceptSample(location: location, time: time, delta: delta)
            return .keep(.directionChange)
        }

        let elapsed = time - lastDragTime
        if elapsed >= configuration.timeThreshold, distance >= configuration.distanceThreshold {
            acceptSample(location: location, time: time, delta: delta)
            return .keep(.threshold)
        }

        lastDroppedSample = sample
        return .drop
    }

    private func shouldPreserveDirectionChange(delta: CGPoint, distance: CGFloat) -> Bool {
        guard distance > 1.0, lastSentDragVector != .zero else { return false }

        let lastVectorLength = hypot(lastSentDragVector.x, lastSentDragVector.y)
        guard lastVectorLength > 0 else { return false }

        let dot = ((delta.x * lastSentDragVector.x) + (delta.y * lastSentDragVector.y)) / (distance * lastVectorLength)
        return dot < configuration.angleDotThreshold
    }

    private mutating func acceptSample(location: CGPoint, time: TimeInterval, delta: CGPoint) {
        hasSentDragSinceDown = true
        lastDragTime = time
        lastDragLocation = location
        if delta != .zero {
            lastSentDragVector = delta
        }
        lastDroppedSample = nil
    }
}

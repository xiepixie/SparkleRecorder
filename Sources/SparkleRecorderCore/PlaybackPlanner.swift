import Foundation

public enum PlaybackLoopMode: Equatable, Sendable {
    case finite(Int)
    case continuous

    public var displayLoopCount: Int {
        switch self {
        case .finite(let count):
            return count
        case .continuous:
            return 0
        }
    }

    public var isContinuous: Bool {
        if case .continuous = self {
            return true
        }
        return false
    }
}

public struct PlaybackStep: Equatable, Sendable {
    public var eventIndex: Int
    public var event: RecordedEvent
    public var deltaFromPrevious: TimeInterval
    public var scheduledOffset: TimeInterval
    public var progress: Double

    public init(
        eventIndex: Int,
        event: RecordedEvent,
        deltaFromPrevious: TimeInterval,
        scheduledOffset: TimeInterval,
        progress: Double
    ) {
        self.eventIndex = eventIndex
        self.event = event
        self.deltaFromPrevious = deltaFromPrevious
        self.scheduledOffset = scheduledOffset
        self.progress = progress
    }
}

public struct PlaybackPlan: Equatable, Sendable {
    public var loopMode: PlaybackLoopMode
    public var speed: Double
    public var rawDuration: TimeInterval
    public var scaledLoopDuration: TimeInterval
    public var steps: [PlaybackStep]

    public init(
        loopMode: PlaybackLoopMode,
        speed: Double,
        rawDuration: TimeInterval,
        scaledLoopDuration: TimeInterval,
        steps: [PlaybackStep]
    ) {
        self.loopMode = loopMode
        self.speed = speed
        self.rawDuration = rawDuration
        self.scaledLoopDuration = scaledLoopDuration
        self.steps = steps
    }
}

public enum PlaybackPlanner {
    public static func plan(events: [RecordedEvent], loops: Int, speed: Double) -> PlaybackPlan {
        let sanitizedSpeed = sanitizedSpeed(speed)
        let steps = timeline(events: events, speed: sanitizedSpeed)
        return PlaybackPlan(
            loopMode: loopMode(for: loops),
            speed: sanitizedSpeed,
            rawDuration: events.last?.time ?? 0,
            scaledLoopDuration: steps.last?.scheduledOffset ?? 0,
            steps: steps
        )
    }

    public static func loopMode(for loops: Int) -> PlaybackLoopMode {
        loops <= 0 ? .continuous : .finite(max(1, loops))
    }

    public static func sanitizedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return 1.0 }
        return max(0.1, min(speed, 10.0))
    }

    public static func finiteLoopCount(for loops: Int) -> Int {
        max(1, loops)
    }

    public static func timeline(events: [RecordedEvent], speed: Double) -> [PlaybackStep] {
        let sanitizedSpeed = sanitizedSpeed(speed)
        let rawDuration = events.last?.time ?? 0
        var previousEventTime: TimeInterval = 0
        var scheduledOffset: TimeInterval = 0

        return events.enumerated()
            .compactMap { index, event in
                let delta = max(0, event.time - previousEventTime) / sanitizedSpeed
                previousEventTime = event.time
                
                guard event.isDisabled != true else {
                    return nil
                }
                
                scheduledOffset += delta

                let progress: Double
                if rawDuration > 0 {
                    progress = min(1.0, max(0, event.time / rawDuration))
                } else {
                    progress = 1.0
                }

                return PlaybackStep(
                    eventIndex: index,
                    event: event,
                    deltaFromPrevious: delta,
                    scheduledOffset: scheduledOffset,
                    progress: progress
                )
        }
    }

    public static func targetSurfaceId(for event: RecordedEvent, context: PlaybackContext) -> String {
        if let surfaceId = event.surfaceId, context.surfaces[surfaceId] != nil {
            return surfaceId
        }
        if let firstKey = context.surfaces.keys.first {
            return firstKey
        }
        return event.surfaceId ?? "surface-1"
    }
}

import Foundation

public struct RecordingTimebase: Equatable, Sendable {
    public var numer: UInt64
    public var denom: UInt64

    public init(numer: UInt64, denom: UInt64) {
        self.numer = numer
        self.denom = denom == 0 ? 1 : denom
    }
}

public struct RecordingEventTime: Equatable, Sendable {
    public var baseTimestamp: UInt64
    public var elapsed: TimeInterval

    public init(baseTimestamp: UInt64, elapsed: TimeInterval) {
        self.baseTimestamp = baseTimestamp
        self.elapsed = elapsed
    }
}

public enum RecordingTimeline {
    public static func secondsFromNanoseconds(_ nanoseconds: UInt64) -> TimeInterval {
        Double(nanoseconds) / 1_000_000_000.0
    }

    public static func secondsFromMachTicks(
        _ ticks: UInt64,
        timebase: RecordingTimebase
    ) -> TimeInterval {
        let nanoseconds = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000_000.0
    }

    public static func liveDuration(
        currentMachTicks: UInt64,
        baseMachTicks: UInt64,
        resumeOffsetDuration: TimeInterval,
        timebase: RecordingTimebase
    ) -> TimeInterval {
        let elapsedTicks = currentMachTicks >= baseMachTicks ? currentMachTicks - baseMachTicks : 0
        return resumeOffsetDuration + secondsFromMachTicks(elapsedTicks, timebase: timebase)
    }

    public static func eventTime(
        timestamp: UInt64,
        baseTimestamp: UInt64?,
        resumeOffsetDuration: TimeInterval
    ) -> RecordingEventTime {
        let base = baseTimestamp ?? timestamp
        let elapsedNanoseconds = timestamp >= base ? timestamp - base : 0
        return RecordingEventTime(
            baseTimestamp: base,
            elapsed: resumeOffsetDuration + secondsFromNanoseconds(elapsedNanoseconds)
        )
    }
}

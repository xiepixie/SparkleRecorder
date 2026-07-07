import Foundation

public struct PlaybackWaitPlan: Equatable, Sendable {
    public var delay: TimeInterval
    public var sleepDuration: TimeInterval
    public var spinDuration: TimeInterval

    public init(delay: TimeInterval, sleepDuration: TimeInterval, spinDuration: TimeInterval) {
        self.delay = delay
        self.sleepDuration = sleepDuration
        self.spinDuration = spinDuration
    }

    public var shouldSleep: Bool {
        sleepDuration > 0
    }

    public var sleepNanoseconds: UInt64 {
        guard sleepDuration.isFinite, sleepDuration > 0 else { return 0 }
        let cappedSeconds = min(sleepDuration, Double(UInt64.max) / 1_000_000_000.0)
        return UInt64((cappedSeconds * 1_000_000_000.0).rounded(.down))
    }
}

public struct PlaybackWaitStrategy: Equatable, Sendable {
    public static let precise = PlaybackWaitStrategy()

    public var sleepThreshold: TimeInterval
    public var spinLeadTime: TimeInterval

    public init(sleepThreshold: TimeInterval = 0.002, spinLeadTime: TimeInterval = 0.0005) {
        self.sleepThreshold = Self.sanitizeNonnegativeFinite(sleepThreshold, fallback: 0.002)
        self.spinLeadTime = Self.sanitizeNonnegativeFinite(spinLeadTime, fallback: 0.0005)
    }

    public func plan(now: TimeInterval, target: TimeInterval) -> PlaybackWaitPlan {
        guard now.isFinite, target.isFinite else {
            return PlaybackWaitPlan(delay: 0, sleepDuration: 0, spinDuration: 0)
        }

        let delay = target - now
        guard delay > 0 else {
            return PlaybackWaitPlan(delay: delay, sleepDuration: 0, spinDuration: 0)
        }

        let sleepDuration = delay > sleepThreshold ? max(0, delay - spinLeadTime) : 0
        return PlaybackWaitPlan(
            delay: delay,
            sleepDuration: sleepDuration,
            spinDuration: max(0, delay - sleepDuration)
        )
    }

    private static func sanitizeNonnegativeFinite(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard value.isFinite, value >= 0 else { return fallback }
        return value
    }
}

public struct PlaybackClockClient: Sendable {
    public var now: @Sendable () -> TimeInterval
    public var sleep: @Sendable (TimeInterval) async -> Void
    public var sleepSynchronously: @Sendable (TimeInterval) -> Void
    public var spinsUntilTarget: Bool

    public init(
        now: @escaping @Sendable () -> TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async -> Void,
        sleepSynchronously: @escaping @Sendable (TimeInterval) -> Void,
        spinsUntilTarget: Bool = true
    ) {
        self.now = now
        self.sleep = sleep
        self.sleepSynchronously = sleepSynchronously
        self.spinsUntilTarget = spinsUntilTarget
    }

    public static let live = PlaybackClockClient(
        now: { CFAbsoluteTimeGetCurrent() },
        sleep: { duration in
            let nanoseconds = PlaybackClockClient.nanoseconds(for: duration)
            guard nanoseconds > 0 else { return }
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        sleepSynchronously: { duration in
            guard duration.isFinite, duration > 0 else { return }
            Thread.sleep(forTimeInterval: duration)
        }
    )

    public static func immediate(now fixedNow: TimeInterval = 0) -> PlaybackClockClient {
        PlaybackClockClient(
            now: { fixedNow },
            sleep: { _ in },
            sleepSynchronously: { _ in },
            spinsUntilTarget: false
        )
    }

    public func wait(until target: TimeInterval, strategy: PlaybackWaitStrategy = .precise) async {
        let waitPlan = strategy.plan(now: now(), target: target)
        if waitPlan.shouldSleep {
            await sleep(waitPlan.sleepDuration)
        }
        guard spinsUntilTarget else { return }
        while now() < target { }
    }

    public func waitSynchronously(until target: TimeInterval, strategy: PlaybackWaitStrategy = .precise) {
        let waitPlan = strategy.plan(now: now(), target: target)
        if waitPlan.shouldSleep {
            sleepSynchronously(waitPlan.sleepDuration)
        }
        guard spinsUntilTarget else { return }
        while now() < target { }
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        PlaybackWaitPlan(delay: duration, sleepDuration: duration, spinDuration: 0).sleepNanoseconds
    }
}

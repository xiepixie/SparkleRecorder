import Foundation

public enum PlaybackTextObservation: Equatable, Sendable {
    case found
    case absent
    case unavailable(String)
}

public enum PlaybackTextObservationOutcome: Equatable, Sendable {
    case matched
    case timedOut
    case cancelled
    case invalidPolicy
    case unavailable(String)
}

public enum PlaybackTextObservationEvaluator {
    public static func wait(
        mustExist: Bool, timeout: Double, pollInterval: Double = 0.5,
        clock: PlaybackClockClient,
        cancelled: @escaping @Sendable () -> Bool = { Task.isCancelled },
        observe: @escaping @Sendable () async -> PlaybackTextObservation
    ) async -> PlaybackTextObservationOutcome {
        guard timeout.isFinite, timeout > 0, timeout <= 3600,
              pollInterval.isFinite, pollInterval > 0 else { return .invalidPolicy }
        let start = clock.now()
        guard start.isFinite, (start + timeout).isFinite else { return .invalidPolicy }
        let deadline = start + timeout
        var last: PlaybackTextObservation = .absent
        while clock.now() < deadline {
            if cancelled() { return .cancelled }
            last = await observe()
            if cancelled() { return .cancelled }
            guard clock.now() < deadline else { return .timedOut }
            if last == (mustExist ? .found : .absent) { return .matched }
            await clock.sleep(min(pollInterval, max(0, deadline - clock.now())))
        }
        if cancelled() { return .cancelled }
        if case .unavailable(let reason) = last { return .unavailable(reason) }
        return .timedOut
    }
}

public struct PlaybackTextObservationClient: Sendable {
    public var observe: @Sendable (RecordedEvent, PlaybackContext) async -> PlaybackTextObservation

    public init(observe: @escaping @Sendable (RecordedEvent, PlaybackContext) async -> PlaybackTextObservation) {
        self.observe = observe
    }
}

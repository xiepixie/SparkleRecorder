import Foundation

public struct AutomationPlayerStartRequest: Sendable {
    public var runID: UUID
    public var macro: SavedMacro
    public var scheduledStartTime: Date?
    public var context: PlaybackContext

    public init(
        runID: UUID,
        macro: SavedMacro,
        scheduledStartTime: Date? = nil,
        context: PlaybackContext? = nil
    ) {
        self.runID = runID
        self.macro = macro
        self.scheduledStartTime = scheduledStartTime
        self.context = context ?? macro.playbackContext
    }
}

public enum AutomationPlayerStartResult: Equatable, Sendable {
    case started
    case rejected(AutomationOutcome)

    public func action(runID: UUID, at date: Date) -> AutomationAction {
        switch self {
        case .started:
            return .playerStarted(runID: runID, at: date)
        case .rejected(let outcome):
            return .playerFinished(runID: runID, outcome: outcome, at: date)
        }
    }
}

public enum AutomationPlayerCompletion: Equatable, Sendable {
    case succeeded(report: RunReport?)
    case failed(report: RunReport?)
    case cancelled(reason: String?)
    case timedOut(deadline: Date?)

    public var outcome: AutomationOutcome {
        switch self {
        case .succeeded(let report):
            return .succeeded(report: report)
        case .failed(let report):
            return .failed(report: report)
        case .cancelled(let reason):
            return .cancelled(reason: reason)
        case .timedOut(let deadline):
            return .timedOut(deadline: deadline)
        }
    }

    public func action(runID: UUID, at date: Date) -> AutomationAction {
        .playerFinished(runID: runID, outcome: outcome, at: date)
    }
}

public struct AutomationPlayerClient: Sendable {
    public var start: @Sendable (AutomationPlayerStartRequest) async -> AutomationPlayerStartResult
    public var cancel: @Sendable (_ runID: UUID) async -> Void
    public var events: @Sendable () -> AsyncStream<AutomationAction>

    public init(
        start: @escaping @Sendable (AutomationPlayerStartRequest) async -> AutomationPlayerStartResult,
        cancel: @escaping @Sendable (_ runID: UUID) async -> Void,
        events: @escaping @Sendable () -> AsyncStream<AutomationAction> = { .finished }
    ) {
        self.start = start
        self.cancel = cancel
        self.events = events
    }

    public static func accepting() -> AutomationPlayerClient {
        AutomationPlayerClient(
            start: { _ in .started },
            cancel: { _ in }
        )
    }

    public static func accepting(events: [AutomationAction]) -> AutomationPlayerClient {
        AutomationPlayerClient(
            start: { _ in .started },
            cancel: { _ in },
            events: { .fixed(events) }
        )
    }

    public static func rejecting(_ outcome: AutomationOutcome) -> AutomationPlayerClient {
        AutomationPlayerClient(
            start: { _ in .rejected(outcome) },
            cancel: { _ in }
        )
    }
}

extension AsyncStream where Element == AutomationAction {
    public static var finished: AsyncStream<AutomationAction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public static func fixed(_ actions: [AutomationAction]) -> AsyncStream<AutomationAction> {
        AsyncStream { continuation in
            for action in actions {
                continuation.yield(action)
            }
            continuation.finish()
        }
    }
}

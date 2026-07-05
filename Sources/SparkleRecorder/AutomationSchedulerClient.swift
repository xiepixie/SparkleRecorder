import Foundation

public enum AutomationSchedulerEvent: Equatable, Sendable {
    case clockTick(Date)
    case manualTrigger(workflowID: UUID, taskID: UUID, at: Date)

    public var action: AutomationAction {
        switch self {
        case .clockTick(let date):
            return .clockTick(date)
        case .manualTrigger(let workflowID, let taskID, let date):
            return .manualStart(workflowID: workflowID, taskID: taskID, requestedAt: date)
        }
    }
}

public struct AutomationSchedulerClient: Sendable {
    public var events: @Sendable () -> AsyncStream<AutomationSchedulerEvent>

    public init(events: @escaping @Sendable () -> AsyncStream<AutomationSchedulerEvent>) {
        self.events = events
    }

    public func actions() -> AsyncStream<AutomationAction> {
        let makeEvents = events
        return AsyncStream { continuation in
            let task = Task {
                for await event in makeEvents() {
                    continuation.yield(event.action)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public static func fixed(_ events: [AutomationSchedulerEvent]) -> AutomationSchedulerClient {
        AutomationSchedulerClient {
            AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    public static func timer(
        interval: TimeInterval,
        emitImmediately: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationSchedulerClient {
        let nanoseconds = UInt64(max(interval, 0.001) * 1_000_000_000)
        return AutomationSchedulerClient {
            AsyncStream { continuation in
                let task = Task {
                    if emitImmediately {
                        continuation.yield(.clockTick(now()))
                    }

                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: nanoseconds)
                        } catch {
                            break
                        }

                        guard !Task.isCancelled else {
                            break
                        }
                        continuation.yield(.clockTick(now()))
                    }
                    continuation.finish()
                }

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        }
    }
}

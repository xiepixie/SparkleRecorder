import Foundation

public struct AutomationRuntimeSnapshot: Equatable, Sendable {
    public var state: AutomationRunState
    public var revision: UInt64

    public init(state: AutomationRunState, revision: UInt64) {
        self.state = state
        self.revision = revision
    }
}

public actor AutomationEngineRuntime {
    private var state: AutomationRunState
    private var revision: UInt64 = 0
    private let reducerEnvironment: AutomationReducerEnvironment
    private let effectRunner: AutomationEffectRunner

    public init(
        initialState: AutomationRunState = AutomationRunState(),
        reducerEnvironment: AutomationReducerEnvironment = .live,
        effectRunner: AutomationEffectRunner
    ) {
        self.state = initialState
        self.reducerEnvironment = reducerEnvironment
        self.effectRunner = effectRunner
    }

    public func currentState() -> AutomationRunState {
        state
    }

    public func currentSnapshot() -> AutomationRuntimeSnapshot {
        AutomationRuntimeSnapshot(state: state, revision: revision)
    }

    @discardableResult
    public func dispatch(_ action: AutomationAction) async -> AutomationRunState {
        await apply(action)
        return state
    }

    public func runScheduler(_ scheduler: AutomationSchedulerClient) async {
        await runActions(scheduler.actions())
    }

    public func runPlayerEvents() async {
        await runActions(effectRunner.playerActions())
    }

    public func runActions(_ actions: AsyncStream<AutomationAction>) async {
        for await action in actions {
            await apply(action)
        }
    }

    private func apply(_ action: AutomationAction) async {
        let result = AutomationReducer.reduce(
            state: state,
            action: action,
            environment: reducerEnvironment
        )
        state = result.state
        revision &+= 1

        for effect in result.effects {
            let followUpActions = await effectRunner.run(effect)
            var persistenceFailed = false
            for followUpAction in followUpActions {
                if case .persistenceFailed = followUpAction {
                    persistenceFailed = true
                }
                await apply(followUpAction)
            }
            if persistenceFailed {
                break
            }
        }
    }
}

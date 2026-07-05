import Foundation

public actor AutomationEngineRuntime {
    private var state: AutomationRunState
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

        for effect in result.effects {
            let followUpActions = await effectRunner.run(effect)
            for followUpAction in followUpActions {
                await apply(followUpAction)
            }
        }
    }
}

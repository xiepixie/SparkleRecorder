import Foundation

public enum AutomationRuntimeSessionStatus: Equatable, Sendable {
    case idle
    case running
    case stopped
}

public enum AutomationRuntimeSessionError: Error, Equatable, Sendable {
    case notStarted
}

public actor AutomationRuntimeSession {
    private let repository: AutomationRepositoryClient
    private let scheduler: AutomationSchedulerClient
    private let reducerEnvironment: AutomationReducerEnvironment
    private let effectRunner: AutomationEffectRunner

    private var runtime: AutomationEngineRuntime?
    private var schedulerTask: Task<Void, Never>?
    private var playerEventsTask: Task<Void, Never>?
    private var status: AutomationRuntimeSessionStatus = .idle

    public init(
        repository: AutomationRepositoryClient,
        scheduler: AutomationSchedulerClient,
        reducerEnvironment: AutomationReducerEnvironment = .live,
        effectRunner: AutomationEffectRunner
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.reducerEnvironment = reducerEnvironment
        self.effectRunner = effectRunner
    }

    public func lifecycleStatus() -> AutomationRuntimeSessionStatus {
        status
    }

    public func currentState() async -> AutomationRunState? {
        guard let runtime else {
            return nil
        }
        return await runtime.currentState()
    }

    @discardableResult
    public func start() async throws -> AutomationRunState {
        if status == .running, let runtime {
            return await runtime.currentState()
        }

        stopTasks()

        let workflows = try await repository.loadWorkflows()
        let runHistory = try await repository.loadRunHistory()
        let runtime = AutomationEngineRuntime(
            initialState: AutomationRunState(workflows: workflows, runs: runHistory),
            reducerEnvironment: reducerEnvironment,
            effectRunner: effectRunner
        )

        self.runtime = runtime
        status = .running

        schedulerTask = Task {
            await runtime.runScheduler(scheduler)
        }
        playerEventsTask = Task {
            await runtime.runPlayerEvents()
        }

        return await runtime.currentState()
    }

    @discardableResult
    public func dispatch(_ action: AutomationAction) async throws -> AutomationRunState {
        guard let runtime else {
            throw AutomationRuntimeSessionError.notStarted
        }
        return await runtime.dispatch(action)
    }

    public func stop(at date: Date = Date()) async {
        if let runtime {
            let state = await runtime.currentState()
            let activeRunIDs = state.runs.compactMap { run -> UUID? in
                guard !run.isTerminal else {
                    return nil
                }
                switch run.status {
                case .waitingForResource, .queued, .running:
                    return run.id
                case .planned, .waitingForDependencies, .completed:
                    return nil
                }
            }

            for runID in activeRunIDs {
                await runtime.dispatch(.cancelRun(runID: runID, at: date))
            }
        }

        stopTasks()
        status = .stopped
    }

    private func stopTasks() {
        schedulerTask?.cancel()
        playerEventsTask?.cancel()
        schedulerTask = nil
        playerEventsTask = nil
    }
}

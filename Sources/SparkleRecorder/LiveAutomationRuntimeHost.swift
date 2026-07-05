import Foundation
import SparkleRecorderCore

@MainActor
final class LiveAutomationRuntimeHost {
    private let session: AutomationRuntimeSession
    private let refreshClient: AutomationRepositoryRefreshClient
    private let windowTracker: WindowTracker
    private var startupTask: Task<Void, Never>?

    init(
        player: Player,
        macroClient: MacroRepositoryClient = .live,
        repository: AutomationRepositoryClient = .fileBacked(),
        scheduler: AutomationSchedulerClient = .timer(interval: 30, emitImmediately: true),
        externalSignal: AutomationExternalSignalClient = .inactive,
        manualApproval: AutomationManualApprovalClient = .rejecting,
        ocrSearchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext = { _, displayBounds in
            AutomationOCRSearchRegionContext(displayBounds: displayBounds)
        },
        windowTracker: WindowTracker = WindowTracker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.refreshClient = .stateful(
            snapshotClient: .repositoryBacked(repository, now: now),
            now: now
        )
        self.windowTracker = windowTracker

        let playerClient = AutomationPlayerClient.live(
            player: player,
            windowTracker: windowTracker,
            now: now
        )
        let effectRunner = AutomationEffectRunner(
            resourceArbiter: .live(),
            player: playerClient,
            conditionEvaluator: .live(
                externalSignal: externalSignal,
                manualApproval: manualApproval,
                searchRegionContext: ocrSearchRegionContext,
                now: now
            ),
            repository: repository,
            loadMacro: { macroID in
                var macro = try await macroClient.loadAllManifests()
                    .first { $0.id == macroID }
                guard macro != nil else {
                    return nil
                }
                macro?.events = try await macroClient.loadEvents(macroID)
                return macro
            },
            now: now
        )

        self.session = AutomationRuntimeSession(
            repository: repository,
            scheduler: scheduler,
            effectRunner: effectRunner
        )
    }

    func start() {
        startupTask?.cancel()
        startupTask = Task { [session] in
            do {
                let state = try await session.start()
                NSLog("SparkleRecorder: Automation runtime started with \(state.workflows.count) workflow(s).")
            } catch {
                NSLog("SparkleRecorder: Failed to start automation runtime: \(error)")
            }
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        Task { [session] in
            await session.stop()
        }
    }

    func dispatchManualStart(workflowID: UUID, taskID: UUID, requestedAt: Date = Date()) {
        Task { [session] in
            do {
                try await session.dispatch(.manualStart(
                    workflowID: workflowID,
                    taskID: taskID,
                    requestedAt: requestedAt
                ))
            } catch {
                NSLog("SparkleRecorder: Automation manual start failed: \(error)")
            }
        }
    }

    func dispatch(_ action: AutomationAction) async throws -> AutomationRunState {
        try await session.dispatch(action)
    }

    func currentState() async -> AutomationRunState? {
        await session.currentState()
    }

    func refreshRepositorySnapshot() async -> AutomationRepositoryRefreshResult {
        switch await refreshClient.refresh() {
        case .loaded(let snapshot):
            return .loaded(snapshot)
        case .failed(let failure, _):
            return .failed(failure)
        case .idle, .loading:
            return .failed(AutomationRepositoryRefreshFailure(
                message: "Repository refresh did not complete",
                failedAt: Date()
            ))
        }
    }

    func repositoryRefreshState() async -> AutomationRepositoryRefreshState {
        await refreshClient.currentState()
    }

    func refreshRepositoryState() async -> AutomationRepositoryRefreshState {
        await refreshClient.refresh()
    }
}

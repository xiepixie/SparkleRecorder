import Foundation
import SparkleRecorderCore

@MainActor
final class LiveAutomationRuntimeHost {
    private let session: AutomationRuntimeSession
    private let runtimeHandoffClient: AutomationRuntimeHandoffClient
    private let runtimeHandoffPollInterval: TimeInterval
    private let refreshClient: AutomationRepositoryRefreshClient
    private let windowTracker: WindowTracker
    private var startupTask: Task<Void, Never>?
    private var runtimeHandoffTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    init(
        player: Player,
        macroClient: MacroRepositoryClient = .live,
        repository: AutomationRepositoryClient = .fileBacked(),
        scheduler: AutomationSchedulerClient = .timer(interval: 30, emitImmediately: true),
        externalSignal: AutomationExternalSignalClient = .inactive,
        manualApproval: AutomationManualApprovalClient = .rejecting,
        runtimeHandoffClient: AutomationRuntimeHandoffClient = .fileBacked(),
        runtimeHandoffPollInterval: TimeInterval = 1,
        visualAssetPackages: [AutomationVisualAssetWorkflowPackage] = [],
        visualAssetPackageRootClient: AutomationVisualAssetPackageRootClient = .fileBacked(),
        visualImageProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        visualBaselineProvider: @escaping AutomationVisualImageProvider = { _, _ in nil },
        ocrSearchRegionContext: @escaping @Sendable (
            _ request: AutomationConditionEvaluationRequest,
            _ displayBounds: RectValue
        ) async -> AutomationOCRSearchRegionContext = { _, displayBounds in
            AutomationOCRSearchRegionContext(displayBounds: displayBounds)
        },
        foregroundInputAvailable: @escaping @Sendable () async -> Bool = { true },
        windowTracker: WindowTracker = WindowTracker(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runtimeHandoffClient = runtimeHandoffClient
        self.runtimeHandoffPollInterval = runtimeHandoffPollInterval
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
        let visualPackageProviders = AutomationVisualAssetImageProviders
            .workflowPackages(visualAssetPackages)
        let storedVisualPackageProviders = AutomationVisualAssetImageProviders
            .workflowPackageRoots {
                do {
                    let roots = try await visualAssetPackageRootClient.loadRoots()
                    guard !roots.isEmpty else {
                        return []
                    }
                    let workflows = try await repository.loadWorkflows()
                    return AutomationVisualAssetWorkflowPackage.packages(
                        workflows: workflows,
                        roots: roots
                    )
                } catch {
                    NSLog("SparkleRecorder: Failed to load workflow visual asset package roots: \(error)")
                    return []
                }
            }
        let imageProvider: AutomationVisualImageProvider = { request, reference in
            if let image = try await visualImageProvider(request, reference) {
                return image
            }
            if let image = try await visualPackageProviders.imageProvider(request, reference) {
                return image
            }
            return try await storedVisualPackageProviders.imageProvider(request, reference)
        }
        let baselineProvider: AutomationVisualImageProvider = { request, reference in
            if let image = try await visualBaselineProvider(request, reference) {
                return image
            }
            if let image = try await visualPackageProviders.baselineProvider(request, reference) {
                return image
            }
            return try await storedVisualPackageProviders.baselineProvider(request, reference)
        }
        let effectRunner = AutomationEffectRunner(
            resourceArbiter: AppAutomationResourceArbiter.make(
                foregroundInputAvailable: foregroundInputAvailable
            ),
            player: playerClient,
            conditionEvaluator: .live(
                externalSignal: externalSignal,
                manualApproval: manualApproval,
                imageProvider: imageProvider,
                baselineProvider: baselineProvider,
                searchRegionContext: ocrSearchRegionContext,
                now: now
            ),
            repository: repository,
            loadMacro: { macroID in
                try await macroClient.loadPinnedMacro(macroID)
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
        guard stopTask == nil else { return }
        startupTask?.cancel()
        startRuntimeHandoffPolling()
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
        _ = beginStopIfNeeded()
    }

    func stopAndWait() async {
        let task = beginStopIfNeeded()
        await task.value
    }

    private func beginStopIfNeeded() -> Task<Void, Never> {
        if let stopTask { return stopTask }

        let startup = startupTask
        let handoff = runtimeHandoffTask
        startup?.cancel()
        handoff?.cancel()
        startupTask = nil
        runtimeHandoffTask = nil

        let task = Task { [session] in
            await startup?.value
            await handoff?.value
            await session.stop()
        }
        stopTask = task
        return task
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

    /// The App shell released its own foreground-input ownership. Wake waiting
    /// runs immediately instead of making them wait for the next scheduler tick.
    func foregroundInputBecameAvailable(at date: Date = Date()) {
        Task { [session] in
            _ = try? await session.dispatch(.clockTick(date))
        }
    }

    func currentSnapshot() async -> AutomationRuntimeSnapshot? {
        await session.currentSnapshot()
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

    private func startRuntimeHandoffPolling() {
        runtimeHandoffTask?.cancel()
        let client = runtimeHandoffClient
        let interval = runtimeHandoffPollInterval
        runtimeHandoffTask = Task { [session] in
            await Self.runRuntimeHandoffMailbox(
                client: client,
                session: session,
                pollInterval: interval
            )
        }
    }

    nonisolated private static func runRuntimeHandoffMailbox(
        client: AutomationRuntimeHandoffClient,
        session: AutomationRuntimeSession,
        pollInterval: TimeInterval
    ) async {
        let sleepNanoseconds = UInt64(max(0.1, pollInterval) * 1_000_000_000)
        while !Task.isCancelled {
            await consumeRuntimeHandoffCommands(client: client, session: session)
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }
    }

    nonisolated private static func consumeRuntimeHandoffCommands(
        client: AutomationRuntimeHandoffClient,
        session: AutomationRuntimeSession
    ) async {
        let commands: [AutomationRuntimeHandoffCommand]
        do {
            commands = try await client.loadCommands()
        } catch {
            NSLog("SparkleRecorder: Failed to load automation runtime handoff commands: \(error)")
            return
        }

        for command in commands {
            guard !Task.isCancelled else {
                return
            }
            do {
                let beforeRunIDs = Set((await session.currentState()?.runs ?? []).map(\.id))
                let afterState = try await session.dispatch(command.action)
                let newRunIDs = afterState.runs
                    .map(\.id)
                    .filter { !beforeRunIDs.contains($0) }
                let receipt = AutomationRuntimeHandoffReceipt(
                    command: command,
                    status: .dispatched,
                    runIDs: newRunIDs,
                    message: "Dispatched by App host"
                )
                try await client.completeCommand(receipt)
                NSLog("SparkleRecorder: Consumed automation runtime handoff command \(command.id.uuidString).")
            } catch AutomationRuntimeSessionError.notStarted {
                return
            } catch {
                let receipt = AutomationRuntimeHandoffReceipt(
                    command: command,
                    status: .failed,
                    message: String(describing: error)
                )
                do {
                    try await client.completeCommand(receipt)
                } catch {
                    NSLog("SparkleRecorder: Failed to write automation runtime handoff receipt \(command.id.uuidString): \(error)")
                }
                NSLog("SparkleRecorder: Failed to consume automation runtime handoff command \(command.id.uuidString): \(error)")
            }
        }
    }
}

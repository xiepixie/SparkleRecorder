import Foundation
import SparkleRecorderCore

private final class AutomationPlayerEventBridge: @unchecked Sendable {
    private let box = AutomationPlayerContinuationBox()
    let stream: AsyncStream<AutomationAction>

    init() {
        let box = box
        self.stream = AsyncStream { continuation in
            box.set(continuation)
        }
    }

    func yield(_ action: AutomationAction) {
        box.yield(action)
    }
}

private final class AutomationPlayerContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AutomationAction>.Continuation?

    func set(_ continuation: AsyncStream<AutomationAction>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func yield(_ action: AutomationAction) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(action)
    }
}

@MainActor
private final class LiveAutomationPlayerBox: @unchecked Sendable {
    private let player: Player
    private let windowTracker: WindowTracker?
    private let targetApplications: AutomationTargetApplicationClient
    private let readinessSleep: @Sendable (TimeInterval) async throws -> Void
    private var preparingRunIDs: Set<UUID> = []
    private var cancelledRunIDs: Set<UUID> = []
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var targetSessions:
        [UUID: (
            session: AutomationTargetApplicationSession,
            cleanupPolicy: AutomationTargetApplicationCleanupPolicy,
            quitTimeout: TimeInterval,
            forceQuitOnTimeout: Bool
        )] = [:]

    init(
        player: Player,
        windowTracker: WindowTracker?,
        targetApplications: AutomationTargetApplicationClient,
        readinessSleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.player = player
        self.windowTracker = windowTracker
        self.targetApplications = targetApplications
        self.readinessSleep = readinessSleep
    }

    func start(
        request: AutomationPlayerStartRequest,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) async -> AutomationPlayerStartResult {
        guard !Task.isCancelled else {
            return .rejected(.cancelled(reason: "Automation cancelled during startup preparation"))
        }
        guard
            !PlaybackPlanner.plan(
                events: request.macro.events,
                loops: request.macro.loops,
                speed: request.macro.speed
            ).steps.isEmpty
        else {
            return .rejected(.rejected(reason: "Macro has no playable events"))
        }
        if let failure = player.playbackPermissionFailure {
            return .rejected(.rejected(reason: failure))
        }
        guard player.reserveAutomationRun(request.runID) else {
            return .rejected(.rejected(reason: "Player is already running"))
        }
        preparingRunIDs.insert(request.runID)
        var startedPlayback = false
        defer {
            preparingRunIDs.remove(request.runID)
            if !startedPlayback { player.releaseAutomationRun(request.runID) }
        }

        let targetSession: AutomationTargetApplicationSession
        switch await targetApplications.prepare(
            request.context.surfaces, request.targetApplicationPolicy)
        {
        case .success(let session):
            targetSession = session
        case .failure(let failure):
            _ = await targetApplications.cleanup(
                failure.session,
                request.targetApplicationCleanupPolicy,
                request.targetApplicationQuitTimeout,
                request.targetApplicationForceQuitOnTimeout
            )
            return .rejected(.rejected(reason: failure.message))
        }
        targetSessions[request.runID] = (
            targetSession,
            request.targetApplicationCleanupPolicy,
            request.targetApplicationQuitTimeout,
            request.targetApplicationForceQuitOnTimeout
        )

        if cancelledRunIDs.remove(request.runID) != nil || Task.isCancelled || !player.canStartAutomationRun(request.runID) {
            await cleanupTargets(for: request.runID)
            return .rejected(.cancelled(reason: "Automation cancelled during startup preparation"))
        }
        if request.targetApplicationReadyDelay > 0 {
            do {
                try await readinessSleep(request.targetApplicationReadyDelay)
            } catch {
                await cleanupTargets(for: request.runID)
                return .rejected(
                    .cancelled(reason: "Automation cancelled during startup preparation"))
            }
        }
        if cancelledRunIDs.remove(request.runID) != nil || Task.isCancelled || !player.canStartAutomationRun(request.runID) {
            await cleanupTargets(for: request.runID)
            return .rejected(.cancelled(reason: "Automation cancelled during startup preparation"))
        }

        let didStart = player.play(
            macroID: request.macro.id,
            events: request.macro.events,
            runID: request.runID,
            loops: request.macro.loops,
            speed: request.macro.speed,
            context: request.context,
            windowTracker: windowTracker,
            automationCompletion: { completion in
                Task { @MainActor in
                    if case .succeeded(let report?) = completion {
                        let persistence = await EvidenceClient.shared.recordSuccess(
                            macroID: request.macro.id,
                            report: report,
                            surfaces: request.context.surfaces
                        )
                        bridge.yield(
                            .evidencePersistenceUpdated(
                                runID: request.runID,
                                persistence: persistence,
                                at: now()
                            ))
                    }
                    await self.cleanupTargets(for: request.runID)
                    self.player.releaseAutomationRun(request.runID)
                    bridge.yield(completion.action(runID: request.runID, at: now()))
                }
            },
            automationEvidencePersistence: { persistence in
                bridge.yield(
                    .evidencePersistenceUpdated(
                        runID: request.runID,
                        persistence: persistence,
                        at: now()
                    ))
            }
        )
        guard didStart else {
            await cleanupTargets(for: request.runID)
            return .rejected(.rejected(reason: "Player could not start the reserved run"))
        }
        startedPlayback = true
        return .started
    }

    func cancel(
        runID: UUID,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) async {
        if preparingRunIDs.contains(runID) {
            cancelledRunIDs.insert(runID)
            await cleanupTargets(for: runID)
            return
        }
        guard player.ownsAutomationRun(runID), player.stop(runID: runID) else {
            await cleanupTargets(for: runID)
            return
        }
        await cleanupTargets(for: runID)
        player.releaseAutomationRun(runID)
        bridge.yield(
            .playerFinished(
                runID: runID,
                outcome: .cancelled(reason: "Automation cancelled playback"),
                at: now()
            ))
    }

    private func cleanupTargets(for runID: UUID) async {
        if let existing = cleanupTasks[runID] { await existing.value; return }
        guard let targetSession = targetSessions.removeValue(forKey: runID) else { return }
        let task = Task { [targetApplications] in
            _ = await targetApplications.cleanup(targetSession.session, targetSession.cleanupPolicy,
                targetSession.quitTimeout, targetSession.forceQuitOnTimeout)
        }
        cleanupTasks[runID] = task
        await task.value
        cleanupTasks[runID] = nil
    }

}

extension AutomationPlayerClient {
    @MainActor
    static func live(
        player: Player,
        windowTracker: WindowTracker? = nil,
        targetApplications: AutomationTargetApplicationClient? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        readinessSleep: @escaping @Sendable (TimeInterval) async throws -> Void = { duration in
            try await Task.sleep(for: .seconds(duration))
        }
    ) -> AutomationPlayerClient {
        let bridge = AutomationPlayerEventBridge()
        let box = LiveAutomationPlayerBox(
            player: player,
            windowTracker: windowTracker,
            targetApplications: targetApplications ?? .live(windowTracker: windowTracker),
            readinessSleep: readinessSleep
        )

        return AutomationPlayerClient(
            start: { request in
                await box.start(request: request, bridge: bridge, now: now)
            },
            cancel: { runID in
                await box.cancel(runID: runID, bridge: bridge, now: now)
            },
            events: {
                bridge.stream
            }
        )
    }
}

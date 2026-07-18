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
    private var targetSessions: [UUID: (
        session: AutomationTargetApplicationSession,
        cleanupPolicy: AutomationTargetApplicationCleanupPolicy
    )] = [:]

    init(
        player: Player,
        windowTracker: WindowTracker?,
        targetApplications: AutomationTargetApplicationClient
    ) {
        self.player = player
        self.windowTracker = windowTracker
        self.targetApplications = targetApplications
    }

    func start(
        request: AutomationPlayerStartRequest,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) async -> AutomationPlayerStartResult {
        guard !player.isPlaying else {
            return .rejected(.rejected(reason: "Player is already running"))
        }
        guard !PlaybackPlanner.plan(
            events: request.macro.events,
            loops: request.macro.loops,
            speed: request.macro.speed
        ).steps.isEmpty else {
            return .rejected(.rejected(reason: "Macro has no playable events"))
        }

        let targetSession: AutomationTargetApplicationSession
        switch await targetApplications.prepare(request.context.surfaces, request.targetApplicationPolicy) {
        case .success(let session):
            targetSession = session
        case .failure(let failure):
            return .rejected(.rejected(reason: failure.message))
        }
        targetSessions[request.runID] = (targetSession, request.targetApplicationCleanupPolicy)

        player.play(
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
                        await EvidenceClient.shared.recordSuccess(
                            macroID: request.macro.id,
                            report: report,
                            surfaces: request.context.surfaces
                        )
                    }
                    await self.cleanupTargets(for: request.runID)
                    bridge.yield(completion.action(runID: request.runID, at: now()))
                }
            }
        )
        return .started
    }

    func cancel(
        runID: UUID,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) async {
        guard player.isPlaying else {
            await cleanupTargets(for: runID)
            return
        }

        player.stop()
        await cleanupTargets(for: runID)
        bridge.yield(.playerFinished(
            runID: runID,
            outcome: .cancelled(reason: "Automation cancelled playback"),
            at: now()
        ))
    }

    private func cleanupTargets(for runID: UUID) async {
        guard let targetSession = targetSessions.removeValue(forKey: runID) else {
            return
        }
        await targetApplications.cleanup(targetSession.session, targetSession.cleanupPolicy)
    }
}

extension AutomationPlayerClient {
    @MainActor
    static func live(
        player: Player,
        windowTracker: WindowTracker? = nil,
        targetApplications: AutomationTargetApplicationClient? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationPlayerClient {
        let bridge = AutomationPlayerEventBridge()
        let box = LiveAutomationPlayerBox(
            player: player,
            windowTracker: windowTracker,
            targetApplications: targetApplications ?? .live(windowTracker: windowTracker)
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

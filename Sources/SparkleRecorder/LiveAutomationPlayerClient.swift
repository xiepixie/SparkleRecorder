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
    private weak var windowTracker: WindowTracker?

    init(player: Player, windowTracker: WindowTracker?) {
        self.player = player
        self.windowTracker = windowTracker
    }

    func start(
        request: AutomationPlayerStartRequest,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) -> AutomationPlayerStartResult {
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

        player.play(
            macroID: request.macro.id,
            events: request.macro.events,
            runID: request.runID,
            loops: request.macro.loops,
            speed: request.macro.speed,
            context: request.context,
            windowTracker: windowTracker,
            automationCompletion: { completion in
                bridge.yield(completion.action(runID: request.runID, at: now()))
            }
        )
        return .started
    }

    func cancel(
        runID: UUID,
        bridge: AutomationPlayerEventBridge,
        now: @escaping @Sendable () -> Date
    ) {
        guard player.isPlaying else {
            return
        }

        player.stop()
        bridge.yield(.playerFinished(
            runID: runID,
            outcome: .cancelled(reason: "Automation cancelled playback"),
            at: now()
        ))
    }
}

extension AutomationPlayerClient {
    @MainActor
    static func live(
        player: Player,
        windowTracker: WindowTracker? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AutomationPlayerClient {
        let bridge = AutomationPlayerEventBridge()
        let box = LiveAutomationPlayerBox(player: player, windowTracker: windowTracker)

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

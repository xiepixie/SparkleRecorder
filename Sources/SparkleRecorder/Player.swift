import Cocoa
import CoreGraphics
import Combine
import SparkleRecorderCore

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var progress: Double = 0
}

private final class PlaybackConflictMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var conflicted = false
    private var ignoreUntil = CFAbsoluteTimeGetCurrent()
    private let loopbackMagic: Int64 = 0x535041524B4C4521

    var hasConflict: Bool {
        lock.lock()
        defer { lock.unlock() }
        return conflicted
    }

    func start(gracePeriod: TimeInterval = 0.25) {
        guard tap == nil else { return }
        ignoreUntil = CFAbsoluteTimeGetCurrent() + gracePeriod
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<PlaybackConflictMonitor>.fromOpaque(refcon).takeUnretainedValue()
            guard type != .tapDisabledByTimeout && type != .tapDisabledByUserInput else {
                return Unmanaged.passUnretained(event)
            }
            guard CFAbsoluteTimeGetCurrent() >= monitor.ignoreUntil else {
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) != monitor.loopbackMagic {
                monitor.lock.lock()
                monitor.conflicted = true
                monitor.lock.unlock()
            }
            return Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        tap = newTap
        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = nil
        }
        lock.lock()
        conflicted = false
        lock.unlock()
    }
}

private final class PlayerRunState: @unchecked Sendable {
    weak var player: Player?
    let generation: UInt64
    let completion: ((Bool) -> Void)?
    let automationCompletion: ((AutomationPlayerCompletion) -> Void)?

    init(
        player: Player,
        generation: UInt64,
        completion: ((Bool) -> Void)?,
        automationCompletion: ((AutomationPlayerCompletion) -> Void)?
    ) {
        self.player = player
        self.generation = generation
        self.completion = completion
        self.automationCompletion = automationCompletion
    }

    @MainActor
    func updateCurrentLoop(_ loop: Int) {
        player?.updateCurrentLoop(loop, generation: generation)
    }

    @MainActor
    func updateProgress(_ progress: Double) {
        player?.updateProgress(progress, generation: generation)
    }

    @MainActor
    func finish(
        monitor: PlaybackConflictMonitor,
        failureEvidence: PlaybackFailureEvidence?,
        terminalOutcome: PlaybackRunCompletion
    ) {
        player?.finishRun(
            generation: generation,
            monitor: monitor,
            failureEvidence: failureEvidence,
            terminalOutcome: terminalOutcome,
            automationCompletion: automationCompletion,
            completion: completion
        )
    }
}

/// Replays a recorded macro by posting CGEvents at the original relative timestamps.
@MainActor
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    let clock = PlaybackClock()
    @Published private(set) var currentLoop: Int = 0
    @Published private(set) var totalLoops: Int = 1

    private var task: Task<Void, Never>?
    private var runStateMachine = PlaybackRunStateMachine()
    private let pointResolver = PointResolver()
    private var conflictMonitor: PlaybackConflictMonitor?
    private let playbackClock: PlaybackClockClient
    private let eventPoster: EventPosterClient
    private let evidenceClient: PlaybackEvidenceClient
    nonisolated private static let waitStrategy = PlaybackWaitStrategy.precise

    init(
        playbackClock: PlaybackClockClient = .live,
        eventPoster: EventPosterClient = .live(),
        evidenceClient: PlaybackEvidenceClient = .live
    ) {
        self.playbackClock = playbackClock
        self.eventPoster = eventPoster
        self.evidenceClient = evidenceClient
    }

    /// Play the macro `loops` times. Pass `loops <= 0` for continuous (infinite) playback,
    /// which only stops on `stop()` or the configured stop hotkey.
    /// The completion receives `true` only when playback ran to natural completion —
    /// `false` for cancellation, so callers can skip chains/stats/sounds on abort.
    func play(
        macroID: UUID? = nil,
        events: [RecordedEvent],
        runID: UUID = UUID(),
        loops: Int = 1,
        speed: Double = 1.0,
        context: PlaybackContext = PlaybackContext(),
        windowTracker: WindowTracker? = nil,
        completion: ((Bool) -> Void)? = nil,
        automationCompletion: ((AutomationPlayerCompletion) -> Void)? = nil
    ) {
        let plan = PlaybackPlanner.plan(events: events, loops: loops, speed: speed)
        guard !isPlaying, !plan.steps.isEmpty else { completion?(false); return }
        let total = plan.loopMode.displayLoopCount

        let startSnapshot = runStateMachine.start(totalLoops: total)
        let gen = startSnapshot.generation
        let monitor = PlaybackConflictMonitor()
        let playbackClock = playbackClock
        let windowContext = Player.windowContextClient(for: windowTracker)
        let stepClientFactory = LivePlaybackRunStepClient(
            playbackClock: playbackClock,
            pointResolver: pointResolver,
            eventPoster: eventPoster
        )
        let runState = PlayerRunState(
            player: self,
            generation: gen,
            completion: completion,
            automationCompletion: automationCompletion
        )
        let runStartTime = Date.now
        let runStartClock = playbackClock.now()
        monitor.start()
        conflictMonitor = monitor
        apply(startSnapshot)

        task = Task.detached(priority: .userInitiated) {
            let powerAssertion = PlaybackPowerAssertion()
            defer { powerAssertion.end() }

            let stepClient = stepClientFactory.makeClient()

            let engine = PlaybackRunEngine(
                plan: plan,
                context: context,
                macroID: macroID,
                runID: runID,
                startedAt: runStartTime,
                startedClock: runStartClock,
                clock: playbackClock,
                windowContext: windowContext,
                conflict: PlaybackConflictClient(hasConflict: { monitor.hasConflict }),
                stepClient: stepClient,
                waitStrategy: Self.waitStrategy
            )
            let result = await engine.run(callbacks: PlaybackRunEngineCallbacks(
                loopStarted: { loop in
                    await runState.updateCurrentLoop(loop)
                },
                progressChanged: { progress in
                    await runState.updateProgress(progress)
                }
            ))
            let didAbort = result.didAbort
            let failureEvidence = result.failureEvidence
            let wasCancelled = Task.isCancelled
            let duration = playbackClock.now() - runStartClock
            let terminalOutcome = PlaybackRunStateMachine.completion(
                runID: runID,
                startedAt: runStartTime,
                duration: duration,
                didAbort: didAbort,
                wasCancelled: wasCancelled,
                failureEvidence: failureEvidence
            )
            await runState.finish(
                monitor: monitor,
                failureEvidence: failureEvidence,
                terminalOutcome: terminalOutcome
            )
        }
    }

    func stop() {
        let snapshot = runStateMachine.stop()
        task?.cancel()
        task = nil
        conflictMonitor?.stop()
        conflictMonitor = nil
        apply(snapshot)
    }

    fileprivate func updateCurrentLoop(_ loop: Int, generation expectedGeneration: UInt64) {
        guard let snapshot = runStateMachine.updateCurrentLoop(
            loop,
            generation: expectedGeneration
        ) else { return }
        apply(snapshot)
    }

    fileprivate func updateProgress(_ progress: Double, generation expectedGeneration: UInt64) {
        guard let snapshot = runStateMachine.updateProgress(
            progress,
            generation: expectedGeneration
        ) else { return }
        apply(snapshot)
    }

    fileprivate func finishRun(
        generation expectedGeneration: UInt64,
        monitor: PlaybackConflictMonitor,
        failureEvidence: PlaybackFailureEvidence?,
        terminalOutcome: PlaybackRunCompletion,
        automationCompletion: ((AutomationPlayerCompletion) -> Void)?,
        completion: ((Bool) -> Void)?
    ) {
        monitor.stop()
        if conflictMonitor === monitor {
            conflictMonitor = nil
        }

        if let snapshot = runStateMachine.finish(generation: expectedGeneration) {
            apply(snapshot)
        }

        if let failureEvidence {
            let evidenceClient = evidenceClient
            Task(priority: .utility) {
                await evidenceClient.recordFailure(failureEvidence)
            }
        }

        automationCompletion?(terminalOutcome.automationCompletion)
        completion?(terminalOutcome.didFinishNaturally)
    }

    private func apply(_ snapshot: PlaybackRunSnapshot) {
        isPlaying = snapshot.isPlaying
        clock.progress = snapshot.progress
        currentLoop = snapshot.currentLoop
        totalLoops = snapshot.totalLoops
    }

    /// Synchronous playback for CLI mode — no MainActor hops, no published state.
    /// Blocks the calling (background) thread until done.
    nonisolated
    static func playSynchronously(
        macroID: UUID? = nil,
        events: [RecordedEvent],
        loops: Int,
        speed: Double,
        context: PlaybackContext = PlaybackContext(),
        windowTracker: WindowTracker? = nil,
        playbackClock: PlaybackClockClient = .live,
        eventPoster: EventPosterClient = .live(),
        evidenceClient: PlaybackEvidenceClient = .live
    ) {
        let plan = PlaybackPlanner.plan(events: events, loops: PlaybackPlanner.finiteLoopCount(for: loops), speed: speed)
        guard !plan.steps.isEmpty else { return }
        let monitor = PlaybackConflictMonitor()
        let windowContext = Player.windowContextClient(for: windowTracker)
        let stepClientFactory = LivePlaybackSynchronousRunStepClient(
            playbackClock: playbackClock,
            eventPoster: eventPoster
        )
        let runID = UUID()
        let runStartTime = Date.now
        let runStartClock = playbackClock.now()
        monitor.start()
        defer { monitor.stop() }

        let powerAssertion = PlaybackPowerAssertion()
        defer { powerAssertion.end() }

        let engine = PlaybackSynchronousRunEngine(
            plan: plan,
            context: context,
            macroID: macroID,
            runID: runID,
            startedAt: runStartTime,
            startedClock: runStartClock,
            clock: playbackClock,
            windowContext: windowContext,
            conflict: PlaybackConflictClient(hasConflict: { monitor.hasConflict }),
            stepClient: stepClientFactory.makeClient(),
            waitStrategy: Self.waitStrategy
        )
        let result = engine.run()
        if let failureEvidence = result.failureEvidence {
            evidenceClient.recordFailureSynchronously(failureEvidence)
        }
    }

    nonisolated private static func activateSurface(_ surface: PlaybackSurface) {
        guard let bid = surface.bundleIdentifier,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) else {
            return
        }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    nonisolated private static func windowContextClient(for tracker: WindowTracker?) -> WindowContextClient {
        WindowContextClient(
            resolveFrameResolutions: { surfaces in
                guard let tracker else { return [:] }
                return Player.resolvedFrameResolutions(for: surfaces, tracker: tracker)
            },
            activateSurface: { surface in
                Player.activateSurface(surface)
            }
        )
    }

    nonisolated private static func resolvedFrameResolutions(
        for surfaces: [String: PlaybackSurface],
        tracker: WindowTracker
    ) -> [String: PlaybackSurfaceFrameResolution] {
        let outerFrames = tracker.resolveCurrentFrames(for: surfaces)
        return outerFrames.reduce(into: [:]) { resolutions, entry in
            let (surfaceId, frame) = entry
            guard let surface = surfaces[surfaceId] else { return }
            resolutions[surfaceId] = resolvedFrameResolution(for: surface, outerFrame: frame)
        }
    }

    nonisolated private static func resolvedFrameResolution(
        for surface: PlaybackSurface,
        outerFrame: RectValue
    ) -> PlaybackSurfaceFrameResolution {
        let bid = surface.bundleIdentifier
        let pid = bid.flatMap { bundleId in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }?.processIdentifier
        }
        let resolved = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: outerFrame)
        let contentFrame = RectValue(
            x: resolved.frame.minX,
            y: resolved.frame.minY,
            width: resolved.frame.width,
            height: resolved.frame.height
        )
        return PlaybackSurfaceFrameResolution(outerFrame: outerFrame, contentFrame: contentFrame)
    }

}

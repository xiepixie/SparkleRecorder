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

    init(player: Player, generation: UInt64, completion: ((Bool) -> Void)?) {
        self.player = player
        self.generation = generation
        self.completion = completion
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
    func finish(monitor: PlaybackConflictMonitor, didAbort: Bool, wasCancelled: Bool) {
        player?.finishRun(
            generation: generation,
            monitor: monitor,
            didAbort: didAbort,
            wasCancelled: wasCancelled,
            completion: completion
        )
    }
}

private final class LockedValueBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct PlaybackPointResolution: Sendable {
    var point: CGPoint?
    var failureReason: String?

    static func success(_ point: CGPoint) -> PlaybackPointResolution {
        PlaybackPointResolution(point: point, failureReason: nil)
    }

    static func failure(_ reason: String) -> PlaybackPointResolution {
        PlaybackPointResolution(point: nil, failureReason: reason)
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
    /// Incremented on every play()/stop(). A task only touches published state
    /// if its generation still matches, so a stale epilogue can't clobber a
    /// newer playback that started right after stop().
    private var generation: UInt64 = 0
    private let pointResolver = PointResolver()
    private var conflictMonitor: PlaybackConflictMonitor?
    private let playbackClock: PlaybackClockClient
    private let eventPoster: EventPosterClient
    nonisolated private static let waitStrategy = PlaybackWaitStrategy.precise

    nonisolated private static func awaitSynchronously<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) -> Value {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedValueBox<Value?>(nil)
        Task.detached(priority: .userInitiated) {
            result.set(await operation())
            semaphore.signal()
        }
        semaphore.wait()
        guard let value = result.get() else {
            fatalError("SparkleRecorder: synchronous async bridge completed without a result")
        }
        return value
    }

    @available(macOS 14.0, *)
    nonisolated private static func recordFailureEvidence(
        macroID: UUID?,
        startTime: Date,
        duration: TimeInterval,
        failedEventIndex: Int?,
        bundleIdentifier: String?,
        title: String?,
        reason: String
    ) async {
        guard let macroID = macroID else { return }
        var screenshotData: Data? = nil
        do {
            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bundleIdentifier, title: title)
            let bitmap = NSBitmapImageRep(cgImage: image)
            screenshotData = bitmap.representation(using: .png, properties: [:])
        } catch {}
        
        await EvidenceClient.shared.recordPlayback(
            macroID: macroID,
            startTime: startTime,
            duration: duration,
            success: false,
            failedEventIndex: failedEventIndex,
            errorMessage: reason,
            screenshotData: screenshotData
        )
    }

    nonisolated private static func recordFailureEvidenceSynchronously(
        macroID: UUID?,
        startTime: Date,
        duration: TimeInterval,
        failedEventIndex: Int?,
        bundleIdentifier: String?,
        title: String?,
        reason: String
    ) {
        if #available(macOS 14.0, *) {
            awaitSynchronously {
                await recordFailureEvidence(macroID: macroID, startTime: startTime, duration: duration, failedEventIndex: failedEventIndex, bundleIdentifier: bundleIdentifier, title: title, reason: reason)
            }
        }
    }

    init(
        playbackClock: PlaybackClockClient = .live,
        eventPoster: EventPosterClient = .live()
    ) {
        self.playbackClock = playbackClock
        self.eventPoster = eventPoster
    }

    /// Play the macro `loops` times. Pass `loops <= 0` for continuous (infinite) playback,
    /// which only stops on `stop()` or the configured stop hotkey.
    /// The completion receives `true` only when playback ran to natural completion —
    /// `false` for cancellation, so callers can skip chains/stats/sounds on abort.
    func play(macroID: UUID? = nil, events: [RecordedEvent], loops: Int = 1, speed: Double = 1.0, context: PlaybackContext = PlaybackContext(), windowTracker: WindowTracker? = nil, completion: ((Bool) -> Void)? = nil) {
        let plan = PlaybackPlanner.plan(events: events, loops: loops, speed: speed)
        guard !isPlaying, !plan.steps.isEmpty else { completion?(false); return }
        let infinite = plan.loopMode.isContinuous
        let total = plan.loopMode.displayLoopCount

        generation &+= 1
        let gen = generation
        let monitor = PlaybackConflictMonitor()
        let playbackClock = playbackClock
        let eventPoster = eventPoster
        let windowContext = Player.windowContextClient(for: windowTracker)
        let pointResolver = pointResolver
        let runState = PlayerRunState(player: self, generation: gen, completion: completion)
        monitor.start()
        conflictMonitor = monitor
        isPlaying = true
        clock.progress = 0
        currentLoop = 0
        totalLoops = total

        task = Task.detached(priority: .userInitiated) {
            var loopIndex = 0
            // Throttle progress updates to ~30 Hz so the hot posting loop never
            // waits on a busy main thread between events.
            var lastProgressPush = 0.0
            var runningContext = context
            var hasCapturedFailure = false
            var aborted = false
            outer: while !Task.isCancelled {
                if !infinite, loopIndex >= total { break }
                loopIndex += 1
                let snapshot = loopIndex
                await runState.updateCurrentLoop(snapshot)

                windowContext.activateAll(runningContext.surfaces.values)

                // Allow app to activate
                await playbackClock.sleep(0.2)

                windowContext.refreshResolvedFrames(in: &runningContext)

                var scheduledTime = playbackClock.now()
                var recentLocatorPoint: (key: String, point: CGPoint, eventTime: TimeInterval)? = nil
                for step in plan.steps {
                    let event = step.event
                    if Task.isCancelled { break outer }
                    scheduledTime += step.deltaFromPrevious

                    let target = scheduledTime
                    await playbackClock.wait(until: target, strategy: Self.waitStrategy)
                    if Task.isCancelled { break outer }
                    if monitor.hasConflict {
                        aborted = true
                        break outer
                    }

                    let targetSurfaceId = PlaybackPlanner.targetSurfaceId(for: event, context: runningContext)
                    if runningContext.currentSurfaceFrames[targetSurfaceId] == nil,
                       let surface = runningContext.surfaces[targetSurfaceId] {
                        let resolvedSurfaceIds = windowContext.refreshResolvedFrames(
                            in: &runningContext,
                            surfaces: [targetSurfaceId: surface],
                            resetExisting: false
                        )
                        if resolvedSurfaceIds.contains(targetSurfaceId) {
                            windowContext.activateSurface(surface)
                        }
                    }

                    if event.kind == .waitForText, let anchor = event.textAnchor {
                        let text = anchor.text
                        let timeout = event.textTimeout ?? 10.0
                        let startPoll = playbackClock.now()
                        var found = false
                        if #available(macOS 14.0, *) {
                            let locator = LocatorEngine()
                            while playbackClock.now() - startPoll < timeout {
                                if Task.isCancelled { break outer }
                                do {
                                    _ = try await locator.locate(event: event, context: runningContext, strategies: [.ocr(anchor)])
                                    found = true
                                    break
                                } catch {
                                    await playbackClock.sleep(0.5)
                                }
                            }
                        }
                        if !found {
                            aborted = true
                            if !hasCapturedFailure {
                                hasCapturedFailure = true
                                let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                Task {
                                    if #available(macOS 14.0, *) {
                                        await Player.recordFailureEvidence(macroID: macroID, startTime: Date(), duration: 0, failedEventIndex: nil, bundleIdentifier: bid, title: title, reason: "waitForText timeout: '\(text)'")
                                    }
                                }
                            }
                            break outer // Abort execution
                        }
                        scheduledTime = playbackClock.now()
                        continue
                    }

                    if event.kind == .verifyText, let anchor = event.textAnchor {
                        let text = anchor.text
                        let mustExist = event.verifyMustExist ?? true
                        var found = false
                        if #available(macOS 14.0, *) {
                            let locator = LocatorEngine()
                            do {
                                _ = try await locator.locate(event: event, context: runningContext, strategies: [.ocr(anchor)])
                                found = true
                            } catch {}
                        }
                        if found != mustExist {
                            aborted = true
                            if !hasCapturedFailure {
                                hasCapturedFailure = true
                                let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                Task {
                                    if #available(macOS 14.0, *) {
                                        await Player.recordFailureEvidence(macroID: macroID, startTime: Date(), duration: 0, failedEventIndex: nil, bundleIdentifier: bid, title: title, reason: "verifyText failed: '\(text)' mustExist=\(mustExist)")
                                    }
                                }
                            }
                            break outer // Abort execution
                        }
                        let actual = playbackClock.now()
                        if actual - scheduledTime > 0.04 {
                            scheduledTime = actual
                        }
                        continue
                    }

	                    let point: CGPoint
	                    if #available(macOS 14.0, *), (event.coordinateStrategy == .locatorOnly || event.textAnchor != nil) {
                            let cacheKey = Player.locatorCacheKey(for: event, surfaceId: targetSurfaceId)
                            if let cacheKey,
                               let cached = recentLocatorPoint,
                               cached.key == cacheKey,
                               abs(event.time - cached.eventTime) <= 1.0 {
                                point = cached.point
                            } else {
                                let locator = LocatorEngine()
                                var strategies: [LocatorStrategy] = []
                                if let anchor = event.textAnchor {
                                    strategies.append(.ocr(anchor))
                                }

                                do {
                                    point = try await Player.locateWithOptionalWait(locator: locator, event: event, context: runningContext, strategies: strategies, clock: playbackClock)
                                    if let cacheKey {
                                        recentLocatorPoint = (cacheKey, point, event.time)
                                    }
                                } catch {
                                    if event.locatorFallbackPolicy == .allowCoordinateFallback {
                                        if let fallbackPoint = Player.coordinateFallbackPoint(for: event, surfaceId: targetSurfaceId, context: runningContext) {
                                            point = fallbackPoint
                                        } else {
                                            let resolvedResult = pointResolver.resolve(event, context: runningContext)
                                            switch resolvedResult {
                                            case .success(let pt):
                                                point = pt
                                            case .failure(let fallbackError):
                                                #if DEBUG
                                                NSLog("SparkleRecorder: locator fallback error: \(fallbackError)")
                                                #endif
                                                aborted = true
                                                if !hasCapturedFailure {
                                                    hasCapturedFailure = true
                                                    let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                                    let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                                        if #available(macOS 14.0, *) {
                                                            await Player.recordFailureEvidence(macroID: macroID, startTime: Date(), duration: 0, failedEventIndex: nil, bundleIdentifier: bid, title: title, reason: "\(fallbackError)")
                                                        }
                                                }
                                                break outer
                                            }
                                        }
                                    } else {
                                        #if DEBUG
                                        NSLog("SparkleRecorder: locator engine error: \(error)")
                                        #endif
                                        aborted = true
                                        if !hasCapturedFailure {
                                            hasCapturedFailure = true
                                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                                if #available(macOS 14.0, *) {
                                                    await Player.recordFailureEvidence(macroID: macroID, startTime: Date(), duration: 0, failedEventIndex: nil, bundleIdentifier: bid, title: title, reason: "\(error)")
                                                }
                                        }
                                        break outer
                                    }
                                }
                            }
                    } else {
                        let resolvedResult = pointResolver.resolve(event, context: runningContext)
                        switch resolvedResult {
                        case .success(let pt):
                            point = pt
                        case .failure(let error):
                            #if DEBUG
                            NSLog("SparkleRecorder: point resolve error: \(error)")
                            #endif
                            aborted = true
                            if !hasCapturedFailure {
                                hasCapturedFailure = true
                                let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                Task {
                                    if #available(macOS 14.0, *) {
                                        await Player.recordFailureEvidence(macroID: macroID, startTime: Date(), duration: 0, failedEventIndex: nil, bundleIdentifier: bid, title: title, reason: "\(error)")
                                    }
                                }
                            }
                            break outer
                        }
                    }

                    eventPoster.post(event, point)
                    let postTime = playbackClock.now()
                    if postTime - scheduledTime > 0.04 {
                        scheduledTime = postTime
                    }
                    if plan.rawDuration > 0, postTime - lastProgressPush > 0.033 {
                        lastProgressPush = postTime
                        let p = step.progress
                        await runState.updateProgress(p)
                    }
                }
            }
            let didAbort = aborted
            let wasCancelled = Task.isCancelled
            await runState.finish(monitor: monitor, didAbort: didAbort, wasCancelled: wasCancelled)
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        conflictMonitor?.stop()
        conflictMonitor = nil
        isPlaying = false
        clock.progress = 0
        currentLoop = 0
        totalLoops = 1
    }

    fileprivate func updateCurrentLoop(_ loop: Int, generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        currentLoop = loop
    }

    fileprivate func updateProgress(_ progress: Double, generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        clock.progress = progress
    }

    fileprivate func finishRun(
        generation expectedGeneration: UInt64,
        monitor: PlaybackConflictMonitor,
        didAbort: Bool,
        wasCancelled: Bool,
        completion: ((Bool) -> Void)?
    ) {
        monitor.stop()
        if conflictMonitor === monitor {
            conflictMonitor = nil
        }

        let finished = !wasCancelled && !didAbort
        if generation == expectedGeneration {
            isPlaying = false
            clock.progress = 0
            currentLoop = 0
            totalLoops = 1
        }
        completion?(finished)
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
        eventPoster: EventPosterClient = .live()
    ) {
        let plan = PlaybackPlanner.plan(events: events, loops: PlaybackPlanner.finiteLoopCount(for: loops), speed: speed)
        guard !plan.steps.isEmpty else { return }
        let total = plan.loopMode.displayLoopCount
        let resolver = PointResolver()
        let monitor = PlaybackConflictMonitor()
        let windowContext = Player.windowContextClient(for: windowTracker)
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<total {
            windowContext.activateAll(context.surfaces.values)
            var runningContext = context

            // Allow app to activate
            playbackClock.sleepSynchronously(0.2)

            windowContext.refreshResolvedFrames(in: &runningContext)

            var scheduledTime = playbackClock.now()
            var recentLocatorPoint: (key: String, point: CGPoint, eventTime: TimeInterval)? = nil
            for step in plan.steps {
                let event = step.event
                scheduledTime += step.deltaFromPrevious

                let target = scheduledTime
                playbackClock.waitSynchronously(until: target, strategy: Self.waitStrategy)
                if monitor.hasConflict {
                    return
                }
                var hasCapturedFailure = false
                let targetSurfaceId = PlaybackPlanner.targetSurfaceId(for: event, context: runningContext)

                if runningContext.currentSurfaceFrames[targetSurfaceId] == nil,
                   let surface = runningContext.surfaces[targetSurfaceId] {
                    let resolvedSurfaceIds = windowContext.refreshResolvedFrames(
                        in: &runningContext,
                        surfaces: [targetSurfaceId: surface],
                        resetExisting: false
                    )
                    if resolvedSurfaceIds.contains(targetSurfaceId) {
                        windowContext.activateSurface(surface)
                    }
                }
                if event.kind == .waitForText, let anchor = event.textAnchor {
                    let text = anchor.text
                    let timeout = event.textTimeout ?? 10.0
                    let startPoll = playbackClock.now()
                    var found = false
                    if #available(macOS 14.0, *) {
                        let contextSnapshot = runningContext
                        found = awaitSynchronously {
                            let locator = LocatorEngine()
                            while playbackClock.now() - startPoll < timeout {
                                do {
                                    _ = try await locator.locate(event: event, context: contextSnapshot, strategies: [.ocr(anchor)])
                                    return true
                                } catch {
                                    await playbackClock.sleep(0.5)
                                }
                            }
                            return false
                        }
                    }
                    if !found {
                        if !hasCapturedFailure {
                            hasCapturedFailure = true
                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                            recordFailureEvidenceSynchronously(
                                macroID: macroID,
                                startTime: Date(),
                                duration: 0,
                                failedEventIndex: nil,
                                bundleIdentifier: bid,
                                title: title,
                                reason: "waitForText timeout: '\(text)'"
                            )
                        }
                        return // Abort synchronously
                    }
                    scheduledTime = playbackClock.now()
                    continue
                }
                if event.kind == .verifyText, let anchor = event.textAnchor {
                    let text = anchor.text
                    let mustExist = event.verifyMustExist ?? true
                    var found = false
                    if #available(macOS 14.0, *) {
                        let contextSnapshot = runningContext
                        found = awaitSynchronously {
                            let locator = LocatorEngine()
                            do {
                                _ = try await locator.locate(event: event, context: contextSnapshot, strategies: [.ocr(anchor)])
                                return true
                            } catch {
                                return false
                            }
                        }
                    }
                    if found != mustExist {
                        if !hasCapturedFailure {
                            hasCapturedFailure = true
                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                            recordFailureEvidenceSynchronously(
                                macroID: macroID,
                                startTime: Date(),
                                duration: 0,
                                failedEventIndex: nil,
                                bundleIdentifier: bid,
                                title: title,
                                reason: "verifyText failed: '\(text)' mustExist=\(mustExist)"
                            )
                        }
                        return // Abort synchronously
                    }
                    let actual = playbackClock.now()
                    if actual - scheduledTime > 0.04 {
                        scheduledTime = actual
                    }
                    continue
                }

                let point: CGPoint
                if #available(macOS 14.0, *), (event.coordinateStrategy == .locatorOnly || event.textAnchor != nil) {
                    let cacheKey = Player.locatorCacheKey(for: event, surfaceId: targetSurfaceId)
                    if let cacheKey,
                       let cached = recentLocatorPoint,
                       cached.key == cacheKey,
                       abs(event.time - cached.eventTime) <= 1.0 {
                        point = cached.point
                    } else {
                        let contextSnapshot = runningContext
                        let resolution = awaitSynchronously {
                            let locator = LocatorEngine()
                            var strategies: [LocatorStrategy] = []
                            if let anchor = event.textAnchor {
                                strategies.append(.ocr(anchor))
                            }
                            do {
                                let resolvedPoint = try await Player.locateWithOptionalWait(
                                    locator: locator,
                                    event: event,
                                    context: contextSnapshot,
                                    strategies: strategies,
                                    clock: playbackClock
                                )
                                return PlaybackPointResolution.success(resolvedPoint)
                            } catch {
                                if event.locatorFallbackPolicy == .allowCoordinateFallback {
                                    if let fallbackPoint = Player.coordinateFallbackPoint(for: event, surfaceId: targetSurfaceId, context: contextSnapshot) {
                                        return PlaybackPointResolution.success(fallbackPoint)
                                    } else {
                                        switch resolver.resolve(event, context: contextSnapshot) {
                                        case .success(let pt):
                                            return PlaybackPointResolution.success(pt)
                                        case .failure(let fallbackError):
                                            return PlaybackPointResolution.failure(String(describing: fallbackError))
                                        }
                                    }
                                }

                                return PlaybackPointResolution.failure(String(describing: error))
                            }
                        }
                        guard let pt = resolution.point else {
                            let reason = resolution.failureReason ?? "locator resolution failed"
                            #if DEBUG
                            NSLog("SparkleRecorder: locator resolution error: \(reason)")
                            #endif
                            if !hasCapturedFailure {
                                hasCapturedFailure = true
                                let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                recordFailureEvidenceSynchronously(
                                    macroID: macroID,
                                    startTime: Date(),
                                    duration: 0,
                                    failedEventIndex: nil,
                                    bundleIdentifier: bid,
                                    title: title,
                                    reason: reason
                                )
                            }
                            return
                        }
                        point = pt
                        if let cacheKey {
                            recentLocatorPoint = (cacheKey, pt, event.time)
                        }
                    }
                } else {
                    let resolvedResult = resolver.resolve(event, context: runningContext)
                    switch resolvedResult {
                    case .success(let pt):
                        point = pt
                    case .failure(let error):
                        #if DEBUG
                        NSLog("SparkleRecorder: point resolve error: \(error)")
                        #endif
                        if !hasCapturedFailure {
                            hasCapturedFailure = true
                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                            recordFailureEvidenceSynchronously(
                                macroID: macroID,
                                startTime: Date(),
                                duration: 0,
                                failedEventIndex: nil,
                                bundleIdentifier: bid,
                                title: title,
                                reason: "\(error)"
                            )
                        }
                        return
                    }
                }

                eventPoster.post(event, point)
                let postTime = playbackClock.now()
                if postTime - scheduledTime > 0.04 {
                    scheduledTime = postTime
                }
            }
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

    @available(macOS 14.0, *)
    nonisolated private static func locateWithOptionalWait(locator: LocatorEngine, event: RecordedEvent, context: PlaybackContext, strategies: [LocatorStrategy], clock: PlaybackClockClient = .live) async throws -> CGPoint {
        guard event.kind.isMouse, event.textAnchor != nil, let timeout = event.textTimeout, timeout > 0 else {
            return try await locator.locate(event: event, context: context, strategies: strategies)
        }

        let startedAt = clock.now()
        var lastError: Error = VisionDetectorError.textNotMatched
        while clock.now() - startedAt < timeout {
            do {
                return try await locator.locate(event: event, context: context, strategies: strategies)
            } catch {
                lastError = error
                await clock.sleep(0.25)
            }
        }
        throw lastError
    }

    nonisolated private static func locatorCacheKey(for event: RecordedEvent, surfaceId: String) -> String? {
        guard let anchor = event.textAnchor else { return nil }
        return [
            surfaceId,
            anchor.text,
            anchor.matchMode.rawValue,
            rectKey(anchor.observedContentNormalizedFrame ?? anchor.observedFrame),
            rectKey(anchor.searchContentNormalizedRegion ?? anchor.searchRegion),
            pointKey(anchor.coordinateFallbackContentNormalized ?? anchor.coordinateFallback)
        ].joined(separator: "|")
    }

    nonisolated private static func rectKey(_ rect: RectValue?) -> String {
        guard let rect else { return "-" }
        return String(format: "%.4f,%.4f,%.4f,%.4f", rect.x, rect.y, rect.width, rect.height)
    }

    nonisolated private static func pointKey(_ point: PointValue?) -> String {
        guard let point else { return "-" }
        return String(format: "%.4f,%.4f", point.x, point.y)
    }

    nonisolated private static func coordinateFallbackPoint(for event: RecordedEvent, surfaceId: String, context: PlaybackContext) -> CGPoint? {
        guard let anchor = event.textAnchor,
              let windowFrame = context.currentSurfaceFrames[surfaceId] else { return nil }

        let point: CGPoint?
        if let normalized = anchor.coordinateFallbackContentNormalized,
           let contentFrame = context.currentContentFrames[surfaceId] {
            point = CGPoint(
                x: contentFrame.x + normalized.x * contentFrame.width,
                y: contentFrame.y + normalized.y * contentFrame.height
            )
        } else if let fallback = anchor.coordinateFallback {
            point = CGPoint(x: fallback.x, y: fallback.y)
        } else {
            point = nil
        }

        guard let point,
              CoordinateMapper().assertPointIsInsideWindow(point, in: windowFrame) else {
            return nil
        }
        return point
    }
}

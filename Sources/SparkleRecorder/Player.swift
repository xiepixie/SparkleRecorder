import Cocoa
import CoreGraphics
import Combine
import SparkleRecorderCore

final class PlaybackClock: ObservableObject {
    @Published var progress: Double = 0
}

private final class PlaybackConflictMonitor {
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

/// Replays a recorded macro by posting CGEvents at the original relative timestamps.
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

    /// Play the macro `loops` times. Pass `loops <= 0` for continuous (infinite) playback,
    /// which only stops on `stop()` or the configured stop hotkey.
    /// The completion receives `true` only when playback ran to natural completion —
    /// `false` for cancellation, so callers can skip chains/stats/sounds on abort.
    func play(events: [RecordedEvent], loops: Int = 1, speed: Double = 1.0, context: PlaybackContext = PlaybackContext(), windowTracker: WindowTracker? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !isPlaying, !events.isEmpty else { completion?(false); return }
        let infinite = (loops <= 0)
        let total = infinite ? 0 : max(1, loops)

        generation &+= 1
        let gen = generation
        let monitor = PlaybackConflictMonitor()
        monitor.start()
        conflictMonitor = monitor
        isPlaying = true
        clock.progress = 0
        currentLoop = 0
        totalLoops = total
        let speed = max(0.1, min(speed, 10.0))
        let lastTime = events.last?.time ?? 0

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
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
                await MainActor.run {
                    if self.generation == gen { self.currentLoop = snapshot }
                }
                
                // Activate target apps upfront for this loop iteration
                for surface in runningContext.surfaces.values {
                    if let bid = surface.bundleIdentifier,
                       let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
                        if #available(macOS 14.0, *) {
                            app.activate()
                        } else {
                            app.activate(options: [.activateIgnoringOtherApps])
                        }
                    }
                }
                
                // Allow app to activate
                try? await Task.sleep(nanoseconds: 200_000_000)
                
                runningContext.currentSurfaceFrames.removeAll()
                runningContext.currentContentFrames.removeAll()
                runningContext.currentTitleBarHeights.removeAll()
                
                // Resolve all current outer frames and content frames upfront
                if let tracker = windowTracker {
                    let outerFrames = tracker.resolveCurrentFrames(for: runningContext.surfaces)
                    for (surfaceId, frame) in outerFrames {
                        runningContext.currentSurfaceFrames[surfaceId] = frame
                        
                        let bid = runningContext.surfaces[surfaceId]?.bundleIdentifier
                        let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                        
                        let resolved = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: frame)
                        runningContext.currentContentFrames[surfaceId] = RectValue(x: resolved.frame.minX, y: resolved.frame.minY, width: resolved.frame.width, height: resolved.frame.height)
                        runningContext.currentTitleBarHeights[surfaceId] = max(0, resolved.frame.minY - frame.y)
                    }
                }
                
	                var scheduledTime = CFAbsoluteTimeGetCurrent()
	                var previousEventTime: TimeInterval = 0
                    var recentLocatorPoint: (key: String, point: CGPoint, eventTime: TimeInterval)? = nil
	                for event in events {
                    if Task.isCancelled { break outer }
                    let eventDelta = max(0, event.time - previousEventTime) / speed
                    scheduledTime += eventDelta
                    previousEventTime = event.time
                    
                    let target = scheduledTime
                    let now = CFAbsoluteTimeGetCurrent()
                    let delay = target - now
	                    if delay > 0.002 {
	                        try? await Task.sleep(nanoseconds: UInt64((delay - 0.0005) * 1_000_000_000))
	                    }
                    while CFAbsoluteTimeGetCurrent() < target { }
                    if Task.isCancelled { break outer }
                    if monitor.hasConflict {
                        aborted = true
                        break outer
                    }
                    
                    let targetSurfaceId: String
                    if let sId = event.surfaceId, runningContext.surfaces[sId] != nil {
                        targetSurfaceId = sId
                    } else if let firstKey = runningContext.surfaces.keys.first {
                        targetSurfaceId = firstKey
                    } else {
                        targetSurfaceId = event.surfaceId ?? "surface-1"
                    }

                    if event.kind == .waitForText, let anchor = event.textAnchor {
                        let text = anchor.text
                        let timeout = event.textTimeout ?? 10.0
                        let startPoll = CFAbsoluteTimeGetCurrent()
                        var found = false
                        if #available(macOS 14.0, *) {
                            let locator = LocatorEngine()
                            while CFAbsoluteTimeGetCurrent() - startPoll < timeout {
                                if Task.isCancelled { break outer }
                                do {
                                    _ = try await locator.locate(event: event, context: runningContext, strategies: [.ocr(anchor)])
                                    found = true
                                    break
                                } catch {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
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
                                        do {
                                            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                            _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "waitForText timeout: '\(text)'")
                                        } catch {}
                                    }
                                }
                            }
                            break outer // Abort execution
                        }
                        scheduledTime = CFAbsoluteTimeGetCurrent()
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
                                        do {
                                            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                            _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "verifyText failed: '\(text)' mustExist=\(mustExist)")
                                        } catch {}
                                    }
                                }
                            }
                            break outer // Abort execution
                        }
                        let actual = CFAbsoluteTimeGetCurrent()
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
                                    point = try await Player.locateWithOptionalWait(locator: locator, event: event, context: runningContext, strategies: strategies)
                                    if let cacheKey {
                                        recentLocatorPoint = (cacheKey, point, event.time)
                                    }
                                } catch {
                                    if event.locatorFallbackPolicy == .allowCoordinateFallback {
                                        if let fallbackPoint = Player.coordinateFallbackPoint(for: event, surfaceId: targetSurfaceId, context: runningContext) {
                                            point = fallbackPoint
                                        } else {
                                            let resolvedResult = self.pointResolver.resolve(event, context: runningContext)
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
                                                    Task {
                                                        do {
                                                            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                                            _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "\(fallbackError)")
                                                        } catch {}
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
                                            Task {
                                                do {
                                                    let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                                    _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "\(error)")
                                                } catch {}
                                            }
                                        }
                                        break outer
                                    }
                                }
                            }
                    } else {
                        let resolvedResult = self.pointResolver.resolve(event, context: runningContext)
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
                                        do {
                                            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                            _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "\(error)")
                                        } catch {}
                                    }
                                }
                            }
                            break outer
                        }
                    }
                    
                    Player.post(event, at: point)
                    let postTime = CFAbsoluteTimeGetCurrent()
                    if postTime - scheduledTime > 0.04 {
                        scheduledTime = postTime
                    }
                    if lastTime > 0, postTime - lastProgressPush > 0.033 {
                        lastProgressPush = postTime
                        let p = min(1.0, event.time / lastTime)
                        await MainActor.run {
                            if self.generation == gen {
                                self.clock.progress = p
                            }
                        }
                    }
                }
            }
            let didAbort = aborted
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                // Evaluate on the main actor so it's serialized with stop().
                monitor.stop()
                if self.conflictMonitor === monitor {
                    self.conflictMonitor = nil
                }
                let finished = !wasCancelled && !didAbort
                if self.generation == gen {
                    self.isPlaying = false
                    self.clock.progress = 0
                    self.currentLoop = 0
                    self.totalLoops = 1
                }
                completion?(finished)
            }
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

    /// Synchronous playback for CLI mode — no MainActor hops, no published state.
    /// Blocks the calling (background) thread until done.
    static func playSynchronously(events: [RecordedEvent], loops: Int, speed: Double, context: PlaybackContext = PlaybackContext(), windowTracker: WindowTracker? = nil) {
        guard !events.isEmpty else { return }
        let speed = max(0.1, min(speed, 10.0))
        let total = max(1, loops)
        let resolver = PointResolver()
        let monitor = PlaybackConflictMonitor()
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<total {
            // Activate target apps upfront for this loop iteration
            for surface in context.surfaces.values {
                if let bid = surface.bundleIdentifier,
                   let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
                    if #available(macOS 14.0, *) {
                        app.activate()
                    } else {
                        app.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            }
            var runningContext = context
            runningContext.currentSurfaceFrames.removeAll()
            runningContext.currentContentFrames.removeAll()
            runningContext.currentTitleBarHeights.removeAll()
            
            // Allow app to activate
            Thread.sleep(forTimeInterval: 0.2)
            
            // Resolve all current outer frames and content frames upfront
            if let tracker = windowTracker {
                let outerFrames = tracker.resolveCurrentFrames(for: runningContext.surfaces)
                for (surfaceId, frame) in outerFrames {
                    runningContext.currentSurfaceFrames[surfaceId] = frame
                    
                    let bid = runningContext.surfaces[surfaceId]?.bundleIdentifier
                    let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                    
                    let resolved = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: frame)
                    runningContext.currentContentFrames[surfaceId] = RectValue(x: resolved.frame.minX, y: resolved.frame.minY, width: resolved.frame.width, height: resolved.frame.height)
                    runningContext.currentTitleBarHeights[surfaceId] = max(0, resolved.frame.minY - frame.y)
                }
            }
            
	            var scheduledTime = CFAbsoluteTimeGetCurrent()
	            var previousEventTime: TimeInterval = 0
                var recentLocatorPoint: (key: String, point: CGPoint, eventTime: TimeInterval)? = nil
	            for event in events {
                let eventDelta = max(0, event.time - previousEventTime) / speed
                scheduledTime += eventDelta
                previousEventTime = event.time
                
                let target = scheduledTime
                let delay = target - CFAbsoluteTimeGetCurrent()
	                if delay > 0.002 {
	                    Thread.sleep(forTimeInterval: delay - 0.0005)
	                }
                while CFAbsoluteTimeGetCurrent() < target { }
                if monitor.hasConflict {
                    return
                }
                var hasCapturedFailure = false
                let targetSurfaceId: String
                if let sId = event.surfaceId, runningContext.surfaces[sId] != nil {
                    targetSurfaceId = sId
                } else if let firstKey = runningContext.surfaces.keys.first {
                    targetSurfaceId = firstKey
                } else {
                    targetSurfaceId = event.surfaceId ?? "surface-1"
                }
                
                if runningContext.currentSurfaceFrames[targetSurfaceId] == nil {
                    if let tracker = windowTracker, let surface = runningContext.surfaces[targetSurfaceId] {
                        let frames = tracker.resolveCurrentFrames(for: [targetSurfaceId: surface])
                        if let frame = frames[targetSurfaceId] {
                            runningContext.currentSurfaceFrames[targetSurfaceId] = frame
                            
                            let bid = surface.bundleIdentifier
                            let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                            
                            let resolved = CoordinateMapper.resolveContentFrame(for: pid, outerFrame: frame)
                            runningContext.currentContentFrames[targetSurfaceId] = RectValue(x: resolved.frame.minX, y: resolved.frame.minY, width: resolved.frame.width, height: resolved.frame.height)
                            runningContext.currentTitleBarHeights[targetSurfaceId] = max(0, resolved.frame.minY - frame.y)
                            
                            if let bid = surface.bundleIdentifier,
                               let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
                                if #available(macOS 14.0, *) {
                                    app.activate()
                                } else {
                                    app.activate(options: [.activateIgnoringOtherApps])
                                }
                            }
                        }
                    }
                }
                if event.kind == .waitForText, let anchor = event.textAnchor {
                    let text = anchor.text
                    let timeout = event.textTimeout ?? 10.0
                    let startPoll = CFAbsoluteTimeGetCurrent()
                    var found = false
                    if #available(macOS 14.0, *) {
                        let sem = DispatchSemaphore(value: 0)
                        Task {
                            let locator = LocatorEngine()
                            while CFAbsoluteTimeGetCurrent() - startPoll < timeout {
                                do {
                                    _ = try await locator.locate(event: event, context: runningContext, strategies: [.ocr(anchor)])
                                    found = true
                                    break
                                } catch {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                }
                            }
                            sem.signal()
                        }
                        sem.wait()
                    }
                    if !found {
                        if !hasCapturedFailure {
                            hasCapturedFailure = true
                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                            Task {
                                if #available(macOS 14.0, *) {
                                    do {
                                        let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                        _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "waitForText timeout: '\(text)'")
                                    } catch {}
                                }
                            }
                        }
                        return // Abort synchronously
                    }
                    scheduledTime = CFAbsoluteTimeGetCurrent()
                    continue
                }
                if event.kind == .verifyText, let anchor = event.textAnchor {
                    let text = anchor.text
                    let mustExist = event.verifyMustExist ?? true
                    var found = false
                    if #available(macOS 14.0, *) {
                        let sem = DispatchSemaphore(value: 0)
                        Task {
                            let locator = LocatorEngine()
                            do {
                                _ = try await locator.locate(event: event, context: runningContext, strategies: [.ocr(anchor)])
                                found = true
                            } catch {}
                            sem.signal()
                        }
                        sem.wait()
                    }
                    if found != mustExist {
                        if !hasCapturedFailure {
                            hasCapturedFailure = true
                            let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                            let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                            Task {
                                if #available(macOS 14.0, *) {
                                    do {
                                        let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                        _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "verifyText failed: '\(text)' mustExist=\(mustExist)")
                                    } catch {}
                                }
                            }
                        }
                        return // Abort synchronously
                    }
                    let actual = CFAbsoluteTimeGetCurrent()
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
                        var resolvedPoint: CGPoint? = nil
                        let sem = DispatchSemaphore(value: 0)
                        Task {
                            let locator = LocatorEngine()
                            var strategies: [LocatorStrategy] = []
                            if let anchor = event.textAnchor {
                                strategies.append(.ocr(anchor))
                            }
                            do {
                                resolvedPoint = try await Player.locateWithOptionalWait(locator: locator, event: event, context: runningContext, strategies: strategies)
                            } catch {
                                if event.locatorFallbackPolicy == .allowCoordinateFallback {
                                    if let fallbackPoint = Player.coordinateFallbackPoint(for: event, surfaceId: targetSurfaceId, context: runningContext) {
                                        resolvedPoint = fallbackPoint
                                    } else if case .success(let pt) = resolver.resolve(event, context: runningContext) {
                                        resolvedPoint = pt
                                    }
                                }
                                
                                if resolvedPoint == nil, !hasCapturedFailure {
                                    hasCapturedFailure = true
                                    let bid = runningContext.surfaces[targetSurfaceId]?.bundleIdentifier
                                    let title = runningContext.surfaces[targetSurfaceId]?.windowTitle
                                    Task {
                                        do {
                                            let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                            _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "\(error)")
                                        } catch {}
                                    }
                                }
                            }
                            sem.signal()
                        }
                        sem.wait()
                        guard let pt = resolvedPoint else { return }
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
                            let sem = DispatchSemaphore(value: 0)
                            Task {
                                if #available(macOS 14.0, *) {
                                    do {
                                        let image = try await ScreenCaptureService.shared.captureWindow(bundleIdentifier: bid, title: title)
                                        _ = await ScreenCaptureService.shared.saveFailureSnapshot(image: image, reason: "\(error)")
                                    } catch {}
                                }
                                sem.signal()
                            }
                        }
                        return
                    }
                }
                
                Player.post(event, at: point)
                let postTime = CFAbsoluteTimeGetCurrent()
                if postTime - scheduledTime > 0.04 {
                    scheduledTime = postTime
                }
            }
        }
    }

    // MARK: - Posting

    private static let synthesizer = MouseKeyboardSynthesizer()
    
    @available(macOS 14.0, *)
    private static func locateWithOptionalWait(locator: LocatorEngine, event: RecordedEvent, context: PlaybackContext, strategies: [LocatorStrategy]) async throws -> CGPoint {
        guard event.kind.isMouse, event.textAnchor != nil, let timeout = event.textTimeout, timeout > 0 else {
            return try await locator.locate(event: event, context: context, strategies: strategies)
        }
        
        let startedAt = CFAbsoluteTimeGetCurrent()
        var lastError: Error = VisionDetectorError.textNotMatched
        while CFAbsoluteTimeGetCurrent() - startedAt < timeout {
            do {
                return try await locator.locate(event: event, context: context, strategies: strategies)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError
    }
    
    private static func locatorCacheKey(for event: RecordedEvent, surfaceId: String) -> String? {
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
    
    private static func rectKey(_ rect: RectValue?) -> String {
        guard let rect else { return "-" }
        return String(format: "%.4f,%.4f,%.4f,%.4f", rect.x, rect.y, rect.width, rect.height)
    }
    
    private static func pointKey(_ point: PointValue?) -> String {
        guard let point else { return "-" }
        return String(format: "%.4f,%.4f", point.x, point.y)
    }
    
    private static func coordinateFallbackPoint(for event: RecordedEvent, surfaceId: String, context: PlaybackContext) -> CGPoint? {
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

    private static func post(_ ev: RecordedEvent, at point: CGPoint) {
        synthesizer.synthesize(ev, at: point)
    }
}

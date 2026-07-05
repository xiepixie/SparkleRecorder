import Cocoa
import CoreGraphics
import Combine
import SparkleRecorderCore
import os

/// Captures live mouse + keyboard events into an in-memory macro using a CGEventTap.
final class Recorder: ObservableObject, EventTapThreadDelegate {
    @Published private(set) var isRecording = false
    @Published public var events: [RecordedEvent] = []
    @Published public var liveDuration: Double = 0
    @Published public var liveStats: (clicks: Int, keys: Int, scrolls: Int, drags: Int) = (0, 0, 0, 0)
    @Published public private(set) var activeSurfaces: [String: PlaybackSurface] = [:]

    private var tapThread: EventTapThread?
    private var baseMachTicks: UInt64 = 0
    private var baseEventTimestamp: UInt64? = nil
    private var isResumedSession = false
    private var resumeOffsetDuration: Double = 0
    private var activeSurfaceId: String? = nil
    private var activeGestureSurfaceId: String? = nil
    private let surfaceTracker = RecordingSurfaceTracker()
    private let surfaceMatcher = SurfaceMatcher()
    private var contentFrameCache: [String: CGRect] = [:]
    private let stateLock = OSAllocatedUnfairLock()
    private var recordedSurfaces: [String: PlaybackSurface] = [:]
    private var recordMouseMovesEnabled = false
    
    // Drag downsampling state
    private let sampler = TrajectorySampler()
    
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private var displayTimer: Timer?
    /// Captured events accumulate here on the event tap thread and flush into
    /// the @Published array on the UI timer. Per-event
    /// @Published mutations caused a SwiftUI re-render per input event, which
    /// could starve the tap into timeout during fast input.
    private var pending: [RecordedEvent] = []

    /// Key codes the recorder must NOT capture (our own hotkeys).
    var ignoredKeyCodes: Set<UInt16> = []

    var eventCount: Int { events.count }

    deinit {
        tapThread?.stop()
        displayTimer?.invalidate()
    }

    /// Replace the in-memory event list (used when opening a saved macro).
    public func loadEvents(_ new: [RecordedEvent], duration: Double? = nil) {
        events = new
        if let d = duration {
            liveDuration = d
        }
        recalculateStats()
    }

    // MARK: - Editing

    @discardableResult
    func startRecording() -> Bool {
        guard !isRecording else { return true }
        events.removeAll()
        pending.removeAll()
        liveDuration = 0
        recalculateStats()
        baseMachTicks = mach_absolute_time()
        baseEventTimestamp = nil
        isResumedSession = false
        resumeOffsetDuration = 0
        recordMouseMovesEnabled = UserDefaults.standard.bool(forKey: "recordMouseMoves")
        
        contentFrameCache.removeAll()
        activeSurfaces.removeAll()
        stateLock.withLock {
            self.recordedSurfaces.removeAll()
            self.activeSurfaceId = nil
            self.activeGestureSurfaceId = nil
        }
        self.surfaceTracker.startTracking()

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)     |
            (1 << CGEventType.leftMouseUp.rawValue)       |
            (1 << CGEventType.rightMouseDown.rawValue)    |
            (1 << CGEventType.rightMouseUp.rawValue)      |
            (1 << CGEventType.mouseMoved.rawValue)        |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)           |
            (1 << CGEventType.keyUp.rawValue)             |
            (1 << CGEventType.flagsChanged.rawValue)      |
            (1 << CGEventType.scrollWheel.rawValue)       |
            (1 << CGEventType.otherMouseDown.rawValue)    |
            (1 << CGEventType.otherMouseUp.rawValue)      |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let thread = EventTapThread(mask: mask)
        thread.delegate = self
        thread.start()
        self.tapThread = thread

        isRecording = true
        startDisplayTimer()
        return true
    }

    func stopRecording() {
        guard isRecording else { return }
        tapThread?.stop()
        tapThread = nil
        surfaceTracker.stopTracking()
        stopDisplayTimer()
        flushPending()
        isRecording = false
        liveDuration = events.last?.time ?? 0
    }

    private func flushPending() {
        let snapshot = stateLock.withLock {
            let events = self.pending
            self.pending.removeAll()
            return (events, self.recordedSurfaces)
        }
        
        activeSurfaces = snapshot.1
        guard !snapshot.0.isEmpty else { return }
        
        var newClicks = 0, newKeys = 0, newScrolls = 0, newDrags = 0
        for ev in snapshot.0 {
            switch ev.kind {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: newClicks += 1
            case .keyDown: newKeys += 1
            case .scrollWheel: newScrolls += 1
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: newDrags += 1
            default: break
            }
        }
        
        liveStats.clicks += newClicks
        liveStats.keys += newKeys
        liveStats.scrolls += newScrolls
        liveStats.drags += newDrags
        
        events.append(contentsOf: snapshot.0)
    }
    
    public func clearAll() {
        events.removeAll()

        recalculateStats()
    }

    public func recalculateStats() {
        var clicks = 0, keys = 0, scrolls = 0, drags = 0
        for ev in events {
            switch ev.kind {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: clicks += 1
            case .keyDown: keys += 1
            case .scrollWheel: scrolls += 1
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: drags += 1
            default: break
            }
        }
        liveStats = (clicks, keys, scrolls, drags)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isRecording {
                self.flushPending()
                let currentMachTicks = mach_absolute_time()
                let elapsedTicks = currentMachTicks >= self.baseMachTicks ? currentMachTicks - self.baseMachTicks : 0
                let elapsedNanos = elapsedTicks * UInt64(Recorder.timebaseInfo.numer) / UInt64(Recorder.timebaseInfo.denom)
                self.liveDuration = self.resumeOffsetDuration + (Double(elapsedNanos) / 1_000_000_000.0)
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func eventTapThread(_ thread: EventTapThread, didReceive type: CGEventType, event: CGEvent) {
        guard let kind = RecordedEvent.Kind(rawValue: Int(type.rawValue)) else { return }

        if kind == .mouseMoved && !recordMouseMovesEnabled {
            return
        }
        
        let loc = event.location
        let eventTimestamp = UInt64(event.timestamp)
        
        if baseEventTimestamp == nil {
            baseEventTimestamp = eventTimestamp
        }
        
        let elapsedNanos = eventTimestamp >= baseEventTimestamp! ? eventTimestamp - baseEventTimestamp! : 0
        let elapsed = resumeOffsetDuration + (Double(elapsedNanos) / 1_000_000_000.0)
        
        // Drag downsampling via TrajectorySampler
        if type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            if !sampler.shouldSampleDrag(event: event, type: type, location: loc, time: elapsed) {
                return // Drop this drag event
            }
        } else if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            sampler.processMouseDown(location: loc, time: elapsed)
        } else if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
            if let ignored = sampler.processMouseUp() {
                // Process the last dragged event before the mouse up using its original elapsed time
                processEvent(ignored.event, type: ignored.type, elapsed: ignored.elapsed)
            }
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if kind.isKey, ignoredKeyCodes.contains(keyCode) { return }
        
        processEvent(event, type: type, elapsed: elapsed)
    }
    
    private func processEvent(_ event: CGEvent, type: CGEventType, elapsed: Double) {
        guard let kind = RecordedEvent.Kind(rawValue: Int(type.rawValue)) else { return }
        let loc = event.location
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        var (currentActiveSurfaces, currentActiveSurfaceId, currentActiveGestureSurfaceId) = stateLock.withLock {
            return (self.recordedSurfaces, self.activeSurfaceId, self.activeGestureSurfaceId)
        }
        
        // Reorder surface creation/matching before mouse down binding
        var updatedSurfaces = currentActiveSurfaces
        var updatedSurfaceId = currentActiveSurfaceId
        
        if let currentFocusedWindow = surfaceTracker.cachedActiveSurface {
            if let existingId = surfaceMatcher.match(currentFocusedWindow, against: updatedSurfaces) {
                updatedSurfaceId = existingId
                updatedSurfaces[existingId] = currentFocusedWindow
            } else {
                let nextId = "surface-\(updatedSurfaces.count + 1)"
                updatedSurfaces[nextId] = currentFocusedWindow
                updatedSurfaceId = nextId
            }
        }
        
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            currentActiveGestureSurfaceId = updatedSurfaceId
        }
        
        let targetId = currentActiveGestureSurfaceId ?? updatedSurfaceId
        
        var nextGestureSurfaceId = currentActiveGestureSurfaceId
        if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
            nextGestureSurfaceId = nil
        }
        
        var localX: CGFloat? = nil
        var localY: CGFloat? = nil
        var normX: CGFloat? = nil
        var normY: CGFloat? = nil
        
        var cLocalX: CGFloat? = nil
        var cLocalY: CGFloat? = nil
        var cNormX: CGFloat? = nil
        var cNormY: CGFloat? = nil
        
        var binding: CoordinateBinding = .unbound
        
        if let sId = targetId, let surface = updatedSurfaces[sId] {
            let frame = surface.recordedFrame
            let isInsideSurface = loc.x >= frame.x && 
                                  loc.x <= (frame.x + frame.width) && 
                                  loc.y >= frame.y && 
                                  loc.y <= (frame.y + frame.height)
            
            if isInsideSurface {
                let lx = loc.x - frame.x
                let ly = loc.y - frame.y
                
                let contentFrame: CGRect
                if let rectContentFrame = surface.recordedContentFrame {
                    contentFrame = CGRect(x: rectContentFrame.x, y: rectContentFrame.y, width: rectContentFrame.width, height: rectContentFrame.height)
                } else {
                    // The tap callback must not perform AX traversal. The
                    // background surface tracker normally provides a content
                    // frame; if it is missing, use a cheap whole-window content
                    // fallback and let playback re-resolve precisely.
                    contentFrame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                    var modifiedSurface = surface
                    modifiedSurface.recordedContentFrame = RectValue(x: contentFrame.minX, y: contentFrame.minY, width: contentFrame.width, height: contentFrame.height)
                    modifiedSurface.contentFrameSource = CoordinateMapper.ResolvedContentFrame.Source.fallbackOuterFrame.rawValue
                    updatedSurfaces[sId] = modifiedSurface
                }
                
                // Old coordinate fallback
                localX = lx
                let tbHeight = contentFrame.minY - frame.y
                localY = ly - tbHeight
                normX = frame.width > 0 ? lx / frame.width : 0
                let clientHeight = max(1.0, frame.height - tbHeight)
                normY = ly >= tbHeight ? (ly - tbHeight) / clientHeight : 0
                
                // New content coordinate model
                cLocalX = loc.x - contentFrame.minX
                cLocalY = loc.y - contentFrame.minY
                cNormX = contentFrame.width > 0 ? cLocalX! / contentFrame.width : 0
                cNormY = contentFrame.height > 0 ? cLocalY! / contentFrame.height : 0
                
                binding = .targetWindow
            } else {
                binding = .globalScreen
            }
        }

        var unicodeStr: String? = nil
        if kind.isKey {
            var chars = [UniChar](repeating: 0, count: 4)
            var actualStringLength = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualStringLength, unicodeString: &chars)
            if actualStringLength > 0 {
                unicodeStr = String(utf16CodeUnits: chars, count: actualStringLength)
            }
        }
        
        let scrollPayload: ScrollPayload?
        if kind == .scrollWheel {
            let pointDeltaX = CGFloat(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            let pointDeltaY = CGFloat(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let lineDeltaX = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            let lineDeltaY = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            let fixedRawX = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let fixedRawY = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
            scrollPayload = ScrollPayload(
                deltaX: pointDeltaX,
                deltaY: pointDeltaY,
                lineDeltaX: lineDeltaX,
                lineDeltaY: lineDeltaY,
                phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
                fixedDeltaX: fixedRawX == 0 ? nil : Double(fixedRawX) / 65_536.0,
                fixedDeltaY: fixedRawY == 0 ? nil : Double(fixedRawY) / 65_536.0,
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            )
        } else {
            scrollPayload = nil
        }

        let recorded = RecordedEvent(
            kind: kind,
            time: elapsed,
            x: loc.x,
            y: loc.y,
            keyCode: keyCode,
            flags: event.flags.rawValue,
            mouseButton: event.getIntegerValueField(.mouseEventButtonNumber),
            clickCount: event.getIntegerValueField(.mouseEventClickState),
            scrollDeltaY: {
                let p = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
                return p == 0 ? Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 12 : p
            }(),
            scrollDeltaX: {
                let p = Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
                return p == 0 ? Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * 12 : p
            }(),
            windowLocalX: localX, windowLocalY: localY,
            windowNormalizedX: normX, windowNormalizedY: normY,
            contentLocalX: cLocalX, contentLocalY: cLocalY,
            contentNormalizedX: cNormX, contentNormalizedY: cNormY,
            coordinateBinding: binding, coordinateStrategy: nil,
            surfaceId: targetId,
            scrollPayload: scrollPayload,
            unicodeString: unicodeStr
        )

        // Display timer will flush from pending into events
        stateLock.withLock { [updatedSurfaces, updatedSurfaceId, nextGestureSurfaceId, recorded] in
            self.recordedSurfaces = updatedSurfaces
            self.activeSurfaceId = updatedSurfaceId
            self.activeGestureSurfaceId = nextGestureSurfaceId
            self.pending.append(recorded)
        }
    }
}

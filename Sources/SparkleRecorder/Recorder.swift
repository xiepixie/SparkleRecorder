import Cocoa
import CoreGraphics
import Combine
import SparkleRecorderCore
import os

private struct RecorderBufferState: Sendable {
    var pending: [RecordedEvent] = []
    var registry = RecordingSurfaceRegistry()
}

private final class RecorderEventBuffer: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: RecorderBufferState())

    func reset() {
        lock.withLock {
            $0 = RecorderBufferState()
        }
    }

    func drainPending() -> (events: [RecordedEvent], surfaces: [String: PlaybackSurface]) {
        lock.withLock {
            let events = $0.pending
            $0.pending.removeAll()
            return (events, $0.registry.activeSurfaces)
        }
    }

    func trackingState() -> RecordingSurfaceRegistry {
        lock.withLock {
            $0.registry
        }
    }

    func store(
        registry: RecordingSurfaceRegistry,
        event: RecordedEvent
    ) {
        lock.withLock {
            $0.registry = registry
            $0.pending.append(event)
        }
    }
}

private final class RecorderDisplayTimerTarget: NSObject {
    weak var recorder: Recorder?

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    @objc func tick(_ timer: Timer) {
        recorder?.displayTimerDidFire()
    }
}

/// Captures live mouse + keyboard events into an in-memory macro using an async event stream.
final class Recorder: ObservableObject, @unchecked Sendable {
    @Published private(set) var isRecording = false
    @Published public var events: [RecordedEvent] = []
    @Published public var liveDuration: Double = 0
    @Published public var liveStats = RecordingStats.zero
    @Published public private(set) var liveWaveformEvents: [RecordedEvent] = []
    @Published public private(set) var activeSurfaces: [String: PlaybackSurface] = [:]

    private var engineClient: RecordingEngineClient?
    private var recordingTask: Task<Void, Never>?
    private var baseMachTicks: UInt64 = 0
    private var baseEventTimestamp: UInt64? = nil
    private var isResumedSession = false
    private var resumeOffsetDuration: Double = 0
    private let surfaceTracker = RecordingSurfaceTracker()
    private let surfaceMatcher = SurfaceMatcher()
    private var contentFrameCache: [String: CGRect] = [:]
    private let eventBuffer = RecorderEventBuffer()
    private var recordMouseMovesEnabled = false
    private lazy var displayTimerTarget = RecorderDisplayTimerTarget(recorder: self)
    
    // Drag downsampling state
    private let sampler = TrajectorySampler()
    
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
    private static let recordingTimebase = RecordingTimebase(
        numer: UInt64(timebaseInfo.numer),
        denom: UInt64(timebaseInfo.denom)
    )
    private var displayTimer: Timer?
    private let maxLiveWaveformEvents = 150
    /// Captured events accumulate here on the event tap thread and flush into
    /// the @Published array on the UI timer. Per-event
    /// @Published mutations caused a SwiftUI re-render per input event, which
    /// could starve the tap into timeout during fast input.

    /// Key codes the recorder must NOT capture (our own hotkeys).
    var ignoredKeyCodes: Set<UInt16> = []

    var eventCount: Int { events.count }

    deinit {
        engineClient?.stop()
        recordingTask?.cancel()
        displayTimer?.invalidate()
    }

    /// Replace the in-memory event list (used when opening a saved macro).
    public func loadEvents(_ new: [RecordedEvent], duration: Double? = nil) {
        events = new
        liveWaveformEvents = Self.cappedWaveformEvents(new, maxCount: maxLiveWaveformEvents)
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
        liveWaveformEvents.removeAll()
        eventBuffer.reset()
        liveDuration = 0
        recalculateStats()
        baseMachTicks = mach_absolute_time()
        baseEventTimestamp = nil
        isResumedSession = false
        resumeOffsetDuration = 0
        recordMouseMovesEnabled = UserDefaults.standard.bool(forKey: "recordMouseMoves")
        
        contentFrameCache.removeAll()
        activeSurfaces.removeAll()
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

        let client = RecordingEngineClient.live(mask: mask)
        self.engineClient = client
        
        recordingTask = Task { [weak self] in
            for await raw in client.events() {
                self?.processRawEvent(type: raw.type, event: raw.event)
            }
        }
        
        client.start()

        isRecording = true
        startDisplayTimer()
        return true
    }

    func stopRecording() {
        guard isRecording else { return }
        engineClient?.stop()
        engineClient = nil
        recordingTask?.cancel()
        recordingTask = nil
        surfaceTracker.stopTracking()
        stopDisplayTimer()
        flushPending()
        isRecording = false
        liveDuration = events.last?.time ?? 0
    }

    private func flushPending() {
        let snapshot = eventBuffer.drainPending()
        
        if activeSurfaces != snapshot.surfaces {
            activeSurfaces = snapshot.surfaces
        }
        guard !snapshot.events.isEmpty else { return }
        
        liveStats.merge(RecordingStats.summarize(snapshot.events))
        events.append(contentsOf: snapshot.events)
        appendLiveWaveformEvents(snapshot.events)
    }
    
    public func clearAll() {
        events.removeAll()
        liveWaveformEvents.removeAll()

        recalculateStats()
    }

    public func recalculateStats() {
        liveStats = RecordingStats.summarize(events)
    }

    private func appendLiveWaveformEvents(_ newEvents: [RecordedEvent]) {
        if newEvents.count >= maxLiveWaveformEvents {
            liveWaveformEvents = Self.cappedWaveformEvents(newEvents, maxCount: maxLiveWaveformEvents)
            return
        }

        liveWaveformEvents.append(contentsOf: newEvents)
        let overflow = liveWaveformEvents.count - maxLiveWaveformEvents
        if overflow > 0 {
            liveWaveformEvents.removeFirst(overflow)
        }
    }

    private static func cappedWaveformEvents(_ events: [RecordedEvent], maxCount: Int) -> [RecordedEvent] {
        guard events.count > maxCount else { return events }
        return Array(events.suffix(maxCount))
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: displayTimerTarget,
            selector: #selector(RecorderDisplayTimerTarget.tick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    fileprivate func displayTimerDidFire() {
        if isRecording {
            flushPending()
            liveDuration = RecordingTimeline.liveDuration(
                currentMachTicks: mach_absolute_time(),
                baseMachTicks: baseMachTicks,
                resumeOffsetDuration: resumeOffsetDuration,
                timebase: Recorder.recordingTimebase
            )
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func processRawEvent(type: CGEventType, event: CGEvent) {
        guard let kind = RecordedEvent.Kind(rawValue: Int(type.rawValue)) else { return }

        if kind == .mouseMoved && !recordMouseMovesEnabled {
            return
        }
        
        let loc = event.location
        let eventTimestamp = UInt64(event.timestamp)
        let eventTime = RecordingTimeline.eventTime(
            timestamp: eventTimestamp,
            baseTimestamp: baseEventTimestamp,
            resumeOffsetDuration: resumeOffsetDuration
        )
        baseEventTimestamp = eventTime.baseTimestamp
        let elapsed = eventTime.elapsed
        
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
        
        var registry = eventBuffer.trackingState()
        
        let targetId = registry.update(
            eventKind: kind,
            trackedActiveSurface: surfaceTracker.cachedActiveSurface,
            surfaceMatcher: surfaceMatcher
        )

        let coordinateBinding = RecordingCoordinateBinder.bind(
            location: loc,
            targetSurfaceId: targetId,
            surfaces: registry.activeSurfaces
        )
        if let updatedSurface = coordinateBinding.updatedSurface, let targetId {
            registry.activeSurfaces[targetId] = updatedSurface
        }
        let coordinateFields = coordinateBinding.fields

        var unicodeStr: String? = nil
        if kind.isKey {
            var chars = [UniChar](repeating: 0, count: 4)
            var actualStringLength = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualStringLength, unicodeString: &chars)
            if actualStringLength > 0 {
                unicodeStr = String(utf16CodeUnits: chars, count: actualStringLength)
            }
        }
        
        let scrollResult = makeScrollResult(for: kind, event: event)

        let recorded = RecordedEvent(
            kind: kind,
            time: elapsed,
            x: loc.x,
            y: loc.y,
            keyCode: keyCode,
            flags: event.flags.rawValue,
            mouseButton: event.getIntegerValueField(.mouseEventButtonNumber),
            clickCount: event.getIntegerValueField(.mouseEventClickState),
            scrollDeltaY: scrollResult?.playbackDeltaY ?? 0,
            scrollDeltaX: scrollResult?.playbackDeltaX ?? 0,
            windowLocalX: coordinateFields.windowLocalX, windowLocalY: coordinateFields.windowLocalY,
            windowNormalizedX: coordinateFields.windowNormalizedX, windowNormalizedY: coordinateFields.windowNormalizedY,
            contentLocalX: coordinateFields.contentLocalX, contentLocalY: coordinateFields.contentLocalY,
            contentNormalizedX: coordinateFields.contentNormalizedX, contentNormalizedY: coordinateFields.contentNormalizedY,
            coordinateBinding: coordinateFields.coordinateBinding, coordinateStrategy: nil,
            surfaceId: targetId,
            scrollPayload: scrollResult?.payload,
            unicodeString: unicodeStr
        )

        // Display timer will flush from pending into events
        eventBuffer.store(
            registry: registry,
            event: recorded
        )
    }

    private func makeScrollResult(for kind: RecordedEvent.Kind, event: CGEvent) -> RecordingScrollResult? {
        guard kind == .scrollWheel else { return nil }
        return RecordingScrollPayloadBuilder.build(
            from: RecordingScrollSample(
                pointDeltaX: Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                pointDeltaY: Int32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                lineDeltaX: Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                lineDeltaY: Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
                fixedRawX: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2),
                fixedRawY: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            )
        )
    }
}

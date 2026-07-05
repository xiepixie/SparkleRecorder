import Cocoa
import CoreGraphics
import Combine
import SparkleRecorderCore

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
    private let makeRecordingEngine: @Sendable (CGEventMask) -> RecordingEngineClient
    private var baseMachTicks: UInt64 = 0
    private var isResumedSession = false
    private var resumeOffsetDuration: Double = 0
    private let surfaceTracker = RecordingSurfaceTracker()
    private var contentFrameCache: [String: CGRect] = [:]
    private let sessionProcessor = RecordingSessionProcessor()
    private var recordMouseMovesEnabled = false
    private lazy var displayTimerTarget = RecorderDisplayTimerTarget(recorder: self)
    
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

    init(
        makeRecordingEngine: @escaping @Sendable (CGEventMask) -> RecordingEngineClient = { mask in
            RecordingEngineClient.live(mask: mask)
        }
    ) {
        self.makeRecordingEngine = makeRecordingEngine
    }

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
        liveDuration = 0
        recalculateStats()
        baseMachTicks = mach_absolute_time()
        isResumedSession = false
        resumeOffsetDuration = 0
        recordMouseMovesEnabled = UserDefaults.standard.bool(forKey: "recordMouseMoves")
        sessionProcessor.reset(
            recordMouseMoves: recordMouseMovesEnabled,
            ignoredKeyCodes: ignoredKeyCodes,
            resumeOffsetDuration: resumeOffsetDuration
        )
        
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

        let client = makeRecordingEngine(mask)
        let stream = client.events()
        guard client.start() else {
            client.stop()
            surfaceTracker.stopTracking()
            sessionProcessor.reset(
                recordMouseMoves: recordMouseMovesEnabled,
                ignoredKeyCodes: ignoredKeyCodes,
                resumeOffsetDuration: resumeOffsetDuration
            )
            return false
        }
        
        recordingTask = Task { [weak self] in
            for await input in stream {
                self?.processRawInput(input)
            }
        }

        self.engineClient = client
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
        let snapshot = sessionProcessor.drainPending()
        
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

    private func processRawInput(_ input: RawInputEvent) {
        sessionProcessor.record(
            input,
            recordMouseMoves: recordMouseMovesEnabled,
            ignoredKeyCodes: ignoredKeyCodes,
            trackedActiveSurface: surfaceTracker.cachedActiveSurface
        )
    }
}

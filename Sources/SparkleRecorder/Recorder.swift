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
    @Published public private(set) var semanticRecordingStatus: SemanticRecorderBridgeStatus = .idle

    private var engineClient: RecordingEngineClient?
    private var recordingTask: Task<Void, Never>?
    private var recordingDiagnosticTask: Task<Void, Never>?
    private let makeRecordingEngine: @Sendable (CGEventMask) -> RecordingEngineClient
    private let makeSemanticRecorderBridge: @Sendable (RecordingCaptureTarget) -> SemanticRecorderBridge
    private let semanticSuppressionContextClient: SemanticRecordingSuppressionContextClient
    private let semanticSuppressionProducer: SemanticRecordingSuppressionProducer
    private var semanticRecorderBridge: SemanticRecorderBridge?
    private var semanticRecordingTask: Task<Void, Never>?
    private var semanticCaptureTarget: RecordingCaptureTarget?
    private var lastSemanticSuppressionFingerprint: SemanticSuppressionFingerprint?
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
        },
        makeSemanticRecorderBridge: @escaping @Sendable (RecordingCaptureTarget) -> SemanticRecorderBridge = { target in
            SemanticRecorderBridge(
                configuration: SemanticRecordingCaptureConfiguration(
                    captureTarget: target
                )
            )
        },
        semanticSuppressionContextClient: SemanticRecordingSuppressionContextClient = .live,
        semanticSuppressionProducer: SemanticRecordingSuppressionProducer = .liveUserDefaults
    ) {
        self.makeRecordingEngine = makeRecordingEngine
        self.makeSemanticRecorderBridge = makeSemanticRecorderBridge
        self.semanticSuppressionContextClient = semanticSuppressionContextClient
        self.semanticSuppressionProducer = semanticSuppressionProducer
    }

    deinit {
        engineClient?.stop()
        recordingTask?.cancel()
        recordingDiagnosticTask?.cancel()
        semanticRecordingTask?.cancel()
        if let semanticRecorderBridge {
            Task {
                await semanticRecorderBridge.cancel(recordingTime: 0)
            }
        }
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
    func startRecording(
        semanticRecordingEnabled: Bool = UserDefaults.standard.bool(forKey: "semanticRecordingEnabled"),
        semanticCaptureTarget: RecordingCaptureTarget = RecordingCaptureTarget()
    ) -> Bool {
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
        let diagnosticStream = client.diagnostics()
        recordingDiagnosticTask = Task { [weak self] in
            for await diagnostic in diagnosticStream {
                self?.processRecordingDiagnostic(diagnostic)
            }
        }

        self.engineClient = client
        isRecording = true
        startSemanticRecordingIfEnabled(
            semanticRecordingEnabled,
            captureTarget: semanticCaptureTarget
        )
        startDisplayTimer()
        return true
    }

    func stopRecording() {
        stopRecording(shouldFinishSemanticRecording: true)
    }

    func cancelRecording() {
        stopRecording(shouldFinishSemanticRecording: false)
    }

    private func stopRecording(shouldFinishSemanticRecording: Bool) {
        guard isRecording else { return }
        engineClient?.stop()
        engineClient = nil
        recordingTask?.cancel()
        recordingTask = nil
        recordingDiagnosticTask?.cancel()
        recordingDiagnosticTask = nil
        surfaceTracker.stopTracking()
        stopDisplayTimer()
        flushPending()
        isRecording = false
        liveDuration = events.last?.time ?? 0
        if shouldFinishSemanticRecording {
            finishSemanticRecording(recordingTime: liveDuration)
        } else {
            cancelSemanticRecording(recordingTime: liveDuration)
        }
    }

    private func flushPending() {
        let snapshot = sessionProcessor.drainPending()
        
        if activeSurfaces != snapshot.surfaces {
            activeSurfaces = snapshot.surfaces
        }
        let semanticRecordingTime = snapshot.events.last?.time ?? liveDuration
        recordSemanticSuppressionContext(recordingTime: semanticRecordingTime)
        guard !snapshot.events.isEmpty else { return }
        
        liveStats.merge(RecordingStats.summarize(snapshot.events))
        events.append(contentsOf: snapshot.events)
        appendLiveWaveformEvents(snapshot.events)
        recordSemanticEvents(snapshot.events)
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

    private func processRecordingDiagnostic(
        _ diagnostic: RecordingEngineDiagnostic
    ) {
        switch diagnostic.kind {
        case .eventTapDisabledByUserInput:
            recordSecureInputSuppressionContext(createdAt: diagnostic.createdAt)
        }
    }

    private func startSemanticRecordingIfEnabled(
        _ semanticRecordingEnabled: Bool,
        captureTarget: RecordingCaptureTarget
    ) {
        semanticRecordingTask?.cancel()
        semanticRecorderBridge = nil
        semanticCaptureTarget = nil
        lastSemanticSuppressionFingerprint = nil
        semanticRecordingStatus = .idle

        guard semanticRecordingEnabled else {
            return
        }

        let initialContext = semanticSuppressionContextClient.context(
            captureTarget,
            0
        )
        let initialDecision = semanticSuppressionProducer.captureSuppressionDecision(
            for: initialContext
        )
        guard !initialDecision.shouldSuppressCapture else {
            semanticRecordingStatus = .suppressed(
                message: semanticCaptureSuppressionMessage(
                    reasons: initialDecision.reasons
                )
            )
            return
        }

        let bridge = makeSemanticRecorderBridge(captureTarget)
        semanticRecorderBridge = bridge
        semanticCaptureTarget = captureTarget
        semanticRecordingStatus = .starting
        semanticRecordingTask = Task { [weak self, bridge] in
            let status = await bridge.start(recordingTime: 0)
            await self?.setSemanticRecordingStatus(status)
        }
        recordSemanticSuppressionContext(initialContext)
    }

    private func recordSemanticEvents(_ events: [RecordedEvent]) {
        guard let bridge = semanticRecorderBridge else {
            return
        }
        Task { [weak self, bridge, events] in
            let status = await bridge.record(events)
            await self?.setSemanticRecordingStatus(status)
        }
    }

    private func finishSemanticRecording(recordingTime: TimeInterval) {
        guard let bridge = semanticRecorderBridge else {
            return
        }
        semanticRecorderBridge = nil
        semanticCaptureTarget = nil
        lastSemanticSuppressionFingerprint = nil
        semanticRecordingTask = Task { [weak self, bridge] in
            let status = await bridge.finish(recordingTime: recordingTime)
            await self?.setSemanticRecordingStatus(status)
        }
    }

    private func cancelSemanticRecording(recordingTime: TimeInterval) {
        guard let bridge = semanticRecorderBridge else {
            return
        }
        semanticRecorderBridge = nil
        semanticCaptureTarget = nil
        lastSemanticSuppressionFingerprint = nil
        semanticRecordingTask = Task { [weak self, bridge] in
            let status = await bridge.cancel(recordingTime: recordingTime)
            await self?.setSemanticRecordingStatus(status)
        }
    }

    private func recordSemanticSuppressionContext(recordingTime: TimeInterval) {
        guard let semanticCaptureTarget else {
            return
        }
        let context = semanticSuppressionContextClient.context(
            semanticCaptureTarget,
            max(0, recordingTime)
        )
        recordSemanticSuppressionContext(context)
    }

    private func recordSemanticSuppressionContext(
        _ context: SemanticRecordingSuppressionContext
    ) {
        guard let bridge = semanticRecorderBridge else {
            return
        }
        let fingerprint = SemanticSuppressionFingerprint(context: context)
        guard fingerprint != lastSemanticSuppressionFingerprint else {
            return
        }
        lastSemanticSuppressionFingerprint = fingerprint

        let decision = semanticSuppressionProducer.captureSuppressionDecision(
            for: context
        )
        if decision.shouldSuppressCapture {
            suppressSemanticRecording(
                bridge: bridge,
                context: context,
                decision: decision
            )
            return
        }

        Task { [weak self, bridge, context] in
            let status = await bridge.addSuppressions(for: context)
            await self?.setSemanticRecordingStatus(status)
        }
    }

    private func recordSecureInputSuppressionContext(createdAt: Date) {
        guard semanticRecorderBridge != nil,
              let semanticCaptureTarget else {
            return
        }
        let context = SemanticRecordingSuppressionContext(
            recordingTime: max(0, liveDuration),
            target: semanticCaptureTarget,
            secureInputEnabled: true,
            createdAt: createdAt
        )
        recordSemanticSuppressionContext(context)
    }

    private func suppressSemanticRecording(
        bridge: SemanticRecorderBridge,
        context: SemanticRecordingSuppressionContext,
        decision: SemanticRecordingCaptureSuppressionDecision
    ) {
        let message = semanticCaptureSuppressionMessage(
            reasons: decision.reasons
        )
        let recordingTime = max(0, context.recordingTime ?? liveDuration)
        semanticRecorderBridge = nil
        semanticCaptureTarget = nil
        lastSemanticSuppressionFingerprint = nil
        semanticRecordingStatus = .suppressed(message: message)
        semanticRecordingTask?.cancel()
        semanticRecordingTask = Task { [weak self, bridge, recordingTime, message] in
            let status = await bridge.suppress(
                recordingTime: recordingTime,
                message: message
            )
            await self?.setSemanticRecordingStatus(status)
        }
    }

    private func semanticCaptureSuppressionMessage(
        reasons: [RecordingSuppressionReason]
    ) -> String {
        let labels = reasons.map(Self.semanticCaptureSuppressionLabel)
        guard !labels.isEmpty else {
            return "Sensitive context detected."
        }
        return "\(labels.prefix(2).joined(separator: ", ")) detected."
    }

    private static func semanticCaptureSuppressionLabel(
        _ reason: RecordingSuppressionReason
    ) -> String {
        switch reason {
        case .secureInput:
            return "Secure Input"
        case .passwordField:
            return "password field"
        case .excludedApplication:
            return "excluded app"
        case .excludedWindow:
            return "excluded window"
        case .excludedDomain:
            return "excluded domain"
        case .privateRegion:
            return "private region"
        case .oversizedArtifact:
            return "oversized artifact"
        case .userDeleted:
            return "deleted artifact"
        case .unknown:
            return "sensitive context"
        }
    }

    @MainActor
    private func setSemanticRecordingStatus(
        _ status: SemanticRecorderBridgeStatus
    ) {
        if case .suppressed = semanticRecordingStatus,
           case .suppressed = status {
            semanticRecordingStatus = status
            return
        }
        if case .suppressed = semanticRecordingStatus {
            return
        }
        semanticRecordingStatus = status
    }
}

private struct SemanticSuppressionFingerprint: Equatable {
    var applicationBundleID: String?
    var windowTitle: String?
    var domain: String?
    var secureInputEnabled: Bool
    var passwordFieldFocused: Bool
    var privateRegion: Bool
    var artifactByteCount: Int?

    init(context: SemanticRecordingSuppressionContext) {
        applicationBundleID = context.target.appBundleIdentifier?.lowercased()
        windowTitle = context.target.windowTitle?.lowercased()
        domain = context.domain?.lowercased()
        secureInputEnabled = context.secureInputEnabled
        passwordFieldFocused = context.passwordFieldFocused
        privateRegion = context.privateRegion
        artifactByteCount = context.artifactByteCount
    }
}

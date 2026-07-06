import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Lifecycle Tests")
struct SemanticRecordingLifecycleTests {
    @Test("Blocking preflight does not create a capture session")
    func blockingPreflightDoesNotCreateCaptureSession() async throws {
        let permissions = MutablePermissionSource(snapshot: SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .authorized,
            screenRecording: .denied
        ))
        let factory = LifecycleSessionFactorySpy()
        let lifecycle = SemanticRecordingLifecycle(
            preflightClient: permissions.client,
            sessionFactory: factory.factory
        )

        let start = try await lifecycle.start()

        switch start {
        case .blocked(let preflight):
            #expect(!preflight.isReadyToStart)
            #expect(preflight.blockingIssues.map(\.permission) == [.screenRecording, .screenRecording])
        case .started:
            Issue.record("Missing Screen Recording should block semantic capture startup")
        }
        #expect(factory.makeCount == 0)

        do {
            try await lifecycle.record(recordedEvent(.leftMouseUp, time: 0.4), index: 0)
            Issue.record("Recording after a blocked start should throw")
        } catch SemanticRecordingLifecycleError.startBlocked(let blocked) {
            #expect(blocked == start.preflight)
        } catch {
            Issue.record("Unexpected lifecycle error: \(error)")
        }
    }

    @Test("Degraded accessibility still starts capture and returns preflight")
    func degradedAccessibilityStillStartsCaptureAndReturnsPreflight() async throws {
        let permissions = MutablePermissionSource(snapshot: SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .denied,
            screenRecording: .authorized
        ))
        let captureSpy = LifecycleCaptureSpy()
        let factory = LifecycleSessionFactorySpy(captureSpy: captureSpy)
        let lifecycle = SemanticRecordingLifecycle(
            preflightClient: permissions.client,
            sessionFactory: factory.factory
        )

        let start = try await lifecycle.start(recordingTime: 0.25)

        switch start {
        case .started(let preflight):
            #expect(preflight.isReadyToStart)
            #expect(preflight.isDegraded)
            #expect(preflight.degradedIssues.map(\.permission) == [.accessibility])
            #expect(preflight.hasCapability(.movieRecording))
            #expect(preflight.hasCapability(.keyframeCapture))
            #expect(!preflight.hasCapability(.accessibilitySnapshots))
        case .blocked:
            Issue.record("Missing Accessibility should degrade, not block, semantic capture")
        }
        #expect(factory.makeCount == 1)
        #expect(await captureSpy.operations == [
            "startMovie:video/recording.mov",
            "captureFrame:recordingStart"
        ])
    }

    @Test("Lifecycle records events and finishes bundle after authorized preflight")
    func lifecycleRecordsEventsAndFinishesBundleAfterAuthorizedPreflight() async throws {
        let captureSpy = LifecycleCaptureSpy()
        let factory = LifecycleSessionFactorySpy(captureSpy: captureSpy)
        let lifecycle = SemanticRecordingLifecycle(
            configuration: SemanticRecordingLifecycleConfiguration(
                captureConfiguration: SemanticRecordingCaptureConfiguration(
                    captureTarget: RecordingCaptureTarget(
                        kind: .window,
                        surfaceID: "checkout-window",
                        windowID: 42,
                        appBundleIdentifier: "com.example.Checkout",
                        windowTitle: "Checkout"
                    ),
                    defaultSurfaceID: "checkout-window"
                )
            ),
            preflightClient: SemanticRecordingPreflightClient.fixed(.allAuthorizedForLifecycle),
            sessionFactory: factory.factory
        )

        let start = try await lifecycle.start()
        try await lifecycle.record(
            recordedEvent(.leftMouseUp, time: 0.75, surfaceID: "checkout-window"),
            index: 0
        )
        let bundle = try await lifecycle.finish(recordingTime: 1.4)

        switch start {
        case .started(let preflight):
            #expect(preflight.isReadyToStart)
            #expect(!preflight.isDegraded)
        case .blocked:
            Issue.record("Authorized permissions should start semantic capture")
        }
        #expect(bundle.validate().isEmpty)
        #expect(bundle.videoSegments.count == 1)
        #expect(bundle.frames.map(\.source) == [.recordingStart, .mouseUp, .recordingStop])
        #expect(bundle.timelineEvents.map(\.recordedEventIndex) == [0])
        #expect(bundle.aiSafeEvents.map(\.kind) == [.click])
        #expect(await captureSpy.operations == [
            "startMovie:video/recording.mov",
            "captureFrame:recordingStart",
            "captureFrame:mouseUp",
            "captureFrame:recordingStop",
            "finishMovie:video/recording.mov"
        ])
    }

    @Test("Lifecycle cancel stops capture without stop keyframe")
    func lifecycleCancelStopsCaptureWithoutStopKeyframe() async throws {
        let captureSpy = LifecycleCaptureSpy()
        let factory = LifecycleSessionFactorySpy(captureSpy: captureSpy)
        let lifecycle = SemanticRecordingLifecycle(
            preflightClient: SemanticRecordingPreflightClient.fixed(.allAuthorizedForLifecycle),
            sessionFactory: factory.factory
        )

        _ = try await lifecycle.start(recordingTime: 0.1)
        await lifecycle.cancel(recordingTime: 0.9)

        #expect(await captureSpy.operations == [
            "startMovie:video/recording.mov",
            "captureFrame:recordingStart",
            "finishMovie:video/recording.mov"
        ])
        await #expect(throws: SemanticRecordingLifecycleError.alreadyFinished) {
            try await lifecycle.record(recordedEvent(.leftMouseUp, time: 1.0), index: 0)
        }
    }

    @Test("Blocked start can be retried after permissions change")
    func blockedStartCanBeRetriedAfterPermissionsChange() async throws {
        let permissions = MutablePermissionSource(snapshot: SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .authorized,
            screenRecording: .denied
        ))
        let factory = LifecycleSessionFactorySpy()
        let lifecycle = SemanticRecordingLifecycle(
            preflightClient: permissions.client,
            sessionFactory: factory.factory
        )

        let blocked = try await lifecycle.start()
        permissions.update(.allAuthorizedForLifecycle)
        let started = try await lifecycle.start()

        switch blocked {
        case .blocked(let preflight):
            #expect(!preflight.isReadyToStart)
        case .started:
            Issue.record("First start should be blocked")
        }
        switch started {
        case .started(let preflight):
            #expect(preflight.isReadyToStart)
        case .blocked:
            Issue.record("Second start should succeed after permissions are authorized")
        }
        #expect(factory.makeCount == 1)
    }

    private func recordedEvent(
        _ kind: RecordedEvent.Kind,
        time: TimeInterval,
        surfaceID: String? = nil
    ) -> RecordedEvent {
        RecordedEvent(
            kind: kind,
            time: time,
            x: 42,
            y: 84,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 1,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            surfaceId: surfaceID
        )
    }
}

private final class MutablePermissionSource: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: SemanticRecordingPermissionSnapshot

    init(snapshot: SemanticRecordingPermissionSnapshot) {
        self.snapshot = snapshot
    }

    var client: SemanticRecordingPreflightClient {
        SemanticRecordingPreflightClient { [self] in
            currentSnapshot()
        }
    }

    func update(_ snapshot: SemanticRecordingPermissionSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
    }

    private func currentSnapshot() -> SemanticRecordingPermissionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

private final class LifecycleSessionFactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let captureSpy: LifecycleCaptureSpy

    init(captureSpy: LifecycleCaptureSpy = LifecycleCaptureSpy()) {
        self.captureSpy = captureSpy
    }

    var makeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var factory: SemanticRecordingCaptureSessionFactory {
        SemanticRecordingCaptureSessionFactory { [self] configuration in
            lock.lock()
            count += 1
            lock.unlock()

            return SemanticRecordingCaptureSession(
                configuration: configuration,
                client: Self.client(spy: captureSpy)
            )
        }
    }

    private static func client(spy: LifecycleCaptureSpy) -> SemanticRecordingCaptureClient {
        SemanticRecordingCaptureClient(
            startMovie: { request in
                await spy.append("startMovie:\(request.artifactRef.path)")
                return SemanticRecordingMovieHandle(
                    segmentID: request.segmentID,
                    artifactRef: request.artifactRef,
                    target: request.target,
                    startTime: request.recordingTime,
                    frameSize: RecordingImageSize(width: 1_440, height: 900)
                )
            },
            finishMovie: { request in
                await spy.append("finishMovie:\(request.handle.artifactRef.path)")
                return SemanticRecordingMovieFinishResult(
                    duration: request.recordingTime,
                    frameSize: RecordingImageSize(width: 1_440, height: 900)
                )
            },
            captureFrame: { request in
                await spy.append("captureFrame:\(request.source.rawValue)")
                return SemanticRecordingCapturedFrame(
                    imageSize: RecordingImageSize(width: 1_440, height: 900),
                    displayScale: 2
                )
            }
        )
    }
}

private actor LifecycleCaptureSpy {
    private(set) var operations: [String] = []

    func append(_ operation: String) {
        operations.append(operation)
    }
}

private extension SemanticRecordingPermissionSnapshot {
    static let allAuthorizedForLifecycle = SemanticRecordingPermissionSnapshot(
        inputMonitoring: .authorized,
        accessibility: .authorized,
        screenRecording: .authorized
    )
}

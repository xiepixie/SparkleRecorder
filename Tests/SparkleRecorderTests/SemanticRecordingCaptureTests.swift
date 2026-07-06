import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Capture Tests")
struct SemanticRecordingCaptureTests {
    @Test("Capture session builds video segment and event-aligned keyframes")
    func captureSessionBuildsVideoSegmentAndEventAlignedKeyframes() async throws {
        let recordingID = uuid("75000000-0000-0000-0000-000000000001")
        let segmentID = uuid("75000000-0000-0000-0000-000000000002")
        let frameIDs = [
            uuid("75000000-0000-0000-0000-000000000003"),
            uuid("75000000-0000-0000-0000-000000000004"),
            uuid("75000000-0000-0000-0000-000000000005"),
            uuid("75000000-0000-0000-0000-000000000006")
        ]
        let eventIDs = [
            uuid("75000000-0000-0000-0000-000000000007"),
            uuid("75000000-0000-0000-0000-000000000008")
        ]
        let semanticID = uuid("75000000-0000-0000-0000-000000000009")
        let ids = CaptureIDFixture(values: [
            .videoSegment: [segmentID],
            .frame: frameIDs,
            .timelineEvent: eventIDs,
            .semanticEvent: [semanticID]
        ])
        let spy = CaptureClientSpy()
        let client = SemanticRecordingCaptureClient(
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
                await spy.append("captureFrame:\(request.source.rawValue):\(request.artifactRef.path)")
                return SemanticRecordingCapturedFrame(
                    imageSize: RecordingImageSize(width: 1_440, height: 900),
                    displayScale: 2
                )
            }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(
                recordingID: recordingID,
                createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                captureTarget: RecordingCaptureTarget(
                    kind: .window,
                    surfaceID: "checkout-window",
                    windowID: 42,
                    appBundleIdentifier: "com.example.Checkout",
                    windowTitle: "Checkout"
                ),
                defaultSurfaceID: "checkout-window"
            ),
            client: client,
            ids: ids.provider
        )

        try await session.start()
        try await session.record(
            recordedEvent(.leftMouseDown, time: 2.1, surfaceID: "checkout-window"),
            index: 0
        )
        try await session.record(
            recordedEvent(.leftMouseUp, time: 2.45, surfaceID: "checkout-window"),
            index: 1
        )
        let bundle = try await session.finish(recordingTime: 3.4)

        #expect(bundle.validate().isEmpty)
        #expect(bundle.id == recordingID)
        #expect(bundle.videoSegments.map(\.id) == [segmentID])
        #expect(bundle.videoSegments.first?.artifactRef.path == "video/recording.mov")
        #expect(bundle.videoSegments.first?.duration == 3.4)
        #expect(bundle.frames.map(\.id) == frameIDs)
        #expect(bundle.frames.map(\.source) == [.recordingStart, .mouseDown, .mouseUp, .recordingStop])
        #expect(bundle.frames.allSatisfy { $0.videoSegmentID == segmentID })
        #expect(bundle.frames.map(\.imageRef.path) == [
            "frames/000001-recordingStart.png",
            "frames/000002-mouseDown.png",
            "frames/000003-mouseUp.png",
            "frames/000004-recordingStop.png"
        ])
        #expect(bundle.timelineEvents.map(\.id) == eventIDs)
        #expect(bundle.timelineEvents.map(\.recordedEventIndex) == [0, 1])
        #expect(bundle.timelineEvents[1].frameID == frameIDs[2])
        #expect(bundle.aiSafeEvents.map(\.id) == [semanticID])
        #expect(bundle.aiSafeEvents.first?.kind == .click)
        #expect(bundle.aiSafeEvents.first?.evidenceFrameIDs == [frameIDs[2]])

        let operations = await spy.operations
        #expect(operations == [
            "startMovie:video/recording.mov",
            "captureFrame:recordingStart:frames/000001-recordingStart.png",
            "captureFrame:mouseDown:frames/000002-mouseDown.png",
            "captureFrame:mouseUp:frames/000003-mouseUp.png",
            "captureFrame:recordingStop:frames/000004-recordingStop.png",
            "finishMovie:video/recording.mov"
        ])
    }

    @Test("Keyframe-only capture does not start a movie")
    func keyframeOnlyCaptureDoesNotStartMovie() async throws {
        let ids = CaptureIDFixture(values: [
            .frame: [
                uuid("76000000-0000-0000-0000-000000000001"),
                uuid("76000000-0000-0000-0000-000000000002")
            ]
        ])
        let spy = CaptureClientSpy()
        let client = SemanticRecordingCaptureClient(
            startMovie: { _ in
                Issue.record("Keyframe-only mode should not start movie capture")
                throw SemanticRecordingCaptureError.alreadyStarted
            },
            finishMovie: { _ in
                Issue.record("Keyframe-only mode should not finish movie capture")
                throw SemanticRecordingCaptureError.alreadyFinished
            },
            captureFrame: { request in
                await spy.append("captureFrame:\(request.source.rawValue)")
                return SemanticRecordingCapturedFrame(imageSize: RecordingImageSize(width: 800, height: 600))
            }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(
                capturePolicy: RecordingCapturePolicy(mode: .keyframesOnly)
            ),
            client: client,
            ids: ids.provider
        )

        try await session.start()
        let bundle = try await session.finish(recordingTime: 1.2)

        #expect(bundle.validate().isEmpty)
        #expect(bundle.capturePolicy.mode == .keyframesOnly)
        #expect(bundle.videoSegments.isEmpty)
        #expect(bundle.frames.count == 2)
        #expect(bundle.frames.allSatisfy { $0.videoSegmentID == nil && $0.videoTime == nil })
        #expect(await spy.operations == [
            "captureFrame:recordingStart",
            "captureFrame:recordingStop"
        ])
    }

    @Test("Frame index observations are attached to the bundle")
    func frameIndexObservationsAreAttachedToBundle() async throws {
        let recordingID = uuid("77000000-0000-0000-0000-000000000001")
        let textFrameID = uuid("77000000-0000-0000-0000-000000000003")
        let observationID = uuid("77000000-0000-0000-0000-000000000004")
        let ids = CaptureIDFixture(values: [
            .frame: [
                uuid("77000000-0000-0000-0000-000000000002"),
                textFrameID,
                uuid("77000000-0000-0000-0000-000000000005")
            ],
            .timelineEvent: [uuid("77000000-0000-0000-0000-000000000006")],
            .semanticEvent: [uuid("77000000-0000-0000-0000-000000000007")]
        ])
        let client = SemanticRecordingCaptureClient(
            startMovie: { request in
                SemanticRecordingMovieHandle(
                    segmentID: request.segmentID,
                    artifactRef: request.artifactRef,
                    target: request.target,
                    startTime: 0
                )
            },
            finishMovie: { request in
                SemanticRecordingMovieFinishResult(duration: request.recordingTime)
            },
            captureFrame: { _ in
                SemanticRecordingCapturedFrame(imageSize: RecordingImageSize(width: 800, height: 600))
            },
            indexFrame: { request in
                guard request.frame.source == .textInput else {
                    return []
                }
                return [
                    RecordingVisualObservation(
                        id: observationID,
                        kind: .ocrText,
                        recordingTime: request.frame.recordingTime,
                        frameID: request.frame.id,
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 20, y: 40, width: 180, height: 30),
                            coordinateSpace: .windowPixels
                        ),
                        text: "Order confirmed",
                        confidence: 0.96,
                        provider: "Vision.fake",
                        providerVersion: "0.1",
                        createdAt: request.createdAt
                    )
                ]
            }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(recordingID: recordingID),
            client: client,
            ids: ids.provider
        )

        try await session.start()
        try await session.record(
            recordedEvent(.keyDown, time: 0.4, unicodeString: "O"),
            index: 0
        )
        let bundle = try await session.finish(recordingTime: 0.8)

        #expect(bundle.validate().isEmpty)
        #expect(bundle.visualObservations.map(\.id) == [observationID])
        #expect(bundle.visualObservations.first?.frameID == textFrameID)
        #expect(bundle.visualObservations.first?.text == "Order confirmed")
        #expect(bundle.observations(frameID: textFrameID).map(\.id) == [observationID])
    }

    @Test("Capture session enforces lifecycle ordering")
    func captureSessionEnforcesLifecycleOrdering() async throws {
        let client = SemanticRecordingCaptureClient(
            startMovie: { request in
                SemanticRecordingMovieHandle(
                    segmentID: request.segmentID,
                    artifactRef: request.artifactRef,
                    target: request.target,
                    startTime: 0
                )
            },
            finishMovie: { request in
                SemanticRecordingMovieFinishResult(duration: request.recordingTime)
            },
            captureFrame: { _ in SemanticRecordingCapturedFrame() }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(),
            client: client
        )

        await #expect(throws: SemanticRecordingCaptureError.notStarted) {
            try await session.record(recordedEvent(.leftMouseUp, time: 0.2), index: 0)
        }
        try await session.start()
        await #expect(throws: SemanticRecordingCaptureError.alreadyStarted) {
            try await session.start()
        }
        _ = try await session.finish(recordingTime: 1.0)
        await #expect(throws: SemanticRecordingCaptureError.alreadyFinished) {
            try await session.record(recordedEvent(.leftMouseUp, time: 1.1), index: 1)
        }
        await #expect(throws: SemanticRecordingCaptureError.alreadyFinished) {
            _ = try await session.finish(recordingTime: 1.2)
        }
    }

    private func recordedEvent(
        _ kind: RecordedEvent.Kind,
        time: TimeInterval,
        surfaceID: String? = nil,
        unicodeString: String? = nil
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
            surfaceId: surfaceID,
            unicodeString: unicodeString
        )
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return uuid
    }
}

private actor CaptureClientSpy {
    private(set) var operations: [String] = []

    func append(_ operation: String) {
        operations.append(operation)
    }
}

private final class CaptureIDFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SemanticRecordingCaptureIDKind: [UUID]]
    private var counters: [SemanticRecordingCaptureIDKind: Int] = [:]

    init(values: [SemanticRecordingCaptureIDKind: [UUID]]) {
        self.values = values
    }

    var provider: SemanticRecordingCaptureIDProvider {
        SemanticRecordingCaptureIDProvider { [self] kind in
            lock.lock()
            defer { lock.unlock() }

            let index = counters[kind, default: 0]
            counters[kind] = index + 1
            if let ids = values[kind], ids.indices.contains(index) {
                return ids[index]
            }
            let fallback = String(format: "79000000-0000-0000-0000-%012d", index + 1)
            return UUID(uuidString: fallback) ?? UUID()
        }
    }
}

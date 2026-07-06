import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Capture Tests")
struct SemanticRecordingCaptureTests {
    @Test("Capture target mapper prefers window identity from playback surface")
    func captureTargetMapperPrefersWindowIdentityFromPlaybackSurface() {
        let surface = PlaybackSurface(
            appName: "Checkout",
            bundleIdentifier: "com.example.checkout",
            windowTitle: "Checkout - Order 42",
            recordedDisplayId: 7,
            recordedWindowId: 42,
            recordedFrame: RectValue(x: 10, y: 20, width: 800, height: 600)
        )

        let target = SemanticRecordingCaptureTargetMapper.target(
            surface: surface,
            surfaceID: "checkout-window"
        )

        #expect(target.kind == .window)
        #expect(target.surfaceID == "checkout-window")
        #expect(target.displayID == 7)
        #expect(target.windowID == 42)
        #expect(target.appBundleIdentifier == "com.example.checkout")
        #expect(target.appName == "Checkout")
        #expect(target.windowTitle == "Checkout - Order 42")
    }

    @Test("Capture target mapper falls back to display without surface")
    func captureTargetMapperFallsBackToDisplayWithoutSurface() {
        let target = SemanticRecordingCaptureTargetMapper.target(
            surface: nil,
            fallbackDisplayID: 99
        )

        #expect(target.kind == .display)
        #expect(target.surfaceID == "surface-1")
        #expect(target.displayID == 99)
        #expect(target.windowID == nil)
        #expect(target.appBundleIdentifier == nil)
        #expect(target.windowTitle == nil)
    }

    @Test("Cancel stops movie without writing a stop keyframe")
    func cancelStopsMovieWithoutWritingStopKeyframe() async throws {
        let recordingID = uuid("75000000-0000-0000-0000-000000000031")
        let segmentID = uuid("75000000-0000-0000-0000-000000000032")
        let startFrameID = uuid("75000000-0000-0000-0000-000000000033")
        let ids = CaptureIDFixture(values: [
            .videoSegment: [segmentID],
            .frame: [startFrameID]
        ])
        let spy = CaptureClientSpy()
        let client = SemanticRecordingCaptureClient(
            startMovie: { request in
                await spy.append("startMovie:\(request.artifactRef.path)")
                return SemanticRecordingMovieHandle(
                    segmentID: request.segmentID,
                    artifactRef: request.artifactRef,
                    target: request.target,
                    startTime: request.recordingTime
                )
            },
            finishMovie: { request in
                await spy.append("finishMovie:\(request.handle.artifactRef.path)")
                return SemanticRecordingMovieFinishResult(duration: request.recordingTime)
            },
            captureFrame: { request in
                await spy.append("captureFrame:\(request.source.rawValue)")
                return SemanticRecordingCapturedFrame()
            }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(recordingID: recordingID),
            client: client,
            ids: ids.provider
        )

        try await session.start(recordingTime: 0.25)
        await session.cancel(recordingTime: 1.5)

        #expect(await spy.operations == [
            "startMovie:video/recording.mov",
            "captureFrame:recordingStart",
            "finishMovie:video/recording.mov"
        ])
        await #expect(throws: SemanticRecordingCaptureError.alreadyFinished) {
            try await session.record(recordedEvent(.leftMouseUp, time: 1.6), index: 0)
        }
    }

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

    @Test("Suppression redacts future AI-safe text and visual observation text")
    func suppressionRedactsFutureAISafeTextAndVisualObservationText() async throws {
        let recordingID = uuid("77000000-0000-0000-0000-000000000101")
        let textFrameID = uuid("77000000-0000-0000-0000-000000000103")
        let observationID = uuid("77000000-0000-0000-0000-000000000104")
        let eventID = uuid("77000000-0000-0000-0000-000000000106")
        let semanticID = uuid("77000000-0000-0000-0000-000000000107")
        let suppressionID = uuid("77000000-0000-0000-0000-000000000108")
        let ids = CaptureIDFixture(values: [
            .frame: [
                uuid("77000000-0000-0000-0000-000000000102"),
                textFrameID,
                uuid("77000000-0000-0000-0000-000000000105")
            ],
            .timelineEvent: [eventID],
            .semanticEvent: [semanticID]
        ])
        let secretArtifactRef = try RecordingArtifactRef("observations/secret-crop.png")
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
                        artifactRef: secretArtifactRef,
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 20, y: 40, width: 180, height: 30),
                            coordinateSpace: .windowPixels
                        ),
                        text: "Card 4242",
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
        await session.addSuppression(RecordingSuppressionRecord(
            id: suppressionID,
            reason: .passwordField,
            timeRange: RecordingTimeRange(startTime: 0.35, duration: 0.2),
            detail: "A password field was focused.",
            createdAt: Date(timeIntervalSince1970: 1_800_000_300)
        ))
        try await session.record(
            recordedEvent(.keyDown, time: 0.4, unicodeString: "4"),
            index: 0
        )
        let bundle = try await session.finish(recordingTime: 0.8)

        #expect(bundle.validate().isEmpty)
        #expect(bundle.suppressions.map(\.id) == [suppressionID])
        #expect(bundle.aiSafeEvents.map(\.id) == [semanticID])
        #expect(bundle.aiSafeEvents.first?.title == "Input withheld")
        #expect(bundle.aiSafeEvents.first?.summary == "Details withheld due to passwordField.")
        #expect(bundle.aiSafeEvents.first?.evidenceFrameIDs.isEmpty == true)
        #expect(bundle.aiSafeEvents.first?.risk == "Suppressed evidence is unavailable to AI suggestions.")
        #expect(bundle.timelineEvents.first?.id == eventID)
        #expect(bundle.timelineEvents.first?.frameID == textFrameID)

        let observation = try #require(bundle.visualObservations.first)
        #expect(observation.id == observationID)
        #expect(observation.frameID == textFrameID)
        #expect(observation.text == nil)
        #expect(observation.confidence == nil)
        #expect(observation.artifactRef == nil)
        #expect(observation.labels.contains("redacted"))
        #expect(observation.metadata["redactedReason"] == "passwordField")
        #expect(observation.metadata["redactedBySuppressionID"] == suppressionID.uuidString)
    }

    @Test("Frame index can attach window and AX metadata observations")
    func frameIndexCanAttachWindowAndAXMetadataObservations() async throws {
        let recordingID = uuid("7A000000-0000-0000-0000-000000000001")
        let eventFrameID = uuid("7A000000-0000-0000-0000-000000000003")
        let windowObservationID = uuid("7A000000-0000-0000-0000-000000000004")
        let axObservationID = uuid("7A000000-0000-0000-0000-000000000005")
        let ids = CaptureIDFixture(values: [
            .frame: [
                uuid("7A000000-0000-0000-0000-000000000002"),
                eventFrameID,
                uuid("7A000000-0000-0000-0000-000000000006")
            ],
            .timelineEvent: [uuid("7A000000-0000-0000-0000-000000000007")],
            .semanticEvent: [uuid("7A000000-0000-0000-0000-000000000008")]
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
                SemanticRecordingCapturedFrame(imageSize: RecordingImageSize(width: 1_440, height: 900))
            },
            indexFrame: { request in
                guard request.frame.source == .mouseUp else {
                    return []
                }
                return [
                    RecordingVisualObservation(
                        id: windowObservationID,
                        kind: .windowSnapshot,
                        recordingTime: request.frame.recordingTime,
                        frameID: request.frame.id,
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 120, y: 80, width: 900, height: 640),
                            coordinateSpace: .screenPixels
                        ),
                        text: "Checkout",
                        provider: "CoreGraphics.fake",
                        labels: ["window"],
                        metadata: [
                            "bundleIdentifier": "com.example.Checkout",
                            "windowID": "42"
                        ],
                        createdAt: request.createdAt
                    ),
                    RecordingVisualObservation(
                        id: axObservationID,
                        kind: .axElement,
                        recordingTime: request.frame.recordingTime,
                        frameID: request.frame.id,
                        bounds: RecordingBounds(
                            rect: RecordingRect(x: 240, y: 180, width: 120, height: 32),
                            coordinateSpace: .screenPixels
                        ),
                        text: "Place Order",
                        provider: "ApplicationServices.fake",
                        labels: ["accessibility"],
                        metadata: [
                            "role": "AXButton",
                            "title": "Place Order"
                        ],
                        createdAt: request.createdAt
                    )
                ]
            }
        )
        let session = SemanticRecordingCaptureSession(
            configuration: SemanticRecordingCaptureConfiguration(
                recordingID: recordingID,
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
            recordedEvent(.leftMouseUp, time: 0.4, surfaceID: "checkout-window"),
            index: 0
        )
        let bundle = try await session.finish(recordingTime: 0.8)

        #expect(bundle.validate().isEmpty)
        #expect(bundle.visualObservations.map(\.kind) == [.windowSnapshot, .axElement])
        #expect(bundle.visualObservations.allSatisfy { $0.frameID == eventFrameID })
        #expect(bundle.visualObservations.first?.metadata["windowID"] == "42")
        #expect(bundle.visualObservations.last?.metadata["role"] == "AXButton")
        #expect(bundle.observations(frameID: eventFrameID).map(\.id) == [
            windowObservationID,
            axObservationID
        ])
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

import Foundation

public enum SemanticRecordingCaptureIDKind: String, Sendable {
    case recording
    case videoSegment
    case frame
    case timelineEvent
    case semanticEvent
    case visualObservation
    case suppression
}

public struct SemanticRecordingCaptureIDProvider: @unchecked Sendable {
    public var next: @Sendable (SemanticRecordingCaptureIDKind) -> UUID

    public init(next: @escaping @Sendable (SemanticRecordingCaptureIDKind) -> UUID = { _ in UUID() }) {
        self.next = next
    }
}

public struct SemanticRecordingCaptureConfiguration: Equatable, Sendable {
    public var recordingID: UUID
    public var createdAt: Date
    public var capturePolicy: RecordingCapturePolicy
    public var captureTarget: RecordingCaptureTarget
    public var videoArtifactRef: RecordingArtifactRef
    public var defaultSurfaceID: String?

    public init(
        recordingID: UUID = UUID(),
        createdAt: Date = Date.now,
        capturePolicy: RecordingCapturePolicy = RecordingCapturePolicy(),
        captureTarget: RecordingCaptureTarget = RecordingCaptureTarget(),
        videoArtifactRef: RecordingArtifactRef? = nil,
        defaultSurfaceID: String? = nil
    ) {
        self.recordingID = recordingID
        self.createdAt = createdAt
        self.capturePolicy = capturePolicy
        self.captureTarget = captureTarget
        self.videoArtifactRef = videoArtifactRef ?? Self.defaultVideoArtifactRef
        self.defaultSurfaceID = defaultSurfaceID
    }

    private static var defaultVideoArtifactRef: RecordingArtifactRef {
        do {
            return try RecordingArtifactRef("video/recording.mov")
        } catch {
            preconditionFailure("Invalid built-in semantic recording video artifact ref")
        }
    }
}

public struct SemanticRecordingMovieStartRequest: Equatable, Sendable {
    public var recordingID: UUID
    public var segmentID: UUID
    public var artifactRef: RecordingArtifactRef
    public var target: RecordingCaptureTarget
    public var startedAt: Date
    public var recordingTime: TimeInterval

    public init(
        recordingID: UUID,
        segmentID: UUID,
        artifactRef: RecordingArtifactRef,
        target: RecordingCaptureTarget,
        startedAt: Date,
        recordingTime: TimeInterval
    ) {
        self.recordingID = recordingID
        self.segmentID = segmentID
        self.artifactRef = artifactRef
        self.target = target
        self.startedAt = startedAt
        self.recordingTime = max(0, recordingTime)
    }
}

public struct SemanticRecordingMovieHandle: Equatable, Sendable {
    public var segmentID: UUID
    public var artifactRef: RecordingArtifactRef
    public var target: RecordingCaptureTarget
    public var startTime: TimeInterval
    public var fileType: String
    public var codec: String
    public var frameSize: RecordingImageSize?

    public init(
        segmentID: UUID,
        artifactRef: RecordingArtifactRef,
        target: RecordingCaptureTarget,
        startTime: TimeInterval,
        fileType: String = "mov",
        codec: String = "SCRecordingOutput",
        frameSize: RecordingImageSize? = nil
    ) {
        self.segmentID = segmentID
        self.artifactRef = artifactRef
        self.target = target
        self.startTime = max(0, startTime)
        self.fileType = fileType
        self.codec = codec
        self.frameSize = frameSize
    }
}

public struct SemanticRecordingMovieFinishRequest: Equatable, Sendable {
    public var recordingID: UUID
    public var handle: SemanticRecordingMovieHandle
    public var finishedAt: Date
    public var recordingTime: TimeInterval

    public init(
        recordingID: UUID,
        handle: SemanticRecordingMovieHandle,
        finishedAt: Date,
        recordingTime: TimeInterval
    ) {
        self.recordingID = recordingID
        self.handle = handle
        self.finishedAt = finishedAt
        self.recordingTime = max(0, recordingTime)
    }
}

public struct SemanticRecordingMovieFinishResult: Equatable, Sendable {
    public var duration: TimeInterval
    public var frameSize: RecordingImageSize?
    public var fileType: String
    public var codec: String

    public init(
        duration: TimeInterval,
        frameSize: RecordingImageSize? = nil,
        fileType: String = "mov",
        codec: String = "SCRecordingOutput"
    ) {
        self.duration = max(0, duration)
        self.frameSize = frameSize
        self.fileType = fileType
        self.codec = codec
    }
}

public struct SemanticRecordingFrameCaptureRequest: Equatable, Sendable {
    public var frameID: UUID
    public var recordingID: UUID
    public var source: RecordingFrameCaptureSource
    public var artifactRef: RecordingArtifactRef
    public var recordingTime: TimeInterval
    public var videoSegmentID: UUID?
    public var videoTime: TimeInterval?
    public var target: RecordingCaptureTarget
    public var surfaceID: String?
    public var relatedEventIDs: [UUID]

    public init(
        frameID: UUID,
        recordingID: UUID,
        source: RecordingFrameCaptureSource,
        artifactRef: RecordingArtifactRef,
        recordingTime: TimeInterval,
        videoSegmentID: UUID? = nil,
        videoTime: TimeInterval? = nil,
        target: RecordingCaptureTarget,
        surfaceID: String? = nil,
        relatedEventIDs: [UUID] = []
    ) {
        self.frameID = frameID
        self.recordingID = recordingID
        self.source = source
        self.artifactRef = artifactRef
        self.recordingTime = max(0, recordingTime)
        self.videoSegmentID = videoSegmentID
        self.videoTime = videoTime.map { max(0, $0) }
        self.target = target
        self.surfaceID = surfaceID
        self.relatedEventIDs = relatedEventIDs
    }
}

public struct SemanticRecordingCapturedFrame: Equatable, Sendable {
    public var imageSize: RecordingImageSize?
    public var windowBounds: RecordingBounds?
    public var displayScale: Double?

    public init(
        imageSize: RecordingImageSize? = nil,
        windowBounds: RecordingBounds? = nil,
        displayScale: Double? = nil
    ) {
        self.imageSize = imageSize
        self.windowBounds = windowBounds
        self.displayScale = displayScale
    }
}

public struct SemanticRecordingFrameIndexRequest: Equatable, Sendable {
    public var recordingID: UUID
    public var frame: RecordingFrameReference
    public var target: RecordingCaptureTarget
    public var createdAt: Date

    public init(
        recordingID: UUID,
        frame: RecordingFrameReference,
        target: RecordingCaptureTarget,
        createdAt: Date
    ) {
        self.recordingID = recordingID
        self.frame = frame
        self.target = target
        self.createdAt = createdAt
    }
}

public struct SemanticRecordingCaptureClient: @unchecked Sendable {
    public var startMovie: @Sendable (SemanticRecordingMovieStartRequest) async throws -> SemanticRecordingMovieHandle
    public var finishMovie: @Sendable (SemanticRecordingMovieFinishRequest) async throws -> SemanticRecordingMovieFinishResult
    public var captureFrame: @Sendable (SemanticRecordingFrameCaptureRequest) async throws -> SemanticRecordingCapturedFrame
    public var indexFrame: @Sendable (SemanticRecordingFrameIndexRequest) async throws -> [RecordingVisualObservation]

    public init(
        startMovie: @escaping @Sendable (SemanticRecordingMovieStartRequest) async throws -> SemanticRecordingMovieHandle,
        finishMovie: @escaping @Sendable (SemanticRecordingMovieFinishRequest) async throws -> SemanticRecordingMovieFinishResult,
        captureFrame: @escaping @Sendable (SemanticRecordingFrameCaptureRequest) async throws -> SemanticRecordingCapturedFrame,
        indexFrame: @escaping @Sendable (SemanticRecordingFrameIndexRequest) async throws -> [RecordingVisualObservation] = { _ in [] }
    ) {
        self.startMovie = startMovie
        self.finishMovie = finishMovie
        self.captureFrame = captureFrame
        self.indexFrame = indexFrame
    }
}

public enum SemanticRecordingCaptureError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case alreadyFinished
}

public actor SemanticRecordingCaptureSession {
    private let configuration: SemanticRecordingCaptureConfiguration
    private let client: SemanticRecordingCaptureClient
    private let ids: SemanticRecordingCaptureIDProvider

    private var didStart = false
    private var didFinish = false
    private var movieHandle: SemanticRecordingMovieHandle?
    private var frames: [RecordingFrameReference] = []
    private var timelineEvents: [RecordingTimelineEvent] = []
    private var semanticEvents: [RecordingSemanticEvent] = []
    private var visualObservations: [RecordingVisualObservation] = []
    private var suppressions: [RecordingSuppressionRecord] = []
    private var frameOrdinal = 0

    public init(
        configuration: SemanticRecordingCaptureConfiguration,
        client: SemanticRecordingCaptureClient,
        ids: SemanticRecordingCaptureIDProvider = SemanticRecordingCaptureIDProvider()
    ) {
        self.configuration = configuration
        self.client = client
        self.ids = ids
    }

    public func start(recordingTime: TimeInterval = 0) async throws {
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }
        guard !didStart else {
            throw SemanticRecordingCaptureError.alreadyStarted
        }
        didStart = true

        if configuration.capturePolicy.recordsVideo {
            movieHandle = try await client.startMovie(SemanticRecordingMovieStartRequest(
                recordingID: configuration.recordingID,
                segmentID: ids.next(.videoSegment),
                artifactRef: configuration.videoArtifactRef,
                target: configuration.captureTarget,
                startedAt: configuration.createdAt,
                recordingTime: recordingTime
            ))
        }

        if configuration.capturePolicy.recordsKeyframes {
            _ = try await captureFrame(
                source: .recordingStart,
                recordingTime: recordingTime,
                relatedEventIDs: []
            )
        }
    }

    public func record(_ event: RecordedEvent, index: Int) async throws {
        guard didStart else {
            throw SemanticRecordingCaptureError.notStarted
        }
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }

        let eventID = ids.next(.timelineEvent)
        let source = RecordingFrameCaptureSource(recordedEventKind: event.kind)
        let frame: RecordingFrameReference?
        if let source {
            frame = try await captureFrame(
                source: source,
                recordingTime: event.time,
                surfaceID: event.surfaceId,
                relatedEventIDs: [eventID]
            )
        } else {
            frame = nil
        }

        let timelineEvent = RecordingTimelineEvent(
            id: eventID,
            recordingTime: event.time,
            kind: .recordedEvent,
            frameID: frame?.id,
            videoSegmentID: movieHandle?.segmentID,
            recordedEventIndex: index,
            surfaceID: event.surfaceId ?? configuration.defaultSurfaceID,
            summary: Self.summary(for: event)
        )
        timelineEvents.append(timelineEvent)

        if let semanticEvent = semanticEvent(for: event, eventID: eventID, frameID: frame?.id) {
            semanticEvents.append(semanticEvent)
        }
    }

    public func addSuppression(_ suppression: RecordingSuppressionRecord) {
        suppressions.append(suppression)
    }

    public func finish(recordingTime: TimeInterval) async throws -> SemanticRecordingBundle {
        guard didStart else {
            throw SemanticRecordingCaptureError.notStarted
        }
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }
        didFinish = true

        if configuration.capturePolicy.recordsKeyframes {
            _ = try await captureFrame(
                source: .recordingStop,
                recordingTime: recordingTime,
                relatedEventIDs: []
            )
        }

        var videoSegments: [RecordingVideoSegment] = []
        if let movieHandle {
            let result = try await client.finishMovie(SemanticRecordingMovieFinishRequest(
                recordingID: configuration.recordingID,
                handle: movieHandle,
                finishedAt: configuration.createdAt.addingTimeInterval(recordingTime),
                recordingTime: recordingTime
            ))
            videoSegments.append(RecordingVideoSegment(
                id: movieHandle.segmentID,
                artifactRef: movieHandle.artifactRef,
                startTime: movieHandle.startTime,
                duration: result.duration,
                target: movieHandle.target,
                fileType: result.fileType,
                codec: result.codec,
                frameSize: result.frameSize ?? movieHandle.frameSize
            ))
        }

        return SemanticRecordingBundle(
            id: configuration.recordingID,
            createdAt: configuration.createdAt,
            capturePolicy: configuration.capturePolicy,
            captureTarget: configuration.captureTarget,
            videoSegments: videoSegments,
            frames: frames,
            timelineEvents: timelineEvents,
            semanticEvents: semanticEvents,
            visualObservations: visualObservations,
            suppressions: suppressions
        )
    }

    private func captureFrame(
        source: RecordingFrameCaptureSource,
        recordingTime: TimeInterval,
        surfaceID: String? = nil,
        relatedEventIDs: [UUID]
    ) async throws -> RecordingFrameReference {
        frameOrdinal += 1
        let frameID = ids.next(.frame)
        let request = SemanticRecordingFrameCaptureRequest(
            frameID: frameID,
            recordingID: configuration.recordingID,
            source: source,
            artifactRef: Self.frameArtifactRef(ordinal: frameOrdinal, source: source),
            recordingTime: recordingTime,
            videoSegmentID: movieHandle?.segmentID,
            videoTime: movieHandle == nil ? nil : recordingTime,
            target: configuration.captureTarget,
            surfaceID: surfaceID ?? configuration.defaultSurfaceID,
            relatedEventIDs: relatedEventIDs
        )
        let captured = try await client.captureFrame(request)
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: recordingTime,
            videoSegmentID: request.videoSegmentID,
            videoTime: request.videoTime,
            imageRef: request.artifactRef,
            imageSize: captured.imageSize,
            source: source,
            surfaceID: request.surfaceID,
            windowBounds: captured.windowBounds,
            displayScale: captured.displayScale,
            relatedEventIDs: relatedEventIDs
        )
        frames.append(frame)

        let indexed = try await client.indexFrame(SemanticRecordingFrameIndexRequest(
            recordingID: configuration.recordingID,
            frame: frame,
            target: configuration.captureTarget,
            createdAt: configuration.createdAt.addingTimeInterval(recordingTime)
        ))
        visualObservations.append(contentsOf: indexed)
        return frame
    }

    private func semanticEvent(
        for event: RecordedEvent,
        eventID: UUID,
        frameID: UUID?
    ) -> RecordingSemanticEvent? {
        guard let kind = RecordingSemanticEventKind(recordedEventKind: event.kind) else {
            return nil
        }
        return RecordingSemanticEvent(
            id: ids.next(.semanticEvent),
            recordingTime: event.time,
            kind: kind,
            frameID: frameID,
            timelineEventID: eventID,
            title: Self.title(for: event),
            summary: Self.summary(for: event),
            evidenceFrameIDs: frameID.map { [$0] } ?? [],
            risk: Self.risk(for: event)
        )
    }

    private static func frameArtifactRef(
        ordinal: Int,
        source: RecordingFrameCaptureSource
    ) -> RecordingArtifactRef {
        do {
            return try RecordingArtifactRef(
                "frames/\(String(format: "%06d", ordinal))-\(source.rawValue).png"
            )
        } catch {
            preconditionFailure("Invalid generated semantic recording frame artifact ref")
        }
    }

    private static func title(for event: RecordedEvent) -> String {
        switch event.kind {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return "Mouse down"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return "Mouse up"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return "Drag"
        case .keyDown:
            return event.unicodeString?.isEmpty == false ? "Text input" : "Key down"
        case .keyUp:
            return "Key up"
        case .scrollWheel:
            return "Scroll"
        case .waitForText:
            return "Wait for text"
        case .verifyText:
            return "Verify text"
        case .mouseMoved:
            return "Mouse move"
        case .flagsChanged:
            return "Modifier changed"
        }
    }

    private static func summary(for event: RecordedEvent) -> String {
        switch event.kind {
        case .keyDown where event.unicodeString?.isEmpty == false:
            return "Typed text at \(format(event.time))s"
        case .scrollWheel:
            return "Scrolled at \(format(event.time))s"
        case .waitForText:
            return "Waited for text at \(format(event.time))s"
        case .verifyText:
            return "Verified text at \(format(event.time))s"
        default:
            return "\(title(for: event)) at \(format(event.time))s"
        }
    }

    private static func risk(for event: RecordedEvent) -> String? {
        switch event.kind {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return "Coordinate click should be reviewed against nearby OCR, image, or AX evidence."
        case .waitForText:
            return "Recorded wait should be reviewed as an OCR condition candidate."
        default:
            return nil
        }
    }

    private static func format(_ time: TimeInterval) -> String {
        String(format: "%.3f", max(0, time))
    }
}

public extension RecordingFrameCaptureSource {
    init?(recordedEventKind kind: RecordedEvent.Kind) {
        switch kind {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self = .mouseDown
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            self = .mouseUp
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            self = .dragEnd
        case .keyDown:
            self = .textInput
        case .scrollWheel:
            self = .scrollSettled
        case .waitForText:
            self = .longWaitAfter
        case .verifyText:
            self = .manual
        case .mouseMoved, .keyUp, .flagsChanged:
            return nil
        }
    }
}

public extension RecordingSemanticEventKind {
    init?(recordedEventKind kind: RecordedEvent.Kind) {
        switch kind {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            self = .click
        case .keyDown:
            self = .inputText
        case .scrollWheel:
            self = .scroll
        case .waitForText:
            self = .wait
        case .verifyText:
            self = .conditionCandidate
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyUp,
             .flagsChanged, .otherMouseDragged:
            return nil
        }
    }
}

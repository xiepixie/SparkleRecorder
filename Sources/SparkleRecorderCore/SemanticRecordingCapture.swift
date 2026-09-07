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
    public var sessionOriginHostTime: Double?
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
        defaultSurfaceID: String? = nil,
        sessionOriginHostTime: Double? = nil
    ) {
        self.sessionOriginHostTime = sessionOriginHostTime
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
    public var timingEvidence: RecordingMovieTimingEvidence?
    public var duration: TimeInterval
    public var frameSize: RecordingImageSize?
    public var fileType: String
    public var codec: String

    public init(
        duration: TimeInterval,
        frameSize: RecordingImageSize? = nil,
        fileType: String = "mov",
        codec: String = "SCRecordingOutput",
        timingEvidence: RecordingMovieTimingEvidence? = nil
    ) {
        self.timingEvidence = timingEvidence
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
    public var capturedHostTime: Double?
    public var timestampUncertainty: Double?
    public var imageSize: RecordingImageSize?
    public var windowBounds: RecordingBounds?
    public var displayScale: Double?

    public init(
        imageSize: RecordingImageSize? = nil,
        windowBounds: RecordingBounds? = nil,
        displayScale: Double? = nil,
        capturedHostTime: Double? = nil,
        timestampUncertainty: Double? = nil
    ) {
        self.capturedHostTime = capturedHostTime
        self.timestampUncertainty = timestampUncertainty
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
    private var captureIssues: [RecordingCaptureIssue] = []
    private var frameOrdinal = 0
    private var sourceEventTimes: [RecordingSourceEventTime] = []
    private var capturedSourceEvents: [RecordedEvent] = []
    private var sourceEventOrderValid = true
    private var inputEvidenceSamples: [RecordingEvidenceSample] = []
    private var playableEvidenceLinks: [RecordingPlayableEvidenceLink] = []
    private var omittedEvidenceSampleCount = 0
    private var frameTimings: [RecordingFrameTimingEvidence] = []

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
            do {
                movieHandle = try await client.startMovie(SemanticRecordingMovieStartRequest(
                    recordingID: configuration.recordingID,
                    segmentID: ids.next(.videoSegment),
                    artifactRef: configuration.videoArtifactRef,
                    target: configuration.captureTarget,
                    startedAt: configuration.createdAt,
                    recordingTime: recordingTime
                ))
            } catch {
                recordCaptureIssue(
                    kind: .movieStartFailed,
                    recordingTime: recordingTime,
                    message: String(describing: error)
                )
            }
        }

        if configuration.capturePolicy.recordsKeyframes {
            _ = await captureFrameIfPossible(
                source: .recordingStart,
                recordingTime: recordingTime,
                relatedEventIDs: []
            )
        }
    }

    public func record(_ event: RecordedEvent, index: Int, sessionTime: Double? = nil) async throws {
        guard didStart else {
            throw SemanticRecordingCaptureError.notStarted
        }
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }
        // Preserve the input event before replacing its playback timestamp with
        // session time for visual evidence. An incomplete/out-of-order sequence
        // cannot establish the saved macro's identity.
        if index != capturedSourceEvents.count { sourceEventOrderValid = false }
        capturedSourceEvents.append(event)
        var evidenceEvent = event
        if let sessionTime, sessionTime.isFinite, sessionTime >= 0 {
            sourceEventTimes.append(.init(sourceEventIndex: index, sourcePlaybackTime: event.time, sessionTime: sessionTime))
            evidenceEvent.time = sessionTime
        }
        let event = evidenceEvent

        let eventID = ids.next(.timelineEvent)
        let frameCaptureMode: RecordingCaptureMode =
            configuration.capturePolicy.mode == .videoAndKeyframes && movieHandle == nil
                ? .keyframesOnly
                : configuration.capturePolicy.mode
        let source = RecordingFrameCaptureSource(
            recordedEventKind: event.kind,
            mode: frameCaptureMode
        )
        let frame: RecordingFrameReference?
        if let source {
            frame = await captureFrameIfPossible(
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
            semanticEvents.append(redactedSemanticEventIfNeeded(semanticEvent))
        }
    }

    public func recordEvidence(
        samples: [RecordingEvidenceSample],
        playableLinks: [RecordingPlayableEvidenceLink],
        omittedSampleCount: Int = 0
    ) throws {
        guard didStart else {
            throw SemanticRecordingCaptureError.notStarted
        }
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }
        inputEvidenceSamples.append(contentsOf: samples)
        playableEvidenceLinks.append(contentsOf: playableLinks)
        omittedEvidenceSampleCount += max(0, omittedSampleCount)
    }

    public func addSuppression(_ suppression: RecordingSuppressionRecord) {
        suppressions.append(suppression)
        applySemanticRedaction(for: suppression)
    }

    public func finish(
        recordingTime: TimeInterval,
        finalPlayableEvents: [RecordedEvent]? = nil
    ) async throws -> SemanticRecordingBundle {
        guard didStart else {
            throw SemanticRecordingCaptureError.notStarted
        }
        guard !didFinish else {
            throw SemanticRecordingCaptureError.alreadyFinished
        }
        didFinish = true

        if configuration.capturePolicy.recordsKeyframes {
            _ = await captureFrameIfPossible(
                source: .recordingStop,
                recordingTime: recordingTime,
                relatedEventIDs: []
            )
        }

        var videoSegments: [RecordingVideoSegment] = []
        var movieEvidence: [RecordingMovieTimingEvidence] = []
        if let movieHandle {
            do {
                let result = try await client.finishMovie(SemanticRecordingMovieFinishRequest(
                    recordingID: configuration.recordingID,
                    handle: movieHandle,
                    finishedAt: configuration.createdAt.addingTimeInterval(recordingTime),
                    recordingTime: recordingTime
                ))
                movieEvidence.append(result.timingEvidence ?? .init(segmentID: movieHandle.segmentID))
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
            } catch {
                recordCaptureIssue(
                    kind: .movieFinishFailed,
                    recordingTime: recordingTime,
                    message: String(describing: error)
                )
            }
        }

        let finalSourceEvents = finalPlayableEvents ?? capturedSourceEvents
        let finalSourceEventTimes = sourceEventTimes.filter { item in
            guard finalSourceEvents.indices.contains(item.sourceEventIndex) else { return false }
            return finalSourceEvents[item.sourceEventIndex].time == item.sourcePlaybackTime
        }
        let finalPlayableEvidenceLinks = playableEvidenceLinks.filter {
            finalSourceEvents.indices.contains($0.playableEventIndex)
        }
        let finalDigest: String? = {
            if finalPlayableEvents != nil {
                return try? RecordingReconstructionProvenance.digest(ofSourceEvents: finalSourceEvents)
            }
            return sourceEventOrderValid
                ? (try? RecordingReconstructionProvenance.digest(ofSourceEvents: capturedSourceEvents))
                : nil
        }()

        return SemanticRecordingBundle(
            id: configuration.recordingID,
            createdAt: configuration.createdAt,
            capturePolicy: configuration.capturePolicy,
            captureTarget: configuration.captureTarget,
            captureIssues: captureIssues,
            videoSegments: videoSegments,
            frames: frames,
            timelineEvents: timelineEvents,
            semanticEvents: semanticEvents,
            visualObservations: visualObservations,
            suppressions: suppressions,
            inputEvidenceSamples: inputEvidenceSamples,
            reconstructionProvenance: configuration.sessionOriginHostTime.map { origin in
                RecordingReconstructionProvenance(sessionOriginHostTime: origin, sessionEndTime: recordingTime,
                    sourceEvents: finalSourceEventTimes, movieEvidence: movieEvidence, frameTimings: frameTimings,
                    clockSegments: RecordingReconstructionProvenance.writtenMovieClocks(movieEvidence: movieEvidence, origin: origin),
                    geometrySnapshots: RecordingReconstructionProvenance.measuredGeometry(movieEvidence: movieEvidence, origin: origin, surfaceID: configuration.defaultSurfaceID ?? configuration.captureTarget.surfaceID),
                    sourceEventDigest: finalDigest,
                    playableEvidenceLinks: finalPlayableEvidenceLinks,
                    omittedEvidenceSampleCount: omittedEvidenceSampleCount)
            }
        )
    }

    public func cancel(recordingTime: TimeInterval) async {
        guard didStart, !didFinish else {
            return
        }
        didFinish = true

        if let movieHandle {
            _ = try? await client.finishMovie(SemanticRecordingMovieFinishRequest(
                recordingID: configuration.recordingID,
                handle: movieHandle,
                finishedAt: configuration.createdAt.addingTimeInterval(recordingTime),
                recordingTime: recordingTime
            ))
        }

        movieHandle = nil
    }

    private func captureFrameIfPossible(
        source: RecordingFrameCaptureSource,
        recordingTime: TimeInterval,
        surfaceID: String? = nil,
        relatedEventIDs: [UUID]
    ) async -> RecordingFrameReference? {
        do {
            return try await captureFrame(
                source: source,
                recordingTime: recordingTime,
                surfaceID: surfaceID,
                relatedEventIDs: relatedEventIDs
            )
        } catch {
            recordCaptureIssue(
                kind: .keyframeCaptureFailed,
                recordingTime: recordingTime,
                frameSource: source,
                surfaceID: surfaceID,
                message: String(describing: error)
            )
            return nil
        }
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
            videoTime: nil,
            target: configuration.captureTarget,
            surfaceID: surfaceID ?? configuration.defaultSurfaceID,
            relatedEventIDs: relatedEventIDs
        )
        let captured = try await client.captureFrame(request)
        let capturedTime = captured.capturedHostTime.flatMap { host in
            configuration.sessionOriginHostTime.flatMap { origin in
                host.isFinite && host >= origin ? host - origin : nil
            }
        }
        frameTimings.append(.init(frameID: frameID, requestedSessionTime: recordingTime, capturedSessionTime: capturedTime, uncertainty: captured.timestampUncertainty))
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: capturedTime ?? recordingTime,
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

        do {
            let indexed = try await client.indexFrame(SemanticRecordingFrameIndexRequest(
                recordingID: configuration.recordingID,
                frame: frame,
                target: configuration.captureTarget,
                createdAt: configuration.createdAt.addingTimeInterval(recordingTime)
            ))
            visualObservations.append(contentsOf: indexed.map(redactedVisualObservationIfNeeded))
        } catch {
            recordCaptureIssue(
                kind: .frameIndexFailed,
                recordingTime: recordingTime,
                frameSource: source,
                surfaceID: request.surfaceID,
                message: String(describing: error)
            )
        }
        return frame
    }

    private func recordCaptureIssue(
        kind: RecordingCaptureIssueKind,
        recordingTime: TimeInterval,
        frameSource: RecordingFrameCaptureSource? = nil,
        surfaceID: String? = nil,
        message: String
    ) {
        captureIssues.append(RecordingCaptureIssue(
            kind: kind,
            recordingTime: recordingTime,
            frameSource: frameSource,
            surfaceID: surfaceID,
            message: message
        ))
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

    private func applySemanticRedaction(
        for suppression: RecordingSuppressionRecord
    ) {
        guard suppression.reason.redactsSemanticEvidence else {
            return
        }
        semanticEvents = semanticEvents.map { event in
            guard suppressionMatches(suppression, semanticEvent: event) else {
                return event
            }
            return redactedSemanticEvent(event, suppression: suppression)
        }
        visualObservations = visualObservations.map { observation in
            guard suppressionMatches(suppression, observation: observation) else {
                return observation
            }
            return redactedVisualObservation(observation, suppression: suppression)
        }
    }

    private func redactedSemanticEventIfNeeded(
        _ event: RecordingSemanticEvent
    ) -> RecordingSemanticEvent {
        var redacted = event
        for suppression in suppressions where suppression.reason.redactsSemanticEvidence {
            if suppressionMatches(suppression, semanticEvent: redacted) {
                redacted = redactedSemanticEvent(redacted, suppression: suppression)
            }
        }
        return redacted
    }

    private func redactedVisualObservationIfNeeded(
        _ observation: RecordingVisualObservation
    ) -> RecordingVisualObservation {
        var redacted = observation
        for suppression in suppressions where suppression.reason.redactsSemanticEvidence {
            if suppressionMatches(suppression, observation: redacted) {
                redacted = redactedVisualObservation(redacted, suppression: suppression)
            }
        }
        return redacted
    }

    private func redactedSemanticEvent(
        _ event: RecordingSemanticEvent,
        suppression: RecordingSuppressionRecord
    ) -> RecordingSemanticEvent {
        var redacted = event
        redacted.title = Self.redactedTitle(for: event.kind)
        redacted.summary = "Details withheld due to \(suppression.reason.rawValue)."
        redacted.evidenceFrameIDs = []
        redacted.observationIDs = []
        redacted.risk = "Suppressed evidence is unavailable to AI suggestions."
        return redacted
    }

    private func redactedVisualObservation(
        _ observation: RecordingVisualObservation,
        suppression: RecordingSuppressionRecord
    ) -> RecordingVisualObservation {
        var redacted = observation
        redacted.text = nil
        redacted.confidence = nil
        redacted.artifactRef = nil
        if !redacted.labels.contains("redacted") {
            redacted.labels.append("redacted")
        }
        redacted.metadata["redactedReason"] = suppression.reason.rawValue
        redacted.metadata["redactedBySuppressionID"] = suppression.id.uuidString
        return redacted
    }

    private func suppressionMatches(
        _ suppression: RecordingSuppressionRecord,
        semanticEvent event: RecordingSemanticEvent
    ) -> Bool {
        if let eventID = suppression.eventID,
           event.timelineEventID == eventID {
            return true
        }
        if let frameID = suppression.frameID,
           event.frameID == frameID || event.evidenceFrameIDs.contains(frameID) {
            return true
        }
        return suppressionMatches(
            suppression,
            recordingTime: event.recordingTime
        )
    }

    private func suppressionMatches(
        _ suppression: RecordingSuppressionRecord,
        observation: RecordingVisualObservation
    ) -> Bool {
        if let frameID = suppression.frameID,
           observation.frameID == frameID {
            return true
        }
        return suppressionMatches(
            suppression,
            recordingTime: observation.recordingTime
        )
    }

    private func suppressionMatches(
        _ suppression: RecordingSuppressionRecord,
        recordingTime: TimeInterval
    ) -> Bool {
        if let timeRange = suppression.timeRange {
            return timeRange.contains(recordingTime)
        }
        if let suppressionTime = suppression.recordingTime {
            return abs(max(0, recordingTime) - max(0, suppressionTime)) <= 0.001
        }
        return false
    }

    private static func redactedTitle(
        for kind: RecordingSemanticEventKind
    ) -> String {
        switch kind {
        case .inputText:
            return "Input withheld"
        case .wait,
             .conditionCandidate:
            return "Text evidence withheld"
        default:
            return "Semantic evidence withheld"
        }
    }
}

public extension RecordingFrameCaptureSource {
    init?(
        recordedEventKind kind: RecordedEvent.Kind,
        mode: RecordingCaptureMode = .diagnosticRich
    ) {
        if mode == .videoAndKeyframes {
            // The movie already preserves continuous before/after state. Keep PNG
            // checkpoints sparse so typing and sampled drags cannot create hundreds
            // of synchronous screenshots and OCR jobs.
            switch kind {
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                self = .mouseUp
            case .waitForText:
                self = .longWaitAfter
            case .verifyText:
                self = .manual
            case .leftMouseDown, .rightMouseDown, .otherMouseDown,
                 .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                 .keyDown, .keyUp, .mouseMoved, .flagsChanged, .scrollWheel:
                // The movie already preserves scroll progression. A discrete
                // wheel burst can contain dozens of events; treating each one as
                // "scroll settled" creates synchronous screenshot/OCR backlog and
                // captures stale post-stop frames rather than historical state.
                return nil
            }
            return
        }

        // Keyframe-only recordings need event checkpoints because no movie exists.
        // Diagnostic-rich mode deliberately keeps the same dense evidence.
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

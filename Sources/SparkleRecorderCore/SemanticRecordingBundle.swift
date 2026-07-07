import Foundation

public enum SemanticRecordingSchema {
    public static let current = SemanticRecordingSchemaVersion(major: 0, minor: 1)

    public static let manifestFileName = "manifest.json"
    public static let privateTimelineFileName = "timeline.jsonl"
    public static let aiSafeEventsFileName = "events.jsonl"
    public static let suppressionsFileName = "suppressed.jsonl"
}

public struct SemanticRecordingSchemaVersion: Codable, Equatable, Comparable, Sendable {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int) {
        self.major = max(0, major)
        self.minor = max(0, minor)
    }

    public static func < (
        lhs: SemanticRecordingSchemaVersion,
        rhs: SemanticRecordingSchemaVersion
    ) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        return lhs.minor < rhs.minor
    }

    public var isSupportedByCurrentApp: Bool {
        major == SemanticRecordingSchema.current.major &&
            minor <= SemanticRecordingSchema.current.minor
    }
}

public enum RecordingArtifactRefError: Error, Equatable, Sendable {
    case emptyPath
    case absolutePath(String)
    case unsupportedScheme(String)
    case unsafeComponent(String)
}

public struct RecordingArtifactRef: Codable, Equatable, Hashable, Sendable {
    public var path: String

    public init(_ path: String) throws {
        self.path = try Self.normalized(path)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let path = try container.decode(String.self)
        do {
            self.path = try Self.normalized(path)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsafe recording artifact ref: \(path)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }

    public static func normalized(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecordingArtifactRefError.emptyPath
        }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
            throw RecordingArtifactRefError.absolutePath(path)
        }
        guard !trimmed.contains("://"),
              !trimmed.lowercased().hasPrefix("file:"),
              !trimmed.contains(":"),
              !trimmed.contains("\\") else {
            throw RecordingArtifactRefError.unsupportedScheme(path)
        }

        let components = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            throw RecordingArtifactRefError.emptyPath
        }
        guard components.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw RecordingArtifactRefError.unsafeComponent(path)
        }
        return components.joined(separator: "/")
    }
}

public enum SemanticRecordingBundleDirectoryIdentityError: Error, Equatable, Sendable {
    case recordingIDMismatch(directoryID: UUID, bundleID: UUID)
}

public enum SemanticRecordingBundleDirectoryIdentity {
    public static func directoryName(for recordingID: UUID) -> String {
        recordingID.uuidString
    }

    public static func recordingID(fromDirectoryName directoryName: String) -> UUID? {
        UUID(uuidString: directoryName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    public static func validate(
        bundle: SemanticRecordingBundle,
        directoryName: String
    ) throws -> UUID {
        guard let directoryID = recordingID(fromDirectoryName: directoryName) else {
            return bundle.id
        }
        guard directoryID == bundle.id else {
            throw SemanticRecordingBundleDirectoryIdentityError.recordingIDMismatch(
                directoryID: directoryID,
                bundleID: bundle.id
            )
        }
        return bundle.id
    }
}

public struct RecordingImageSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public struct RecordingRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public enum RecordingCoordinateSpace: String, Codable, Equatable, Sendable {
    case screenPixels
    case displayPixels
    case windowPixels
    case contentPixels
    case framePixels
    case normalizedFrame
}

public struct RecordingBounds: Codable, Equatable, Sendable {
    public var rect: RecordingRect
    public var coordinateSpace: RecordingCoordinateSpace

    public init(
        rect: RecordingRect,
        coordinateSpace: RecordingCoordinateSpace
    ) {
        self.rect = rect
        self.coordinateSpace = coordinateSpace
    }
}

public struct RecordingTimeRange: Codable, Equatable, Sendable {
    public var startTime: TimeInterval
    public var duration: TimeInterval

    public init(startTime: TimeInterval, duration: TimeInterval) {
        self.startTime = max(0, startTime)
        self.duration = max(0, duration)
    }

    public var endTime: TimeInterval {
        startTime + duration
    }

    public func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time <= endTime
    }
}

public enum RecordingCaptureMode: String, Codable, Equatable, Sendable {
    case videoAndKeyframes
    case keyframesOnly
    case diagnosticRich
}

public struct RecordingCapturePolicy: Codable, Equatable, Sendable {
    public var mode: RecordingCaptureMode
    public var recordsVideo: Bool
    public var recordsKeyframes: Bool
    public var localOnly: Bool
    public var allowsAIFrameExport: Bool

    public init(
        mode: RecordingCaptureMode = .videoAndKeyframes,
        recordsVideo: Bool? = nil,
        recordsKeyframes: Bool? = nil,
        localOnly: Bool = true,
        allowsAIFrameExport: Bool = false
    ) {
        self.mode = mode
        self.recordsVideo = recordsVideo ?? (mode != .keyframesOnly)
        self.recordsKeyframes = recordsKeyframes ?? true
        self.localOnly = localOnly
        self.allowsAIFrameExport = allowsAIFrameExport
    }
}

public enum RecordingCaptureTargetKind: String, Codable, Equatable, Sendable {
    case window
    case display
    case application
    case region
    case unknown
}

public struct RecordingCaptureTarget: Codable, Equatable, Sendable {
    public var kind: RecordingCaptureTargetKind
    public var surfaceID: String?
    public var displayID: UInt32?
    public var windowID: UInt32?
    public var appBundleIdentifier: String?
    public var appName: String?
    public var windowTitle: String?

    public init(
        kind: RecordingCaptureTargetKind = .unknown,
        surfaceID: String? = nil,
        displayID: UInt32? = nil,
        windowID: UInt32? = nil,
        appBundleIdentifier: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil
    ) {
        self.kind = kind
        self.surfaceID = surfaceID
        self.displayID = displayID
        self.windowID = windowID
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public struct RecordingVideoSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var artifactRef: RecordingArtifactRef
    public var startTime: TimeInterval
    public var duration: TimeInterval
    public var target: RecordingCaptureTarget
    public var fileType: String
    public var codec: String
    public var frameSize: RecordingImageSize?

    public init(
        id: UUID = UUID(),
        artifactRef: RecordingArtifactRef,
        startTime: TimeInterval,
        duration: TimeInterval,
        target: RecordingCaptureTarget = RecordingCaptureTarget(),
        fileType: String = "mov",
        codec: String = "SCRecordingOutput",
        frameSize: RecordingImageSize? = nil
    ) {
        self.id = id
        self.artifactRef = artifactRef
        self.startTime = max(0, startTime)
        self.duration = max(0, duration)
        self.target = target
        self.fileType = fileType
        self.codec = codec
        self.frameSize = frameSize
    }

    public var endTime: TimeInterval {
        startTime + duration
    }

    public func contains(_ recordingTime: TimeInterval) -> Bool {
        recordingTime >= startTime && recordingTime <= endTime
    }
}

public enum RecordingFrameCaptureSource: String, Codable, Equatable, Sendable {
    case recordingStart
    case recordingStop
    case focusChange
    case mouseDown
    case mouseUp
    case dragEnd
    case textInput
    case scrollSettled
    case longWaitBefore
    case longWaitAfter
    case userMarker
    case frameDifference
    case manual
    case other
}

public struct RecordingFrameReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingTime: TimeInterval
    public var videoSegmentID: UUID?
    public var videoTime: TimeInterval?
    public var imageRef: RecordingArtifactRef
    public var imageSize: RecordingImageSize?
    public var source: RecordingFrameCaptureSource
    public var surfaceID: String?
    public var windowBounds: RecordingBounds?
    public var displayScale: Double?
    public var relatedEventIDs: [UUID]

    public init(
        id: UUID = UUID(),
        recordingTime: TimeInterval,
        videoSegmentID: UUID? = nil,
        videoTime: TimeInterval? = nil,
        imageRef: RecordingArtifactRef,
        imageSize: RecordingImageSize? = nil,
        source: RecordingFrameCaptureSource,
        surfaceID: String? = nil,
        windowBounds: RecordingBounds? = nil,
        displayScale: Double? = nil,
        relatedEventIDs: [UUID] = []
    ) {
        self.id = id
        self.recordingTime = max(0, recordingTime)
        self.videoSegmentID = videoSegmentID
        self.videoTime = videoTime.map { max(0, $0) }
        self.imageRef = imageRef
        self.imageSize = imageSize
        self.source = source
        self.surfaceID = surfaceID
        self.windowBounds = windowBounds
        self.displayScale = displayScale
        self.relatedEventIDs = relatedEventIDs
    }
}

public enum RecordingTimelineEventKind: String, Codable, Equatable, Sendable {
    case rawInput
    case recordedEvent
    case focusChange
    case windowSnapshot
    case keyframe
    case visualObservation
    case waitStart
    case waitEnd
    case userMarker
    case suppression
    case note
}

public struct RecordingTimelineEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingTime: TimeInterval
    public var kind: RecordingTimelineEventKind
    public var frameID: UUID?
    public var videoSegmentID: UUID?
    public var rawEventIndex: Int?
    public var recordedEventIndex: Int?
    public var surfaceID: String?
    public var summary: String?
    public var relatedEventIDs: [UUID]

    public init(
        id: UUID = UUID(),
        recordingTime: TimeInterval,
        kind: RecordingTimelineEventKind,
        frameID: UUID? = nil,
        videoSegmentID: UUID? = nil,
        rawEventIndex: Int? = nil,
        recordedEventIndex: Int? = nil,
        surfaceID: String? = nil,
        summary: String? = nil,
        relatedEventIDs: [UUID] = []
    ) {
        self.id = id
        self.recordingTime = max(0, recordingTime)
        self.kind = kind
        self.frameID = frameID
        self.videoSegmentID = videoSegmentID
        self.rawEventIndex = rawEventIndex
        self.recordedEventIndex = recordedEventIndex
        self.surfaceID = surfaceID
        self.summary = summary
        self.relatedEventIDs = relatedEventIDs
    }
}

public enum RecordingSemanticEventKind: String, Codable, Equatable, Sendable {
    case summary
    case macroStep
    case click
    case inputText
    case scroll
    case wait
    case observation
    case conditionCandidate
    case warning
    case marker
}

public struct RecordingSemanticEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingTime: TimeInterval
    public var kind: RecordingSemanticEventKind
    public var frameID: UUID?
    public var timelineEventID: UUID?
    public var title: String
    public var summary: String?
    public var evidenceFrameIDs: [UUID]
    public var observationIDs: [UUID]
    public var risk: String?

    public init(
        id: UUID = UUID(),
        recordingTime: TimeInterval,
        kind: RecordingSemanticEventKind,
        frameID: UUID? = nil,
        timelineEventID: UUID? = nil,
        title: String,
        summary: String? = nil,
        evidenceFrameIDs: [UUID] = [],
        observationIDs: [UUID] = [],
        risk: String? = nil
    ) {
        self.id = id
        self.recordingTime = max(0, recordingTime)
        self.kind = kind
        self.frameID = frameID
        self.timelineEventID = timelineEventID
        self.title = title
        self.summary = summary
        self.evidenceFrameIDs = evidenceFrameIDs
        self.observationIDs = observationIDs
        self.risk = risk
    }
}

public enum RecordingVisualObservationKind: String, Codable, Equatable, Sendable {
    case ocrText
    case axElement
    case windowSnapshot
    case pixelSample
    case imageTemplateCandidate
    case regionBaseline
    case regionDiff
    case patternCandidate
}

public struct RecordingVisualObservation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingVisualObservationKind
    public var recordingTime: TimeInterval
    public var frameID: UUID?
    public var sourcePreviewRefID: UUID?
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?
    public var text: String?
    public var confidence: Double?
    public var score: Double?
    public var provider: String
    public var providerVersion: String?
    public var labels: [String]
    public var metadata: [String: String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: RecordingVisualObservationKind,
        recordingTime: TimeInterval,
        frameID: UUID? = nil,
        sourcePreviewRefID: UUID? = nil,
        artifactRef: RecordingArtifactRef? = nil,
        bounds: RecordingBounds? = nil,
        text: String? = nil,
        confidence: Double? = nil,
        score: Double? = nil,
        provider: String,
        providerVersion: String? = nil,
        labels: [String] = [],
        metadata: [String: String] = [:],
        createdAt: Date = Date.now
    ) {
        self.id = id
        self.kind = kind
        self.recordingTime = max(0, recordingTime)
        self.frameID = frameID
        self.sourcePreviewRefID = sourcePreviewRefID
        self.artifactRef = artifactRef
        self.bounds = bounds
        self.text = text
        self.confidence = confidence
        self.score = score
        self.provider = provider
        self.providerVersion = providerVersion
        self.labels = labels
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public enum RecordingVisualReferenceKind: String, Codable, Equatable, Sendable {
    case ocrRegion
    case imageTemplate
    case regionBaseline
    case pixelSample
}

public struct RecordingContentDigest: Codable, Equatable, Sendable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public struct RecordingSourcePreviewReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingVisualReferenceKind
    public var recordingID: UUID?
    public var frameID: UUID?
    public var eventID: UUID?
    public var surfaceID: String?
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?
    public var imageSize: RecordingImageSize?
    public var createdAt: Date?
    public var recordingTime: TimeInterval?
    public var contentDigest: RecordingContentDigest?
    public var label: String?

    public init(
        id: UUID = UUID(),
        kind: RecordingVisualReferenceKind,
        recordingID: UUID? = nil,
        frameID: UUID? = nil,
        eventID: UUID? = nil,
        surfaceID: String? = nil,
        artifactRef: RecordingArtifactRef? = nil,
        bounds: RecordingBounds? = nil,
        imageSize: RecordingImageSize? = nil,
        createdAt: Date? = nil,
        recordingTime: TimeInterval? = nil,
        contentDigest: RecordingContentDigest? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recordingID = recordingID
        self.frameID = frameID
        self.eventID = eventID
        self.surfaceID = surfaceID
        self.artifactRef = artifactRef
        self.bounds = bounds
        self.imageSize = imageSize
        self.createdAt = createdAt
        self.recordingTime = recordingTime.map { max(0, $0) }
        self.contentDigest = contentDigest
        self.label = label
    }
}

public enum RecordingRuntimeSampleKind: String, Codable, Equatable, Sendable {
    case displaySample
    case watchedRegionCrop
    case decodedPreview
}

public struct RecordingRuntimeSampleReference: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingRuntimeSampleKind
    public var runID: UUID
    public var taskID: UUID
    public var conditionID: UUID?
    public var artifactRef: RecordingArtifactRef
    public var capturedAt: Date
    public var bounds: RecordingBounds?
    public var imageSize: RecordingImageSize?
    public var contentDigest: RecordingContentDigest?

    public init(
        id: UUID = UUID(),
        kind: RecordingRuntimeSampleKind,
        runID: UUID,
        taskID: UUID,
        conditionID: UUID? = nil,
        artifactRef: RecordingArtifactRef,
        capturedAt: Date = Date.now,
        bounds: RecordingBounds? = nil,
        imageSize: RecordingImageSize? = nil,
        contentDigest: RecordingContentDigest? = nil
    ) {
        self.id = id
        self.kind = kind
        self.runID = runID
        self.taskID = taskID
        self.conditionID = conditionID
        self.artifactRef = artifactRef
        self.capturedAt = capturedAt
        self.bounds = bounds
        self.imageSize = imageSize
        self.contentDigest = contentDigest
    }
}

public struct RecordingMatcherDescriptor: Codable, Equatable, Sendable {
    public var kind: String
    public var version: String
    public var provider: String?

    public init(kind: String, version: String, provider: String? = nil) {
        self.kind = kind
        self.version = version
        self.provider = provider
    }
}

public enum RecordingPreviewComparisonOutcome: String, Codable, Equatable, Sendable {
    case matched
    case changed
    case unchanged
    case missingSource
    case missingSample
    case unreadable
    case rejected
    case unavailable
}

public struct RecordingPreviewComparison: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourcePreviewRefID: UUID
    public var runtimeSampleRefID: UUID
    public var outcome: RecordingPreviewComparisonOutcome
    public var score: Double?
    public var threshold: Double?
    public var matcher: RecordingMatcherDescriptor
    public var diffArtifactRef: RecordingArtifactRef?
    public var reason: String?
    public var comparedAt: Date

    public init(
        id: UUID = UUID(),
        sourcePreviewRefID: UUID,
        runtimeSampleRefID: UUID,
        outcome: RecordingPreviewComparisonOutcome,
        score: Double? = nil,
        threshold: Double? = nil,
        matcher: RecordingMatcherDescriptor,
        diffArtifactRef: RecordingArtifactRef? = nil,
        reason: String? = nil,
        comparedAt: Date = Date.now
    ) {
        self.id = id
        self.sourcePreviewRefID = sourcePreviewRefID
        self.runtimeSampleRefID = runtimeSampleRefID
        self.outcome = outcome
        self.score = score
        self.threshold = threshold
        self.matcher = matcher
        self.diffArtifactRef = diffArtifactRef
        self.reason = reason
        self.comparedAt = comparedAt
    }
}

public enum RecordingSuppressionReason: String, Codable, Equatable, Sendable {
    case secureInput
    case passwordField
    case excludedApplication
    case excludedWindow
    case excludedDomain
    case privateRegion
    case oversizedArtifact
    case userDeleted
    case unknown
}

public struct RecordingSuppressionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var reason: RecordingSuppressionReason
    public var recordingTime: TimeInterval?
    public var timeRange: RecordingTimeRange?
    public var target: RecordingCaptureTarget?
    public var frameID: UUID?
    public var eventID: UUID?
    public var redactedArtifactRef: RecordingArtifactRef?
    public var count: Int
    public var detail: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        reason: RecordingSuppressionReason,
        recordingTime: TimeInterval? = nil,
        timeRange: RecordingTimeRange? = nil,
        target: RecordingCaptureTarget? = nil,
        frameID: UUID? = nil,
        eventID: UUID? = nil,
        redactedArtifactRef: RecordingArtifactRef? = nil,
        count: Int = 1,
        detail: String? = nil,
        createdAt: Date = Date.now
    ) {
        self.id = id
        self.reason = reason
        self.recordingTime = recordingTime.map { max(0, $0) }
        self.timeRange = timeRange
        self.target = target
        self.frameID = frameID
        self.eventID = eventID
        self.redactedArtifactRef = redactedArtifactRef
        self.count = max(0, count)
        self.detail = detail
        self.createdAt = createdAt
    }
}

public struct RecordingEvidenceReference: Codable, Equatable, Sendable {
    public var frameID: UUID?
    public var eventIDs: [UUID]
    public var observationIDs: [UUID]
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?
    public var summary: String?

    public init(
        frameID: UUID? = nil,
        eventIDs: [UUID] = [],
        observationIDs: [UUID] = [],
        artifactRef: RecordingArtifactRef? = nil,
        bounds: RecordingBounds? = nil,
        summary: String? = nil
    ) {
        self.frameID = frameID
        self.eventIDs = eventIDs
        self.observationIDs = observationIDs
        self.artifactRef = artifactRef
        self.bounds = bounds
        self.summary = summary
    }
}

public enum RecordingQueryResultKind: String, Codable, Equatable, Sendable {
    case frame
    case event
    case ocrText
    case pattern
    case visualReference
    case previewComparison
}

public struct RecordingQueryResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingID: UUID
    public var kind: RecordingQueryResultKind
    public var title: String
    public var summary: String?
    public var score: Double?
    public var evidence: [RecordingEvidenceReference]

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        kind: RecordingQueryResultKind,
        title: String,
        summary: String? = nil,
        score: Double? = nil,
        evidence: [RecordingEvidenceReference] = []
    ) {
        self.id = id
        self.recordingID = recordingID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.score = score
        self.evidence = evidence
    }
}

public enum RecordingSuggestionKind: String, Codable, Equatable, Sendable {
    case waitCleanup
    case locatorReplacement
    case conditionCandidate
    case visualAssetExtraction
    case fragileClick
    case draftGeneration
}

public struct RecordingSuggestion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingID: UUID
    public var kind: RecordingSuggestionKind
    public var title: String
    public var summary: String
    public var confidence: Double
    public var risk: String?
    public var evidence: [RecordingEvidenceReference]

    public init(
        id: UUID = UUID(),
        recordingID: UUID,
        kind: RecordingSuggestionKind,
        title: String,
        summary: String,
        confidence: Double,
        risk: String? = nil,
        evidence: [RecordingEvidenceReference] = []
    ) {
        self.id = id
        self.recordingID = recordingID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.confidence = min(1, max(0, confidence))
        self.risk = risk
        self.evidence = evidence
    }
}

public enum SemanticRecordingBundleIssue: Equatable, Sendable {
    case unsupportedSchemaVersion(SemanticRecordingSchemaVersion)
    case duplicateVideoSegmentID(UUID)
    case duplicateFrameID(UUID)
    case duplicateTimelineEventID(UUID)
    case duplicateSemanticEventID(UUID)
    case duplicateVisualObservationID(UUID)
    case duplicateSourcePreviewID(UUID)
    case duplicateRuntimeSampleID(UUID)
    case duplicatePreviewComparisonID(UUID)
    case duplicateSuppressionID(UUID)
    case duplicateRedactedFrameID(UUID)
    case duplicateRedactedVideoSegmentID(UUID)
    case frameReferencesMissingVideoSegment(frameID: UUID, videoSegmentID: UUID)
    case timelineEventReferencesMissingFrame(eventID: UUID, frameID: UUID)
    case timelineEventReferencesMissingVideoSegment(eventID: UUID, videoSegmentID: UUID)
    case semanticEventReferencesMissingFrame(eventID: UUID, frameID: UUID)
    case semanticEventReferencesMissingTimelineEvent(eventID: UUID, timelineEventID: UUID)
    case semanticEventReferencesMissingObservation(eventID: UUID, observationID: UUID)
    case visualObservationReferencesMissingFrame(observationID: UUID, frameID: UUID)
    case visualObservationReferencesMissingSourcePreview(observationID: UUID, sourcePreviewRefID: UUID)
    case sourcePreviewReferencesMissingFrame(refID: UUID, frameID: UUID)
    case sourcePreviewReferencesMissingTimelineEvent(refID: UUID, eventID: UUID)
    case comparisonReferencesMissingSource(comparisonID: UUID, sourcePreviewRefID: UUID)
    case comparisonReferencesMissingSample(comparisonID: UUID, runtimeSampleRefID: UUID)
    case suppressionReferencesMissingFrame(suppressionID: UUID, frameID: UUID)
    case suppressionReferencesMissingTimelineEvent(suppressionID: UUID, eventID: UUID)
    case redactedFrameReferencesMissingFrame(frameID: UUID)
    case redactedFrameReferencesMissingSuppression(frameID: UUID, suppressionID: UUID)
    case redactedVideoReferencesMissingVideoSegment(videoSegmentID: UUID)
    case redactedVideoReferencesMissingSuppression(videoSegmentID: UUID, suppressionID: UUID)
}

public struct SemanticRecordingBundle: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var schemaVersion: SemanticRecordingSchemaVersion
    public var createdAt: Date
    public var capturePolicy: RecordingCapturePolicy
    public var captureTarget: RecordingCaptureTarget?
    public var videoSegments: [RecordingVideoSegment]
    public var frames: [RecordingFrameReference]
    public var timelineEvents: [RecordingTimelineEvent]
    public var semanticEvents: [RecordingSemanticEvent]
    public var visualObservations: [RecordingVisualObservation]
    public var sourcePreviews: [RecordingSourcePreviewReference]
    public var runtimeSamples: [RecordingRuntimeSampleReference]
    public var previewComparisons: [RecordingPreviewComparison]
    public var suppressions: [RecordingSuppressionRecord]
    public var redactedFrames: [SemanticRecordingRenderedFrameRedaction]
    public var redactedVideos: [SemanticRecordingRenderedVideoRedaction]

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case createdAt
        case capturePolicy
        case captureTarget
        case videoSegments
        case frames
        case timelineEvents
        case semanticEvents
        case visualObservations
        case sourcePreviews
        case runtimeSamples
        case previewComparisons
        case suppressions
        case redactedFrames
        case redactedVideos
    }

    public init(
        id: UUID = UUID(),
        schemaVersion: SemanticRecordingSchemaVersion = SemanticRecordingSchema.current,
        createdAt: Date = Date.now,
        capturePolicy: RecordingCapturePolicy = RecordingCapturePolicy(),
        captureTarget: RecordingCaptureTarget? = nil,
        videoSegments: [RecordingVideoSegment] = [],
        frames: [RecordingFrameReference] = [],
        timelineEvents: [RecordingTimelineEvent] = [],
        semanticEvents: [RecordingSemanticEvent] = [],
        visualObservations: [RecordingVisualObservation] = [],
        sourcePreviews: [RecordingSourcePreviewReference] = [],
        runtimeSamples: [RecordingRuntimeSampleReference] = [],
        previewComparisons: [RecordingPreviewComparison] = [],
        suppressions: [RecordingSuppressionRecord] = [],
        redactedFrames: [SemanticRecordingRenderedFrameRedaction] = [],
        redactedVideos: [SemanticRecordingRenderedVideoRedaction] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.capturePolicy = capturePolicy
        self.captureTarget = captureTarget
        self.videoSegments = videoSegments
        self.frames = frames
        self.timelineEvents = timelineEvents
        self.semanticEvents = semanticEvents
        self.visualObservations = visualObservations
        self.sourcePreviews = sourcePreviews
        self.runtimeSamples = runtimeSamples
        self.previewComparisons = previewComparisons
        self.suppressions = suppressions
        self.redactedFrames = redactedFrames
        self.redactedVideos = redactedVideos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.schemaVersion = try container.decodeIfPresent(
            SemanticRecordingSchemaVersion.self,
            forKey: .schemaVersion
        ) ?? SemanticRecordingSchema.current
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.capturePolicy = try container.decodeIfPresent(
            RecordingCapturePolicy.self,
            forKey: .capturePolicy
        ) ?? RecordingCapturePolicy()
        self.captureTarget = try container.decodeIfPresent(
            RecordingCaptureTarget.self,
            forKey: .captureTarget
        )
        self.videoSegments = try container.decodeIfPresent(
            [RecordingVideoSegment].self,
            forKey: .videoSegments
        ) ?? []
        self.frames = try container.decodeIfPresent(
            [RecordingFrameReference].self,
            forKey: .frames
        ) ?? []
        self.timelineEvents = try container.decodeIfPresent(
            [RecordingTimelineEvent].self,
            forKey: .timelineEvents
        ) ?? []
        self.semanticEvents = try container.decodeIfPresent(
            [RecordingSemanticEvent].self,
            forKey: .semanticEvents
        ) ?? []
        self.visualObservations = try container.decodeIfPresent(
            [RecordingVisualObservation].self,
            forKey: .visualObservations
        ) ?? []
        self.sourcePreviews = try container.decodeIfPresent(
            [RecordingSourcePreviewReference].self,
            forKey: .sourcePreviews
        ) ?? []
        self.runtimeSamples = try container.decodeIfPresent(
            [RecordingRuntimeSampleReference].self,
            forKey: .runtimeSamples
        ) ?? []
        self.previewComparisons = try container.decodeIfPresent(
            [RecordingPreviewComparison].self,
            forKey: .previewComparisons
        ) ?? []
        self.suppressions = try container.decodeIfPresent(
            [RecordingSuppressionRecord].self,
            forKey: .suppressions
        ) ?? []
        self.redactedFrames = try container.decodeIfPresent(
            [SemanticRecordingRenderedFrameRedaction].self,
            forKey: .redactedFrames
        ) ?? []
        self.redactedVideos = try container.decodeIfPresent(
            [SemanticRecordingRenderedVideoRedaction].self,
            forKey: .redactedVideos
        ) ?? []
    }

    public var aiSafeEvents: [RecordingSemanticEvent] {
        semanticEvents
    }

    public func videoSegment(containing recordingTime: TimeInterval) -> RecordingVideoSegment? {
        videoSegments.first { $0.contains(recordingTime) }
    }

    public func nearestFrame(
        to recordingTime: TimeInterval,
        within tolerance: TimeInterval? = nil
    ) -> RecordingFrameReference? {
        let candidate = frames.min { left, right in
            abs(left.recordingTime - recordingTime) < abs(right.recordingTime - recordingTime)
        }
        guard let candidate else {
            return nil
        }
        if let tolerance, abs(candidate.recordingTime - recordingTime) > max(0, tolerance) {
            return nil
        }
        return candidate
    }

    public func frames(relatedToEventID eventID: UUID) -> [RecordingFrameReference] {
        frames.filter { $0.relatedEventIDs.contains(eventID) }
    }

    public func observations(frameID: UUID) -> [RecordingVisualObservation] {
        visualObservations.filter { $0.frameID == frameID }
    }

    public func redactedFrame(frameID: UUID) -> SemanticRecordingRenderedFrameRedaction? {
        redactedFrames.first { $0.frameID == frameID }
    }

    public func redactedVideo(
        videoSegmentID: UUID
    ) -> SemanticRecordingRenderedVideoRedaction? {
        redactedVideos.first { $0.videoSegmentID == videoSegmentID }
    }

    public func preferredImageRef(
        for frame: RecordingFrameReference
    ) -> RecordingArtifactRef {
        redactedFrame(frameID: frame.id)?.redactedImageRef ?? frame.imageRef
    }

    public func previewComparisons(sourcePreviewRefID: UUID) -> [RecordingPreviewComparison] {
        previewComparisons.filter { $0.sourcePreviewRefID == sourcePreviewRefID }
    }

    public func validate() -> [SemanticRecordingBundleIssue] {
        var issues: [SemanticRecordingBundleIssue] = []
        if !schemaVersion.isSupportedByCurrentApp {
            issues.append(.unsupportedSchemaVersion(schemaVersion))
        }

        let videoSegmentIDs = Set(videoSegments.map(\.id))
        let frameIDs = Set(frames.map(\.id))
        let timelineEventIDs = Set(timelineEvents.map(\.id))
        let visualObservationIDs = Set(visualObservations.map(\.id))
        let sourcePreviewIDs = Set(sourcePreviews.map(\.id))
        let runtimeSampleIDs = Set(runtimeSamples.map(\.id))
        let suppressionIDs = Set(suppressions.map(\.id))

        issues.append(
            contentsOf: Self.duplicateIssues(
                videoSegments.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateVideoSegmentID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                frames.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateFrameID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                timelineEvents.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateTimelineEventID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                semanticEvents.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateSemanticEventID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                visualObservations.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateVisualObservationID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                sourcePreviews.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateSourcePreviewID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                runtimeSamples.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateRuntimeSampleID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                previewComparisons.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicatePreviewComparisonID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                suppressions.map(\.id),
                issue: SemanticRecordingBundleIssue.duplicateSuppressionID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                redactedFrames.map(\.frameID),
                issue: SemanticRecordingBundleIssue.duplicateRedactedFrameID
            )
        )
        issues.append(
            contentsOf: Self.duplicateIssues(
                redactedVideos.map(\.videoSegmentID),
                issue: SemanticRecordingBundleIssue.duplicateRedactedVideoSegmentID
            )
        )

        for frame in frames {
            if let videoSegmentID = frame.videoSegmentID, !videoSegmentIDs.contains(videoSegmentID) {
                issues.append(
                    .frameReferencesMissingVideoSegment(
                        frameID: frame.id,
                        videoSegmentID: videoSegmentID
                    )
                )
            }
        }

        for event in timelineEvents {
            if let frameID = event.frameID, !frameIDs.contains(frameID) {
                issues.append(.timelineEventReferencesMissingFrame(eventID: event.id, frameID: frameID))
            }
            if let videoSegmentID = event.videoSegmentID, !videoSegmentIDs.contains(videoSegmentID) {
                issues.append(
                    .timelineEventReferencesMissingVideoSegment(
                        eventID: event.id,
                        videoSegmentID: videoSegmentID
                    )
                )
            }
        }

        for event in semanticEvents {
            if let frameID = event.frameID, !frameIDs.contains(frameID) {
                issues.append(.semanticEventReferencesMissingFrame(eventID: event.id, frameID: frameID))
            }
            if let timelineEventID = event.timelineEventID, !timelineEventIDs.contains(timelineEventID) {
                issues.append(
                    .semanticEventReferencesMissingTimelineEvent(
                        eventID: event.id,
                        timelineEventID: timelineEventID
                    )
                )
            }
            for observationID in event.observationIDs where !visualObservationIDs.contains(observationID) {
                issues.append(
                    .semanticEventReferencesMissingObservation(
                        eventID: event.id,
                        observationID: observationID
                    )
                )
            }
        }

        for observation in visualObservations {
            if let frameID = observation.frameID, !frameIDs.contains(frameID) {
                issues.append(
                    .visualObservationReferencesMissingFrame(
                        observationID: observation.id,
                        frameID: frameID
                    )
                )
            }
            if let sourcePreviewRefID = observation.sourcePreviewRefID,
               !sourcePreviewIDs.contains(sourcePreviewRefID) {
                issues.append(
                    .visualObservationReferencesMissingSourcePreview(
                        observationID: observation.id,
                        sourcePreviewRefID: sourcePreviewRefID
                    )
                )
            }
        }

        for sourcePreview in sourcePreviews {
            if let frameID = sourcePreview.frameID, !frameIDs.contains(frameID) {
                issues.append(
                    .sourcePreviewReferencesMissingFrame(
                        refID: sourcePreview.id,
                        frameID: frameID
                    )
                )
            }
            if let eventID = sourcePreview.eventID, !timelineEventIDs.contains(eventID) {
                issues.append(
                    .sourcePreviewReferencesMissingTimelineEvent(
                        refID: sourcePreview.id,
                        eventID: eventID
                    )
                )
            }
        }

        for comparison in previewComparisons {
            if !sourcePreviewIDs.contains(comparison.sourcePreviewRefID) {
                issues.append(
                    .comparisonReferencesMissingSource(
                        comparisonID: comparison.id,
                        sourcePreviewRefID: comparison.sourcePreviewRefID
                    )
                )
            }
            if !runtimeSampleIDs.contains(comparison.runtimeSampleRefID) {
                issues.append(
                    .comparisonReferencesMissingSample(
                        comparisonID: comparison.id,
                        runtimeSampleRefID: comparison.runtimeSampleRefID
                    )
                )
            }
        }

        for suppression in suppressions {
            if let frameID = suppression.frameID, !frameIDs.contains(frameID) {
                issues.append(
                    .suppressionReferencesMissingFrame(
                        suppressionID: suppression.id,
                        frameID: frameID
                    )
                )
            }
            if let eventID = suppression.eventID, !timelineEventIDs.contains(eventID) {
                issues.append(
                    .suppressionReferencesMissingTimelineEvent(
                        suppressionID: suppression.id,
                        eventID: eventID
                    )
                )
            }
        }

        for redactedFrame in redactedFrames {
            if !frameIDs.contains(redactedFrame.frameID) {
                issues.append(
                    .redactedFrameReferencesMissingFrame(frameID: redactedFrame.frameID)
                )
            }
            for suppressionID in redactedFrame.sourceSuppressionIDs
                where !suppressionIDs.contains(suppressionID) {
                issues.append(
                    .redactedFrameReferencesMissingSuppression(
                        frameID: redactedFrame.frameID,
                        suppressionID: suppressionID
                    )
                )
            }
        }

        for redactedVideo in redactedVideos {
            if !videoSegmentIDs.contains(redactedVideo.videoSegmentID) {
                issues.append(
                    .redactedVideoReferencesMissingVideoSegment(
                        videoSegmentID: redactedVideo.videoSegmentID
                    )
                )
            }
            for suppressionID in redactedVideo.sourceSuppressionIDs
                where !suppressionIDs.contains(suppressionID) {
                issues.append(
                    .redactedVideoReferencesMissingSuppression(
                        videoSegmentID: redactedVideo.videoSegmentID,
                        suppressionID: suppressionID
                    )
                )
            }
        }

        return issues
    }

    private static func duplicateIssues(
        _ ids: [UUID],
        issue: (UUID) -> SemanticRecordingBundleIssue
    ) -> [SemanticRecordingBundleIssue] {
        var seen = Set<UUID>()
        var emitted = Set<UUID>()
        var issues: [SemanticRecordingBundleIssue] = []
        for id in ids where !seen.insert(id).inserted && emitted.insert(id).inserted {
            issues.append(issue(id))
        }
        return issues
    }
}

public struct SemanticRecordingBundleSidecars: Equatable, Sendable {
    public var videoSegments: [RecordingVideoSegment]?
    public var frames: [RecordingFrameReference]?
    public var timelineEvents: [RecordingTimelineEvent]?
    public var semanticEvents: [RecordingSemanticEvent]?
    public var visualObservations: [RecordingVisualObservation]?
    public var sourcePreviews: [RecordingSourcePreviewReference]?
    public var runtimeSamples: [RecordingRuntimeSampleReference]?
    public var previewComparisons: [RecordingPreviewComparison]?
    public var suppressions: [RecordingSuppressionRecord]?
    public var redactedFrames: [SemanticRecordingRenderedFrameRedaction]?
    public var redactedVideos: [SemanticRecordingRenderedVideoRedaction]?

    public init(
        videoSegments: [RecordingVideoSegment]? = nil,
        frames: [RecordingFrameReference]? = nil,
        timelineEvents: [RecordingTimelineEvent]? = nil,
        semanticEvents: [RecordingSemanticEvent]? = nil,
        visualObservations: [RecordingVisualObservation]? = nil,
        sourcePreviews: [RecordingSourcePreviewReference]? = nil,
        runtimeSamples: [RecordingRuntimeSampleReference]? = nil,
        previewComparisons: [RecordingPreviewComparison]? = nil,
        suppressions: [RecordingSuppressionRecord]? = nil,
        redactedFrames: [SemanticRecordingRenderedFrameRedaction]? = nil,
        redactedVideos: [SemanticRecordingRenderedVideoRedaction]? = nil
    ) {
        self.videoSegments = videoSegments
        self.frames = frames
        self.timelineEvents = timelineEvents
        self.semanticEvents = semanticEvents
        self.visualObservations = visualObservations
        self.sourcePreviews = sourcePreviews
        self.runtimeSamples = runtimeSamples
        self.previewComparisons = previewComparisons
        self.suppressions = suppressions
        self.redactedFrames = redactedFrames
        self.redactedVideos = redactedVideos
    }
}

public enum SemanticRecordingBundleSidecarKind: String, Codable, Equatable, Sendable, CaseIterable {
    case videoSegments
    case frames
    case timelineEvents
    case semanticEvents
    case visualObservations
    case suppressions
    case redactedFrames
    case redactedVideos
}

public struct SemanticRecordingBundleSidecarLoadIssue: Codable, Equatable, Sendable {
    public var kind: SemanticRecordingBundleSidecarKind
    public var relativePath: String
    public var message: String
    public var fallbackToManifest: Bool

    public init(
        kind: SemanticRecordingBundleSidecarKind,
        relativePath: String,
        message: String,
        fallbackToManifest: Bool = true
    ) {
        self.kind = kind
        self.relativePath = relativePath
        self.message = message
        self.fallbackToManifest = fallbackToManifest
    }
}

public struct SemanticRecordingBundleSidecarLoadDiagnostics: Codable, Equatable, Sendable {
    public var loadedKinds: [SemanticRecordingBundleSidecarKind]
    public var missingKinds: [SemanticRecordingBundleSidecarKind]
    public var failedIssues: [SemanticRecordingBundleSidecarLoadIssue]

    public init(
        loadedKinds: [SemanticRecordingBundleSidecarKind] = [],
        missingKinds: [SemanticRecordingBundleSidecarKind] = [],
        failedIssues: [SemanticRecordingBundleSidecarLoadIssue] = []
    ) {
        self.loadedKinds = Self.unique(loadedKinds)
        self.missingKinds = Self.unique(missingKinds)
        self.failedIssues = failedIssues
    }

    public var isDegraded: Bool {
        !failedIssues.isEmpty
    }

    public mutating func recordLoaded(_ kind: SemanticRecordingBundleSidecarKind) {
        Self.appendUnique(kind, to: &loadedKinds)
    }

    public mutating func recordMissing(_ kind: SemanticRecordingBundleSidecarKind) {
        Self.appendUnique(kind, to: &missingKinds)
    }

    public mutating func recordFailed(
        _ kind: SemanticRecordingBundleSidecarKind,
        relativePath: String,
        message: String,
        fallbackToManifest: Bool = true
    ) {
        failedIssues.append(
            SemanticRecordingBundleSidecarLoadIssue(
                kind: kind,
                relativePath: relativePath,
                message: message,
                fallbackToManifest: fallbackToManifest
            )
        )
    }

    private static func appendUnique(
        _ kind: SemanticRecordingBundleSidecarKind,
        to kinds: inout [SemanticRecordingBundleSidecarKind]
    ) {
        guard !kinds.contains(kind) else { return }
        kinds.append(kind)
    }

    private static func unique(
        _ kinds: [SemanticRecordingBundleSidecarKind]
    ) -> [SemanticRecordingBundleSidecarKind] {
        var result: [SemanticRecordingBundleSidecarKind] = []
        for kind in kinds where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
}

public struct SemanticRecordingBundleLoadResult: Codable, Equatable, Sendable {
    public var bundle: SemanticRecordingBundle
    public var sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics

    public init(
        manifest: SemanticRecordingBundle,
        sidecars: SemanticRecordingBundleSidecars = SemanticRecordingBundleSidecars(),
        sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics = SemanticRecordingBundleSidecarLoadDiagnostics()
    ) {
        self.bundle = manifest.applyingSidecars(sidecars)
        self.sidecarDiagnostics = sidecarDiagnostics
    }
}

public extension SemanticRecordingBundle {
    func applyingSidecars(_ sidecars: SemanticRecordingBundleSidecars) -> SemanticRecordingBundle {
        SemanticRecordingBundle(
            id: id,
            schemaVersion: schemaVersion,
            createdAt: createdAt,
            capturePolicy: capturePolicy,
            captureTarget: captureTarget,
            videoSegments: sidecars.videoSegments ?? videoSegments,
            frames: sidecars.frames ?? frames,
            timelineEvents: sidecars.timelineEvents ?? timelineEvents,
            semanticEvents: sidecars.semanticEvents ?? semanticEvents,
            visualObservations: sidecars.visualObservations ?? visualObservations,
            sourcePreviews: sidecars.sourcePreviews ?? sourcePreviews,
            runtimeSamples: sidecars.runtimeSamples ?? runtimeSamples,
            previewComparisons: sidecars.previewComparisons ?? previewComparisons,
            suppressions: sidecars.suppressions ?? suppressions,
            redactedFrames: sidecars.redactedFrames ?? redactedFrames,
            redactedVideos: sidecars.redactedVideos ?? redactedVideos
        )
    }
}

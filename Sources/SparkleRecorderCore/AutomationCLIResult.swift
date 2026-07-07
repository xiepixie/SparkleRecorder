import Foundation

public enum AutomationCLIResultSchema {
    public static let current = "sparkle.cli.result.v1"
}

public struct AutomationCLIMessage: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var path: String?
    public var taskKey: String?
    public var dependencyKey: String?
    public var candidates: [UUID]

    public init(
        code: String,
        message: String,
        path: String? = nil,
        taskKey: String? = nil,
        dependencyKey: String? = nil,
        candidates: [UUID] = []
    ) {
        self.code = code
        self.message = message
        self.path = path
        self.taskKey = taskKey
        self.dependencyKey = dependencyKey
        self.candidates = candidates
    }

    public init(issue: AutomationWorkflowDraftIssue) {
        self.init(
            code: issue.code.rawValue,
            message: issue.message,
            path: issue.path,
            taskKey: issue.taskKey,
            dependencyKey: issue.dependencyKey,
            candidates: issue.candidates
        )
    }
}

public struct AutomationCLINextAction: Codable, Equatable, Sendable {
    public var command: String
    public var reason: String

    public init(command: String, reason: String) {
        self.command = command
        self.reason = reason
    }
}

public struct AutomationCLIResultEnvelope<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var ok: Bool
    public var schema: String
    public var command: String
    public var data: Value?
    public var warnings: [AutomationCLIMessage]
    public var errors: [AutomationCLIMessage]
    public var nextActions: [AutomationCLINextAction]

    public init(
        ok: Bool,
        schema: String = AutomationCLIResultSchema.current,
        command: String,
        data: Value?,
        warnings: [AutomationCLIMessage] = [],
        errors: [AutomationCLIMessage] = [],
        nextActions: [AutomationCLINextAction] = []
    ) {
        self.ok = ok
        self.schema = schema
        self.command = command
        self.data = data
        self.warnings = warnings
        self.errors = errors
        self.nextActions = nextActions
    }
}

public struct AutomationCLIEmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

public enum SemanticRecordingCLICatalogSource: String, Codable, Equatable, Sendable {
    case fixture
    case storedBundle
}

public struct SemanticRecordingCLICatalogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { recordingID }
    public var recordingID: UUID
    public var source: SemanticRecordingCLICatalogSource
    public var fixture: String?
    public var modifiedAt: Date?
    public var manifestAvailable: Bool

    public init(
        recordingID: UUID,
        source: SemanticRecordingCLICatalogSource,
        fixture: String? = nil,
        modifiedAt: Date? = nil,
        manifestAvailable: Bool = true
    ) {
        self.recordingID = recordingID
        self.source = source
        self.fixture = fixture
        self.modifiedAt = modifiedAt
        self.manifestAvailable = manifestAvailable
    }
}

public struct SemanticRecordingCLIListPayload: Codable, Equatable, Sendable {
    public var fixtureMode: Bool
    public var fixture: String?
    public var recordingsRoot: String?
    public var count: Int
    public var recordings: [SemanticRecordingCLICatalogEntry]

    public init(
        recordings: [SemanticRecordingCLICatalogEntry],
        fixture: String? = nil,
        recordingsRoot: String? = nil
    ) {
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.recordingsRoot = recordingsRoot
        self.count = recordings.count
        self.recordings = recordings
    }
}

public struct SemanticRecordingCLICaptureTargetSummary: Codable, Equatable, Sendable {
    public var kind: RecordingCaptureTargetKind
    public var surfaceID: String?
    public var displayID: UInt32?
    public var windowID: UInt32?
    public var appBundleIdentifier: String?
    public var appName: String?
    public var windowTitle: String?

    public init(target: RecordingCaptureTarget) {
        self.kind = target.kind
        self.surfaceID = target.surfaceID
        self.displayID = target.displayID
        self.windowID = target.windowID
        self.appBundleIdentifier = target.appBundleIdentifier
        self.appName = target.appName
        self.windowTitle = target.windowTitle
    }
}

public struct SemanticRecordingCLISuppressionReasonCount: Codable, Equatable, Sendable {
    public var reason: RecordingSuppressionReason
    public var count: Int

    public init(reason: RecordingSuppressionReason, count: Int) {
        self.reason = reason
        self.count = count
    }
}

public struct SemanticRecordingCLISuppressionSummary: Codable, Equatable, Sendable {
    public var recordCount: Int
    public var totalSuppressedCount: Int
    public var reasons: [SemanticRecordingCLISuppressionReasonCount]

    public init(records: [RecordingSuppressionRecord]) {
        self.recordCount = records.count
        self.totalSuppressedCount = records.reduce(0) { total, record in
            total + record.count
        }
        let reasonCounts = Dictionary(grouping: records, by: \.reason)
            .map { reason, records in
                SemanticRecordingCLISuppressionReasonCount(
                    reason: reason,
                    count: records.reduce(0) { total, record in total + record.count }
                )
            }
            .sorted { $0.reason.rawValue < $1.reason.rawValue }
        self.reasons = reasonCounts
    }
}

public struct SemanticRecordingCLIArtifactAvailability: Codable, Equatable, Sendable {
    public var videoRefs: [RecordingArtifactRef]
    public var redactedVideoRefs: [RecordingArtifactRef]
    public var frameRefs: [RecordingArtifactRef]
    public var redactedFrameRefs: [RecordingArtifactRef]
    public var sourcePreviewRefs: [RecordingArtifactRef]
    public var runtimeSampleRefs: [RecordingArtifactRef]
    public var diffRefs: [RecordingArtifactRef]

    public init(bundle: SemanticRecordingBundle) {
        self.videoRefs = bundle.videoSegments.map(\.artifactRef)
        self.redactedVideoRefs = bundle.redactedVideos.map(\.redactedVideoRef)
        self.frameRefs = bundle.frames.map(\.imageRef)
        self.redactedFrameRefs = bundle.redactedFrames.map(\.redactedImageRef)
        self.sourcePreviewRefs = bundle.sourcePreviews.compactMap(\.artifactRef)
        self.runtimeSampleRefs = bundle.runtimeSamples.map(\.artifactRef)
        self.diffRefs = bundle.previewComparisons.compactMap(\.diffArtifactRef)
    }
}

public enum SemanticRecordingCLIArtifactFileKind: String, Codable, Equatable, Sendable {
    case video
    case redactedVideo
    case frame
    case redactedFrame
    case visualObservation
    case sourcePreview
    case runtimeSample
    case diff
}

public enum SemanticRecordingCLIArtifactFileStatus: String, Codable, Equatable, Sendable {
    case present
    case missing
    case deleted
    case empty
    case directory
    case unsafe
}

public struct SemanticRecordingCLIArtifactFileEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(kind.rawValue):\(ref.path)" }
    public var kind: SemanticRecordingCLIArtifactFileKind
    public var ref: RecordingArtifactRef
    public var status: SemanticRecordingCLIArtifactFileStatus
    public var byteCount: Int?
    public var reason: String?

    public init(
        kind: SemanticRecordingCLIArtifactFileKind,
        ref: RecordingArtifactRef,
        status: SemanticRecordingCLIArtifactFileStatus,
        byteCount: Int? = nil,
        reason: String? = nil
    ) {
        self.kind = kind
        self.ref = ref
        self.status = status
        self.byteCount = byteCount
        self.reason = reason
    }
}

public struct SemanticRecordingCLIArtifactFileSummary: Codable, Equatable, Sendable {
    public var checkedCount: Int
    public var presentCount: Int
    public var missingCount: Int
    public var deletedCount: Int
    public var emptyCount: Int
    public var directoryCount: Int
    public var unsafeCount: Int
    public var videoPresentCount: Int
    public var framePresentCount: Int
    public var evidence: [SemanticRecordingCLIArtifactFileEvidence]

    public init(
        evidence: [SemanticRecordingCLIArtifactFileEvidence]
    ) {
        self.checkedCount = evidence.count
        self.presentCount = evidence.filter { $0.status == .present }.count
        self.missingCount = evidence.filter { $0.status == .missing }.count
        self.deletedCount = evidence.filter { $0.status == .deleted }.count
        self.emptyCount = evidence.filter { $0.status == .empty }.count
        self.directoryCount = evidence.filter { $0.status == .directory }.count
        self.unsafeCount = evidence.filter { $0.status == .unsafe }.count
        self.videoPresentCount = evidence.filter {
            ($0.kind == .video || $0.kind == .redactedVideo) && $0.status == .present
        }.count
        self.framePresentCount = evidence.filter {
            ($0.kind == .frame || $0.kind == .redactedFrame) && $0.status == .present
        }.count
        self.evidence = evidence
    }

    public var hasIssues: Bool {
        missingCount > 0 || deletedCount > 0 || emptyCount > 0 || directoryCount > 0 || unsafeCount > 0
    }
}

public struct SemanticRecordingCLIFrameSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingTime: TimeInterval
    public var videoSegmentID: UUID?
    public var videoTime: TimeInterval?
    public var source: RecordingFrameCaptureSource
    public var surfaceID: String?
    public var relatedEventIDs: [UUID]
    public var imageRef: RecordingArtifactRef
    public var effectiveImageRef: RecordingArtifactRef
    public var redactedImageRef: RecordingArtifactRef?
    public var imageSize: RecordingImageSize?
    public var observationIDs: [UUID]

    public init(
        frame: RecordingFrameReference,
        redactedFrame: SemanticRecordingRenderedFrameRedaction? = nil,
        observationIDs: [UUID] = []
    ) {
        self.id = frame.id
        self.recordingTime = frame.recordingTime
        self.videoSegmentID = frame.videoSegmentID
        self.videoTime = frame.videoTime
        self.source = frame.source
        self.surfaceID = frame.surfaceID
        self.relatedEventIDs = frame.relatedEventIDs
        self.imageRef = frame.imageRef
        self.effectiveImageRef = redactedFrame?.redactedImageRef ?? frame.imageRef
        self.redactedImageRef = redactedFrame?.redactedImageRef
        self.imageSize = frame.imageSize
        self.observationIDs = observationIDs
    }
}

public struct SemanticRecordingCLIEventSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recordingTime: TimeInterval
    public var kind: RecordingTimelineEventKind
    public var frameID: UUID?
    public var videoSegmentID: UUID?
    public var surfaceID: String?
    public var summary: String?
    public var relatedEventIDs: [UUID]
    public var relatedFrameIDs: [UUID]

    public init(
        event: RecordingTimelineEvent,
        relatedFrameIDs: [UUID] = []
    ) {
        self.id = event.id
        self.recordingTime = event.recordingTime
        self.kind = event.kind
        self.frameID = event.frameID
        self.videoSegmentID = event.videoSegmentID
        self.surfaceID = event.surfaceID
        self.summary = event.summary
        self.relatedEventIDs = event.relatedEventIDs
        self.relatedFrameIDs = relatedFrameIDs
    }
}

public struct SemanticRecordingCLISummaryPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var schemaVersion: SemanticRecordingSchemaVersion
    public var createdAt: Date
    public var captureMode: RecordingCaptureMode
    public var captureTarget: SemanticRecordingCLICaptureTargetSummary?
    public var videoSegmentCount: Int
    public var frameCount: Int
    public var timelineEventCount: Int
    public var aiSafeEventCount: Int
    public var visualObservationCount: Int
    public var ocrObservationCount: Int
    public var sourcePreviewCount: Int
    public var runtimeSampleCount: Int
    public var previewComparisonCount: Int
    public var videoAvailable: Bool
    public var keyframesAvailable: Bool
    public var suppressionSummary: SemanticRecordingCLISuppressionSummary
    public var artifactAvailability: SemanticRecordingCLIArtifactAvailability

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.schemaVersion = bundle.schemaVersion
        self.createdAt = bundle.createdAt
        self.captureMode = bundle.capturePolicy.mode
        self.captureTarget = bundle.captureTarget.map(SemanticRecordingCLICaptureTargetSummary.init(target:))
        self.videoSegmentCount = bundle.videoSegments.count
        self.frameCount = bundle.frames.count
        self.timelineEventCount = bundle.timelineEvents.count
        self.aiSafeEventCount = bundle.aiSafeEvents.count
        self.visualObservationCount = bundle.visualObservations.count
        self.ocrObservationCount = bundle.visualObservations.filter { $0.kind == .ocrText }.count
        self.sourcePreviewCount = bundle.sourcePreviews.count
        self.runtimeSampleCount = bundle.runtimeSamples.count
        self.previewComparisonCount = bundle.previewComparisons.count
        self.videoAvailable = !bundle.videoSegments.isEmpty
        self.keyframesAvailable = !bundle.frames.isEmpty
        self.suppressionSummary = SemanticRecordingCLISuppressionSummary(records: bundle.suppressions)
        self.artifactAvailability = SemanticRecordingCLIArtifactAvailability(bundle: bundle)
    }
}

public struct SemanticRecordingCLIReadinessPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var sourceOption: String?
    public var bundleDirectory: String?
    public var load: SemanticRecordingDebugSmokePersistedBundleLoadEvidence
    public var readiness: SemanticRecordingBundleReadiness
    public var status: SemanticRecordingBundleReadinessStatus
    public var issueCount: Int
    public var blockingIssueCount: Int
    public var degradedIssueCount: Int
    public var followUps: [String]
    public var artifactAvailability: SemanticRecordingCLIArtifactAvailability
    public var artifactFiles: SemanticRecordingCLIArtifactFileSummary?

    public init(
        requestedRecordingID: String,
        loadResult: SemanticRecordingBundleLoadResult,
        readiness: SemanticRecordingBundleReadiness,
        fixture: String? = nil,
        sourceOption: String? = nil,
        bundleDirectory: String? = nil,
        followUps: [String] = [],
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.recordingID = loadResult.bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.sourceOption = sourceOption
        self.bundleDirectory = bundleDirectory
        self.load = SemanticRecordingDebugSmokePersistedBundleLoadEvidence(loadResult: loadResult)
        self.readiness = readiness
        self.status = readiness.status
        self.issueCount = readiness.issues.count
        self.blockingIssueCount = readiness.blockingIssueCount
        self.degradedIssueCount = readiness.degradedIssueCount
        self.followUps = followUps
        self.artifactAvailability = SemanticRecordingCLIArtifactAvailability(bundle: loadResult.bundle)
        self.artifactFiles = artifactFiles
    }
}

public enum SemanticRecordingCLIMacroLinkStatus: String, Codable, Equatable, Sendable {
    case unlinked
    case ready
    case degraded
    case notReady
    case failedToLoad
}

public struct SemanticRecordingCLIMacroLinkEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { macroID }
    public var macroID: UUID
    public var macroName: String
    public var macroEventCount: Int
    public var recordingReference: MacroSemanticRecordingReference?
    public var recordingID: UUID?
    public var bundleDirectory: String?
    public var status: SemanticRecordingCLIMacroLinkStatus
    public var issues: [String]
    public var load: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    public var readiness: SemanticRecordingBundleReadiness?
    public var readinessStatus: SemanticRecordingBundleReadinessStatus?
    public var artifactAvailability: SemanticRecordingCLIArtifactAvailability?
    public var artifactFiles: SemanticRecordingCLIArtifactFileSummary?

    public init(
        macro: SavedMacro,
        bundleDirectory: String? = nil,
        loadResult: SemanticRecordingBundleLoadResult? = nil,
        readiness: SemanticRecordingBundleReadiness? = nil,
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil,
        issues: [String] = [],
        status: SemanticRecordingCLIMacroLinkStatus? = nil
    ) {
        self.macroID = macro.id
        self.macroName = macro.name
        self.macroEventCount = macro.eventCount
        self.recordingReference = macro.semanticRecording
        self.recordingID = macro.semanticRecording?.recordingID ?? loadResult?.bundle.id
        self.bundleDirectory = bundleDirectory
        self.issues = issues
        self.load = loadResult.map(SemanticRecordingDebugSmokePersistedBundleLoadEvidence.init(loadResult:))
        self.readiness = readiness
        self.readinessStatus = readiness?.status
        self.artifactAvailability = loadResult.map { SemanticRecordingCLIArtifactAvailability(bundle: $0.bundle) }
        self.artifactFiles = artifactFiles

        if let status {
            self.status = status
        } else if macro.semanticRecording == nil {
            self.status = .unlinked
        } else if loadResult == nil {
            self.status = .failedToLoad
        } else {
            switch readiness?.status {
            case .ready:
                self.status = .ready
            case .degraded:
                self.status = .degraded
            case .notReady:
                self.status = .notReady
            case nil:
                self.status = .failedToLoad
            }
        }
    }
}

public struct SemanticRecordingCLIMacroLinksPayload: Codable, Equatable, Sendable {
    public var macrosRoot: String?
    public var recordingsRoot: String
    public var totalMacroCount: Int
    public var linkedMacroCount: Int
    public var returnedCount: Int
    public var readyCount: Int
    public var degradedCount: Int
    public var notReadyCount: Int
    public var failedCount: Int
    public var unlinkedCount: Int
    public var requiresOCRObservations: Bool
    public var requiresWindowOrAXObservations: Bool
    public var links: [SemanticRecordingCLIMacroLinkEntry]

    public init(
        macrosRoot: String? = nil,
        recordingsRoot: String,
        totalMacroCount: Int,
        requiresOCRObservations: Bool = false,
        requiresWindowOrAXObservations: Bool = false,
        links: [SemanticRecordingCLIMacroLinkEntry]
    ) {
        self.macrosRoot = macrosRoot
        self.recordingsRoot = recordingsRoot
        self.totalMacroCount = max(0, totalMacroCount)
        self.linkedMacroCount = links.filter { $0.recordingReference != nil }.count
        self.returnedCount = links.count
        self.readyCount = links.filter { $0.status == .ready }.count
        self.degradedCount = links.filter { $0.status == .degraded }.count
        self.notReadyCount = links.filter { $0.status == .notReady }.count
        self.failedCount = links.filter { $0.status == .failedToLoad }.count
        self.unlinkedCount = links.filter { $0.status == .unlinked }.count
        self.requiresOCRObservations = requiresOCRObservations
        self.requiresWindowOrAXObservations = requiresWindowOrAXObservations
        self.links = links
    }
}

public struct SemanticRecordingCLIExplainKeyPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingSemanticEventKind
    public var recordingTime: TimeInterval
    public var title: String
    public var summary: String?
    public var risk: String?
    public var frameID: UUID?
    public var timelineEventID: UUID?
    public var evidenceFrameIDs: [UUID]
    public var observationIDs: [UUID]
    public var evidence: [RecordingEvidenceReference]

    public init(event: RecordingSemanticEvent, bundle: SemanticRecordingBundle) {
        self.id = event.id
        self.kind = event.kind
        self.recordingTime = event.recordingTime
        self.title = event.title
        self.summary = event.summary
        self.risk = event.risk
        self.frameID = event.frameID
        self.timelineEventID = event.timelineEventID
        self.evidenceFrameIDs = event.evidenceFrameIDs
        self.observationIDs = event.observationIDs
        self.evidence = Self.evidenceReferences(event: event, bundle: bundle)
    }

    private static func evidenceReferences(
        event: RecordingSemanticEvent,
        bundle: SemanticRecordingBundle
    ) -> [RecordingEvidenceReference] {
        let observations = event.observationIDs.compactMap { observationID in
            bundle.visualObservations.first { $0.id == observationID }
        }
        let frameIDs = semanticRecordingCLIUniqueUUIDs(
            event.evidenceFrameIDs + [event.frameID].compactMap { $0 } + observations.compactMap(\.frameID)
        )

        var references: [RecordingEvidenceReference] = frameIDs.compactMap { frameID in
            guard let frame = bundle.frames.first(where: { $0.id == frameID }) else {
                return nil
            }
            let frameObservations = observations.filter { $0.frameID == frameID }
            let primaryObservation = frameObservations.first
            let eventIDs = semanticRecordingCLIUniqueUUIDs(
                [event.timelineEventID].compactMap { $0 } + frame.relatedEventIDs
            )
            return RecordingEvidenceReference(
                frameID: frame.id,
                eventIDs: eventIDs,
                observationIDs: frameObservations.map(\.id),
                artifactRef: primaryObservation?.artifactRef ?? bundle.preferredImageRef(for: frame),
                bounds: primaryObservation?.bounds ?? frame.windowBounds,
                summary: event.summary ?? event.title
            )
        }

        let referencedObservationIDs = Set(references.flatMap(\.observationIDs))
        for observation in observations where !referencedObservationIDs.contains(observation.id) {
            references.append(
                RecordingEvidenceReference(
                    frameID: observation.frameID,
                    eventIDs: [event.timelineEventID].compactMap { $0 },
                    observationIDs: [observation.id],
                    artifactRef: observation.artifactRef,
                    bounds: observation.bounds,
                    summary: event.summary ?? event.title
                )
            )
        }

        if references.isEmpty {
            references.append(
                RecordingEvidenceReference(
                    frameID: event.frameID,
                    eventIDs: [event.timelineEventID].compactMap { $0 },
                    observationIDs: event.observationIDs,
                    summary: event.summary ?? event.title
                )
            )
        }

        return references
    }
}

public struct SemanticRecordingCLIExplainObservation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingVisualObservationKind
    public var recordingTime: TimeInterval
    public var frameID: UUID?
    public var sourcePreviewRefID: UUID?
    public var text: String?
    public var confidence: Double?
    public var score: Double?
    public var provider: String
    public var labels: [String]
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?

    public init(observation: RecordingVisualObservation) {
        self.id = observation.id
        self.kind = observation.kind
        self.recordingTime = observation.recordingTime
        self.frameID = observation.frameID
        self.sourcePreviewRefID = observation.sourcePreviewRefID
        self.text = observation.text
        self.confidence = observation.confidence
        self.score = observation.score ?? observation.confidence
        self.provider = observation.provider
        self.labels = observation.labels
        self.artifactRef = observation.artifactRef
        self.bounds = observation.bounds
    }
}

public struct SemanticRecordingCLIExplainPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var summary: SemanticRecordingCLISummaryPayload
    public var keyPointCount: Int
    public var keyPoints: [SemanticRecordingCLIExplainKeyPoint]
    public var visualEvidenceCount: Int
    public var visualEvidence: [SemanticRecordingCLIExplainObservation]
    public var evidenceNotes: [String]
    public var mutationPolicy: String

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil
    ) {
        let keyPoints = bundle.semanticEvents
            .sorted { left, right in
                if left.recordingTime != right.recordingTime {
                    return left.recordingTime < right.recordingTime
                }
                return left.title < right.title
            }
            .map { event in
                SemanticRecordingCLIExplainKeyPoint(event: event, bundle: bundle)
            }
        let visualEvidence = bundle.visualObservations
            .sorted { left, right in
                if left.recordingTime != right.recordingTime {
                    return left.recordingTime < right.recordingTime
                }
                return left.kind.rawValue < right.kind.rawValue
            }
            .map(SemanticRecordingCLIExplainObservation.init(observation:))

        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.summary = SemanticRecordingCLISummaryPayload(
            requestedRecordingID: requestedRecordingID,
            bundle: bundle,
            fixture: fixture
        )
        self.keyPointCount = keyPoints.count
        self.keyPoints = keyPoints
        self.visualEvidenceCount = visualEvidence.count
        self.visualEvidence = visualEvidence
        self.evidenceNotes = Self.makeEvidenceNotes(bundle: bundle)
        self.mutationPolicy = "Explain output is read-only evidence. Workflow changes still require Review, Draft Preview, validate and import."
    }

    private static func makeEvidenceNotes(bundle: SemanticRecordingBundle) -> [String] {
        var notes: [String] = []
        if !bundle.schemaVersion.isSupportedByCurrentApp {
            notes.append("Bundle schema is not supported by the current app version.")
        }
        if bundle.frames.isEmpty {
            notes.append("No keyframes are available; frame-level evidence cannot be reviewed.")
        }
        if bundle.videoSegments.isEmpty {
            notes.append("No video segments are available; use keyframes and timeline events for review.")
        }
        if bundle.semanticEvents.isEmpty {
            notes.append("No semantic events are available; use raw frames/events/search before drafting.")
        }
        if bundle.visualObservations.isEmpty {
            notes.append("No visual observations are available; OCR/visual search and suggestions will be limited.")
        }
        if !bundle.suppressions.isEmpty {
            notes.append("Suppressed evidence is present; use redacted refs or Macro Review before drafting or sharing frames.")
        }
        if !bundle.redactedFrames.isEmpty || !bundle.redactedVideos.isEmpty {
            notes.append("Redacted artifact refs are available and should be preferred over source frame/video refs.")
        }
        return notes
    }
}

public struct SemanticRecordingCLIFramesPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var count: Int
    public var frames: [SemanticRecordingCLIFrameSummary]

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        frames selectedFrames: [RecordingFrameReference]? = nil
    ) {
        let frames = (selectedFrames ?? bundle.frames)
            .sorted { $0.recordingTime < $1.recordingTime }
        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.count = frames.count
        self.frames = frames.map { frame in
            SemanticRecordingCLIFrameSummary(
                frame: frame,
                redactedFrame: bundle.redactedFrame(frameID: frame.id),
                observationIDs: bundle.observations(frameID: frame.id).map(\.id)
            )
        }
    }
}

public struct SemanticRecordingCLIEventsNearQuery: Codable, Equatable, Sendable {
    public var time: TimeInterval
    public var window: TimeInterval

    public init(time: TimeInterval, window: TimeInterval) {
        self.time = max(0, time)
        self.window = max(0, window)
    }
}

public struct SemanticRecordingCLIEventsNearPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var query: SemanticRecordingCLIEventsNearQuery
    public var eventCount: Int
    public var frameCount: Int
    public var events: [SemanticRecordingCLIEventSummary]
    public var frames: [SemanticRecordingCLIFrameSummary]

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        time: TimeInterval,
        window: TimeInterval
    ) {
        let query = SemanticRecordingCLIEventsNearQuery(time: time, window: window)
        let matchingEvents = bundle.timelineEvents
            .filter { abs($0.recordingTime - query.time) <= query.window }
            .sorted { $0.recordingTime < $1.recordingTime }
        let eventIDs = Set(matchingEvents.map(\.id))
        let eventFrameIDs = Set(matchingEvents.compactMap(\.frameID))
        let matchingFrames = bundle.frames
            .filter { frame in
                if abs(frame.recordingTime - query.time) <= query.window {
                    return true
                }
                if eventFrameIDs.contains(frame.id) {
                    return true
                }
                return frame.relatedEventIDs.contains { eventIDs.contains($0) }
            }
            .sorted { $0.recordingTime < $1.recordingTime }

        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.query = query
        self.eventCount = matchingEvents.count
        self.frameCount = matchingFrames.count
        self.events = matchingEvents.map { event in
            let relatedFrameIDs = semanticRecordingCLIUniqueUUIDs(
                [event.frameID].compactMap { $0 } +
                    bundle.frames(relatedToEventID: event.id).map(\.id)
            )
            return SemanticRecordingCLIEventSummary(
                event: event,
                relatedFrameIDs: relatedFrameIDs
            )
        }
        self.frames = matchingFrames.map { frame in
            SemanticRecordingCLIFrameSummary(
                frame: frame,
                redactedFrame: bundle.redactedFrame(frameID: frame.id),
                observationIDs: bundle.observations(frameID: frame.id).map(\.id)
            )
        }
    }
}

public struct SemanticRecordingCLIOCRSearchQuery: Codable, Equatable, Sendable {
    public var text: String
    public var matchMode: TextMatchMode

    public init(text: String, matchMode: TextMatchMode = .contains) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.matchMode = matchMode
    }
}

public struct SemanticRecordingCLIOCRSearchResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var observationID: UUID
    public var queryResultIDs: [UUID]
    public var recordingTime: TimeInterval
    public var frameID: UUID?
    public var sourcePreviewRefID: UUID?
    public var text: String
    public var confidence: Double?
    public var score: Double?
    public var provider: String
    public var providerVersion: String?
    public var labels: [String]
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?
    public var evidence: [RecordingEvidenceReference]

    public init(
        observation: RecordingVisualObservation,
        queryResults: [RecordingQueryResult],
        bundle: SemanticRecordingBundle
    ) {
        let matchingQueryResults = queryResults
            .filter { result in
                result.kind == .ocrText &&
                    result.evidence.contains { evidence in
                        evidence.observationIDs.contains(observation.id)
                    }
            }
            .sorted { $0.title < $1.title }
        let evidence = matchingQueryResults.flatMap(\.evidence)

        self.id = observation.id
        self.observationID = observation.id
        self.queryResultIDs = matchingQueryResults.map(\.id)
        self.recordingTime = observation.recordingTime
        self.frameID = observation.frameID
        self.sourcePreviewRefID = observation.sourcePreviewRefID
        self.text = observation.text ?? ""
        self.confidence = observation.confidence
        self.score = observation.score ?? observation.confidence ?? matchingQueryResults.first?.score
        self.provider = observation.provider
        self.providerVersion = observation.providerVersion
        self.labels = observation.labels
        self.artifactRef = observation.artifactRef
        self.bounds = observation.bounds
        self.evidence = evidence.isEmpty
            ? Self.evidenceFallback(observation: observation, bundle: bundle)
            : evidence
    }

    private static func evidenceFallback(
        observation: RecordingVisualObservation,
        bundle: SemanticRecordingBundle
    ) -> [RecordingEvidenceReference] {
        let eventIDs = observation.frameID.flatMap { frameID in
            bundle.frames.first { $0.id == frameID }?.relatedEventIDs
        } ?? []
        return [
            RecordingEvidenceReference(
                frameID: observation.frameID,
                eventIDs: eventIDs,
                observationIDs: [observation.id],
                artifactRef: observation.artifactRef,
                bounds: observation.bounds,
                summary: "OCR observation matched the search text."
            )
        ]
    }
}

public struct SemanticRecordingCLIOCRSearchPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var availability: SemanticRecordingQueryAvailability
    public var query: SemanticRecordingCLIOCRSearchQuery
    public var unavailableReason: String?
    public var count: Int
    public var results: [SemanticRecordingCLIOCRSearchResult]

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        text: String,
        matchMode: TextMatchMode = .contains,
        queryResults: [RecordingQueryResult] = []
    ) {
        let query = SemanticRecordingCLIOCRSearchQuery(text: text, matchMode: matchMode)
        let searchQuery = SemanticRecordingOCRSearchQuery(
            text: query.text,
            matchMode: query.matchMode
        )
        let searchResult: SemanticRecordingOCRSearchResult
        if let fixture {
            searchResult = SemanticRecordingQueryEngine
                .deterministicOCRSearch(
                    for: bundle,
                    fixture: fixture,
                    query: searchQuery
                )
        } else {
            searchResult = SemanticRecordingQueryEngine.persistedOCRSearch(
                for: bundle,
                query: searchQuery,
                queryResults: queryResults
            )
        }
        let results = searchResult.matches.map { match in
            SemanticRecordingCLIOCRSearchResult(
                observation: match.observation,
                queryResults: match.queryResults,
                bundle: bundle
            )
        }

        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.availability = searchResult.availability
        self.query = query
        self.unavailableReason = searchResult.unavailableReason
        self.count = results.count
        self.results = results
    }
}

public struct SemanticRecordingCLIVisualSearchQuery: Codable, Equatable, Sendable {
    public var text: String?
    public var matchMode: TextMatchMode
    public var kind: RecordingVisualObservationKind?
    public var label: String?

    public init(
        text: String? = nil,
        matchMode: TextMatchMode = .contains,
        kind: RecordingVisualObservationKind? = nil,
        label: String? = nil
    ) {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmedText?.isEmpty == true ? nil : trimmedText
        self.matchMode = matchMode
        self.kind = kind
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = trimmedLabel?.isEmpty == true ? nil : trimmedLabel
    }
}

public struct SemanticRecordingCLIVisualSearchResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var observationID: UUID
    public var kind: RecordingVisualObservationKind
    public var recordingTime: TimeInterval
    public var frameID: UUID?
    public var sourcePreviewRefID: UUID?
    public var text: String?
    public var confidence: Double?
    public var score: Double?
    public var provider: String
    public var providerVersion: String?
    public var labels: [String]
    public var artifactRef: RecordingArtifactRef?
    public var bounds: RecordingBounds?
    public var evidence: [RecordingEvidenceReference]

    public init(
        match: SemanticRecordingVisualSearchMatch,
        bundle: SemanticRecordingBundle
    ) {
        let observation = match.observation
        self.id = observation.id
        self.observationID = observation.id
        self.kind = observation.kind
        self.recordingTime = observation.recordingTime
        self.frameID = observation.frameID
        self.sourcePreviewRefID = observation.sourcePreviewRefID
        self.text = observation.text
        self.confidence = observation.confidence
        self.score = observation.score ?? observation.confidence
        self.provider = observation.provider
        self.providerVersion = observation.providerVersion
        self.labels = observation.labels
        self.artifactRef = observation.artifactRef
        self.bounds = observation.bounds
        self.evidence = Self.evidenceFallback(observation: observation, bundle: bundle)
    }

    private static func evidenceFallback(
        observation: RecordingVisualObservation,
        bundle: SemanticRecordingBundle
    ) -> [RecordingEvidenceReference] {
        let eventIDs = observation.frameID.flatMap { frameID in
            bundle.frames.first { $0.id == frameID }?.relatedEventIDs
        } ?? []
        return [
            RecordingEvidenceReference(
                frameID: observation.frameID,
                eventIDs: eventIDs,
                observationIDs: [observation.id],
                artifactRef: observation.artifactRef,
                bounds: observation.bounds,
                summary: "Visual observation matched the search filters."
            )
        ]
    }
}

public struct SemanticRecordingCLIVisualSearchPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var query: SemanticRecordingCLIVisualSearchQuery
    public var count: Int
    public var results: [SemanticRecordingCLIVisualSearchResult]

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        text: String? = nil,
        matchMode: TextMatchMode = .contains,
        kind: RecordingVisualObservationKind? = nil,
        label: String? = nil
    ) {
        let query = SemanticRecordingCLIVisualSearchQuery(
            text: text,
            matchMode: matchMode,
            kind: kind,
            label: label
        )
        let results = SemanticRecordingQueryEngine.visualSearch(
            bundle: bundle,
            query: SemanticRecordingVisualSearchQuery(
                text: query.text,
                matchMode: query.matchMode,
                kind: query.kind,
                label: query.label
            )
        )
        .map { match in
            SemanticRecordingCLIVisualSearchResult(
                match: match,
                bundle: bundle
            )
        }

        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.query = query
        self.count = results.count
        self.results = results
    }
}

public enum SemanticRecordingCLIAssetExtractionKind: String, Codable, Equatable, Sendable {
    case imageTemplate
    case image
    case baseline

    public var materializedKind: SemanticRecordingReviewMaterializedAssetKind {
        switch self {
        case .imageTemplate, .image:
            return .image
        case .baseline:
            return .baseline
        }
    }
}

public struct SemanticRecordingCLIAssetExtractionQuery: Codable, Equatable, Sendable {
    public var frameID: UUID
    public var region: RecordingBounds
    public var kind: SemanticRecordingCLIAssetExtractionKind
    public var name: String
    public var assetKey: String

    public init(
        frameID: UUID,
        region: RecordingBounds,
        kind: SemanticRecordingCLIAssetExtractionKind,
        name: String,
        assetKey: String
    ) {
        self.frameID = frameID
        self.region = region
        self.kind = kind
        self.name = name
        self.assetKey = assetKey
    }
}

public struct SemanticRecordingCLIAssetExtractionPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var query: SemanticRecordingCLIAssetExtractionQuery
    public var sourceArtifactRef: RecordingArtifactRef
    public var outputRoot: String
    public var materializedAsset: SemanticRecordingReviewMaterializedAsset
    public var visualAsset: AutomationWorkflowDraftVisualImageAsset
    public var visualAssets: AutomationWorkflowDraftVisualAssets
    public var evidence: [RecordingEvidenceReference]

    public init(
        requestedRecordingID: String,
        recordingID: UUID,
        fixture: String? = nil,
        query: SemanticRecordingCLIAssetExtractionQuery,
        sourceArtifactRef: RecordingArtifactRef,
        outputRoot: String,
        materializedAsset: SemanticRecordingReviewMaterializedAsset,
        visualAsset: AutomationWorkflowDraftVisualImageAsset,
        evidence: [RecordingEvidenceReference]
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.recordingID = recordingID
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.query = query
        self.sourceArtifactRef = sourceArtifactRef
        self.outputRoot = outputRoot
        self.materializedAsset = materializedAsset
        self.visualAsset = visualAsset
        switch query.kind.materializedKind {
        case .image:
            self.visualAssets = AutomationWorkflowDraftVisualAssets(images: [visualAsset])
        case .baseline:
            self.visualAssets = AutomationWorkflowDraftVisualAssets(baselines: [visualAsset])
        }
        self.evidence = evidence
    }
}

public struct AutomationWorkflowDraftFromRecordingPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var sourceOption: String?
    public var wrotePath: String?
    public var result: SemanticRecordingWorkflowDraftBuildResult

    public init(
        requestedRecordingID: String,
        recordingID: UUID,
        fixture: String? = nil,
        sourceOption: String? = nil,
        wrotePath: String? = nil,
        result: SemanticRecordingWorkflowDraftBuildResult
    ) {
        self.requestedRecordingID = requestedRecordingID
        self.recordingID = recordingID
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.sourceOption = sourceOption
        self.wrotePath = wrotePath
        self.result = result
    }
}

public enum SemanticRecordingCLISuggestionCategory: String, Codable, Equatable, Sendable {
    case waits
    case locators
    case conditions
    case cleanup
    case all

    public var suggestionKinds: [RecordingSuggestionKind] {
        switch self {
        case .waits:
            return [.waitCleanup, .conditionCandidate]
        case .locators:
            return [.locatorReplacement, .fragileClick, .visualAssetExtraction]
        case .conditions:
            return [.conditionCandidate]
        case .cleanup:
            return [.waitCleanup, .locatorReplacement, .conditionCandidate, .fragileClick]
        case .all:
            return [
                .waitCleanup,
                .locatorReplacement,
                .conditionCandidate,
                .visualAssetExtraction,
                .fragileClick,
                .draftGeneration
            ]
        }
    }
}

public struct SemanticRecordingCLISuggestionSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordingSuggestionKind
    public var title: String
    public var summary: String
    public var confidence: Double
    public var risk: String?
    public var fallback: String
    public var mutationPolicy: String
    public var evidence: [RecordingEvidenceReference]
    public var reviewActions: [SemanticRecordingReviewActionSemantics]
    public var reviewActionPresentations: [SemanticRecordingReviewActionPresentation]

    private static let missingEvidenceConfidenceCap = 0.49

    public init(suggestion: RecordingSuggestion) {
        self.id = suggestion.id
        self.kind = suggestion.kind
        self.title = suggestion.title
        self.summary = suggestion.summary
        self.confidence = suggestion.evidence.isEmpty
            ? min(suggestion.confidence, Self.missingEvidenceConfidenceCap)
            : suggestion.confidence
        self.risk = Self.risk(suggestion.risk, evidence: suggestion.evidence)
        self.fallback = Self.fallback(for: suggestion.kind)
        self.mutationPolicy = "Review required; no workflow or macro mutation until accepted."
        self.evidence = suggestion.evidence
        let reviewActions: [SemanticRecordingReviewActionSemantics] = [
            .acceptSuggestion(suggestion),
            .rejectSuggestion(suggestion),
            .clearDecision(suggestion)
        ]
        self.reviewActions = reviewActions
        self.reviewActionPresentations = reviewActions.map(SemanticRecordingReviewActionPresentation.init)
    }

    private static func risk(
        _ risk: String?,
        evidence: [RecordingEvidenceReference]
    ) -> String? {
        guard evidence.isEmpty else {
            return risk
        }
        let missingEvidenceRisk = "Missing recording evidence refs; keep this suggestion low confidence until cited evidence is available."
        guard let risk, !risk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return missingEvidenceRisk
        }
        return "\(risk) \(missingEvidenceRisk)"
    }

    private static func fallback(for kind: RecordingSuggestionKind) -> String {
        switch kind {
        case .waitCleanup:
            return "Keep the original recorded wait until the user accepts a reviewed replacement."
        case .locatorReplacement:
            return "Keep the original playable click or keystroke if the locator is not accepted."
        case .conditionCandidate:
            return "Keep the original playable macro wait until the user accepts a reviewed condition."
        case .visualAssetExtraction:
            return "Keep existing recording evidence refs until an asset is explicitly extracted."
        case .fragileClick:
            return "Keep coordinate playback as the fallback path while a better locator is reviewed."
        case .draftGeneration:
            return "Keep the generated workflow as a draft only; validate and import explicitly."
        }
    }
}

public struct SemanticRecordingCLISuggestionsPayload: Codable, Equatable, Sendable {
    public var requestedRecordingID: String
    public var recordingID: UUID
    public var fixtureMode: Bool
    public var fixture: String?
    public var category: SemanticRecordingCLISuggestionCategory
    public var availability: SemanticRecordingSuggestionAvailability
    public var query: SemanticRecordingSuggestionQuery
    public var unavailableReason: String?
    public var count: Int
    public var suggestions: [SemanticRecordingCLISuggestionSummary]
    public var artifactFiles: SemanticRecordingCLIArtifactFileSummary?

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        category: SemanticRecordingCLISuggestionCategory,
        suggestions: [RecordingSuggestion],
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) {
        let availability: SemanticRecordingSuggestionAvailability = fixture == nil
            ? .persistedBundle
            : .deterministicFixture
        self.init(
            requestedRecordingID: requestedRecordingID,
            bundle: bundle,
            fixture: fixture,
            category: category,
            suggestionResult: SemanticRecordingSuggestionResult(
                availability: availability,
                query: .kinds(category.suggestionKinds),
                suggestions: suggestions,
                unavailableReason: nil
            ),
            artifactFiles: artifactFiles
        )
    }

    public init(
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        category: SemanticRecordingCLISuggestionCategory,
        suggestionResult: SemanticRecordingSuggestionResult,
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) {
        let selectedSuggestions = SemanticRecordingQueryEngine
            .filterAndSort(
                suggestions: suggestionResult.suggestions,
                allowedKinds: suggestionResult.query.allowedKinds
            )
            .map(SemanticRecordingCLISuggestionSummary.init(suggestion:))

        self.requestedRecordingID = requestedRecordingID
        self.recordingID = bundle.id
        self.fixtureMode = fixture != nil
        self.fixture = fixture
        self.category = category
        self.availability = suggestionResult.availability
        self.query = suggestionResult.query
        self.unavailableReason = suggestionResult.unavailableReason
        self.count = selectedSuggestions.count
        self.suggestions = selectedSuggestions
        self.artifactFiles = artifactFiles
    }
}

public extension AutomationCLIResultEnvelope {
    static func failure(
        command: String,
        code: String,
        message: String,
        path: String? = nil
    ) -> AutomationCLIResultEnvelope<Value> {
        AutomationCLIResultEnvelope<Value>(
            ok: false,
            command: command,
            data: nil,
            errors: [
                AutomationCLIMessage(
                    code: code,
                    message: message,
                    path: path
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIListPayload {
    static func semanticRecordingList(
        command: String,
        recordings: [SemanticRecordingCLICatalogEntry],
        fixture: String? = nil,
        recordingsRoot: String? = nil,
        sourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        let nextActions = recordings.prefix(1).map { recording in
            AutomationCLINextAction(
                command: "SparkleRecorder recording show \(recording.recordingID.uuidString)\(sourceArgument) --json",
                reason: "Open the latest listed semantic recording before narrowing frames, OCR or suggestions."
            )
        }
        return AutomationCLIResultEnvelope<SemanticRecordingCLIListPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIListPayload(
                recordings: recordings,
                fixture: fixture,
                recordingsRoot: recordingsRoot
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLISummaryPayload {
    static func semanticRecordingShow(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLISummaryPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLISummaryPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording frames \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "List event-aligned keyframes and safe artifact refs without reading image bytes."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder recording events-near \(requestedRecordingID) --time <seconds> --window 1.0\(sourceArgument) --json",
                    reason: "Ask for nearby events and frames before drafting a condition or locator suggestion."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIReadinessPayload {
    static func semanticRecordingReadiness(
        command: String,
        requestedRecordingID: String,
        loadResult: SemanticRecordingBundleLoadResult,
        readiness: SemanticRecordingBundleReadiness,
        fixture: String? = nil,
        sourceOption: String? = nil,
        bundleDirectory: String? = nil,
        followUps: [String] = [],
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIReadinessPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIReadinessPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIReadinessPayload(
                requestedRecordingID: requestedRecordingID,
                loadResult: loadResult,
                readiness: readiness,
                fixture: fixture,
                sourceOption: sourceOption,
                bundleDirectory: bundleDirectory,
                followUps: followUps,
                artifactFiles: artifactFiles
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture)
                + semanticRecordingCLIReadinessWarnings(
                    readiness,
                    loadResult: loadResult,
                    artifactFiles: artifactFiles
                ),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording show \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "Inspect the same loaded bundle summary and safe artifact refs before using it for Review or AI."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder recording explain \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "Read the AI-safe semantic events and evidence notes after readiness issues are understood."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIMacroLinksPayload {
    static func semanticRecordingMacroLinks(
        command: String,
        payload: SemanticRecordingCLIMacroLinksPayload,
        recordingsRootSourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIMacroLinksPayload> {
        let firstLinked = payload.links.first { $0.recordingReference != nil }
        let sourceArgument = recordingsRootSourceOption ?? ""
        var nextActions: [AutomationCLINextAction] = []
        if let recordingID = firstLinked?.recordingID {
            nextActions.append(
                AutomationCLINextAction(
                    command: "SparkleRecorder recording readiness \(recordingID.uuidString)\(sourceArgument) --json",
                    reason: "Audit the linked semantic recording bundle before using the saved macro as live Review or AI evidence."
                )
            )
            nextActions.append(
                AutomationCLINextAction(
                    command: "SparkleRecorder recording show \(recordingID.uuidString)\(sourceArgument) --json",
                    reason: "Inspect the linked bundle summary and safe artifact refs."
                )
            )
        }
        return AutomationCLIResultEnvelope<SemanticRecordingCLIMacroLinksPayload>(
            ok: true,
            command: command,
            data: payload,
            warnings: semanticRecordingCLIMacroLinkWarnings(payload),
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIExplainPayload {
    static func semanticRecordingExplain(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIExplainPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIExplainPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording frames \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "Inspect cited frame refs before accepting any generated edits."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder recording ocr search \(requestedRecordingID) --text <text>\(sourceArgument) --json",
                    reason: "Narrow explanation evidence to local OCR observations without invoking Vision."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow draft from-recording \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "Generate a review-only workflow draft after checking the cited evidence."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIFramesPayload {
    static func semanticRecordingFrames(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIFramesPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording events-near \(requestedRecordingID) --time <seconds> --window 1.0\(sourceArgument) --json",
                    reason: "Narrow the frame list around a click, wait or visual observation before making a reviewable edit."
                )
            ]
        )
    }

    static func semanticRecordingFrameShow(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        frame: RecordingFrameReference,
        fixture: String? = nil,
        sourceOption: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIFramesPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIFramesPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture,
                frames: [frame]
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording events-near \(requestedRecordingID) --time \(frame.recordingTime) --window 1.0\(sourceArgument) --json",
                    reason: "Inspect nearby timeline events before turning this frame into a reviewable draft edit."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIEventsNearPayload {
    static func semanticRecordingEventsNear(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil,
        time: TimeInterval,
        window: TimeInterval
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIEventsNearPayload> {
        return AutomationCLIResultEnvelope<SemanticRecordingCLIEventsNearPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIEventsNearPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture,
                time: time,
                window: window
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "Open the cited frame IDs in Macro Review before accepting AI-generated edits.",
                    reason: "S4 fixture commands expose evidence refs; user-reviewed mutation still belongs to Review or Draft Preview."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIOCRSearchPayload {
    static func semanticRecordingOCRSearch(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil,
        text: String,
        matchMode: TextMatchMode = .contains,
        queryResults: [RecordingQueryResult] = []
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIOCRSearchPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIOCRSearchPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture,
                text: text,
                matchMode: matchMode,
                queryResults: queryResults
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording events-near \(requestedRecordingID) --time <matched-time> --window 1.0\(sourceArgument) --json",
                    reason: "Inspect timeline context around a matched OCR observation before creating a condition."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder recording suggest conditions \(requestedRecordingID)\(sourceArgument) --json",
                    reason: "Ask for review-only condition suggestions backed by the matched OCR evidence."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIVisualSearchPayload {
    static func semanticRecordingVisualSearch(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil,
        text: String? = nil,
        matchMode: TextMatchMode = .contains,
        kind: RecordingVisualObservationKind? = nil,
        label: String? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIVisualSearchPayload> {
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: fixture,
            sourceOption: sourceOption
        )
        return AutomationCLIResultEnvelope<SemanticRecordingCLIVisualSearchPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLIVisualSearchPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture,
                text: text,
                matchMode: matchMode,
                kind: kind,
                label: label
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder recording events-near \(requestedRecordingID) --time <matched-time> --window 1.0\(sourceArgument) --json",
                    reason: "Inspect timeline context before turning a visual observation into a reviewed condition or asset."
                ),
                AutomationCLINextAction(
                    command: "Open the cited frame IDs in Macro Review before extracting assets or accepting locators.",
                    reason: "Visual search returns evidence proposals only; user-reviewed asset extraction remains a separate step."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLIAssetExtractionPayload {
    static func semanticRecordingAssetExtraction(
        command: String,
        payload: SemanticRecordingCLIAssetExtractionPayload
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload> {
        AutomationCLIResultEnvelope<SemanticRecordingCLIAssetExtractionPayload>(
            ok: true,
            command: command,
            data: payload,
            warnings: semanticRecordingCLIFixtureWarnings(payload.fixture),
            nextActions: [
                AutomationCLINextAction(
                    command: "Add visualAssets.\(payload.query.kind.materializedKind == .baseline ? "baselines" : "images") to a sparkle.workflow.draft.v1 document before import.",
                    reason: "Asset extraction materializes a package-local visual asset; workflow mutation still goes through Draft Preview/import."
                ),
                AutomationCLINextAction(
                    command: "Open the cited frame ID in Macro Review before accepting generated draft edits.",
                    reason: "The extracted asset is evidence-backed but still needs user review before changing automation behavior."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftFromRecordingPayload {
    static func workflowDraftFromRecording(
        command: String,
        payload: AutomationWorkflowDraftFromRecordingPayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftFromRecordingPayload> {
        let validationWarnings = payload.result.validation.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let validationErrors = payload.result.validation.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))
        let skippedWarnings = payload.result.skippedItems.map { skipped in
            let id = skipped.suggestionID?.uuidString ?? skipped.candidateID ?? skipped.source.rawValue
            return AutomationCLIMessage(
                code: "draftItemSkipped",
                message: "Skipped \(skipped.source.rawValue) '\(id)': \(skipped.reason)"
            )
        }
        let fallbackWarnings: [AutomationCLIMessage]
        if payload.result.appliedItems.contains(where: { $0.source == .conditionCandidate }) {
            fallbackWarnings = [
                AutomationCLIMessage(
                    code: "draftCandidateFallback",
                    message: "Draft tasks were generated from direct Review condition candidates, not stored/live suggestion synthesis."
                )
            ]
        } else {
            fallbackWarnings = []
        }
        let draftPath = payload.wrotePath ?? "<recording-draft.json>"
        let sourceArgument = semanticRecordingCLISourceOption(
            fixture: payload.fixture,
            sourceOption: payload.sourceOption
        )

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftFromRecordingPayload>(
            ok: payload.result.isValid,
            command: command,
            data: payload,
            warnings: semanticRecordingCLIFixtureWarnings(payload.fixture) + fallbackWarnings + validationWarnings + skippedWarnings,
            errors: validationErrors,
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow draft validate \(draftPath) --json",
                    reason: "Validate the generated draft before simulation or import."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow draft simulate \(draftPath) --json",
                    reason: "Preview condition branches and timeout behavior before import."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder recording frames \(payload.requestedRecordingID)\(sourceArgument) --json",
                    reason: "Inspect the cited frame evidence before accepting generated draft tasks."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == SemanticRecordingCLISuggestionsPayload {
    static func semanticRecordingSuggestions(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil,
        category: SemanticRecordingCLISuggestionCategory,
        suggestions: [RecordingSuggestion],
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload> {
        let availability: SemanticRecordingSuggestionAvailability = fixture == nil
            ? .persistedBundle
            : .deterministicFixture
        return semanticRecordingSuggestions(
            command: command,
            requestedRecordingID: requestedRecordingID,
            bundle: bundle,
            fixture: fixture,
            sourceOption: sourceOption,
            category: category,
            suggestionResult: SemanticRecordingSuggestionResult(
                availability: availability,
                query: .kinds(category.suggestionKinds),
                suggestions: suggestions,
                unavailableReason: nil
            ),
            artifactFiles: artifactFiles
        )
    }

    static func semanticRecordingSuggestions(
        command: String,
        requestedRecordingID: String,
        bundle: SemanticRecordingBundle,
        fixture: String? = nil,
        sourceOption: String? = nil,
        category: SemanticRecordingCLISuggestionCategory,
        suggestionResult: SemanticRecordingSuggestionResult,
        artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
    ) -> AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload> {
        return AutomationCLIResultEnvelope<SemanticRecordingCLISuggestionsPayload>(
            ok: true,
            command: command,
            data: SemanticRecordingCLISuggestionsPayload(
                requestedRecordingID: requestedRecordingID,
                bundle: bundle,
                fixture: fixture,
                category: category,
                suggestionResult: suggestionResult,
                artifactFiles: artifactFiles
            ),
            warnings: semanticRecordingCLIFixtureWarnings(fixture)
                + semanticRecordingCLISuggestionWarnings(
                    suggestionResult,
                    artifactFiles: artifactFiles
                ),
            nextActions: [
                AutomationCLINextAction(
                    command: "Open the cited frame IDs in Macro Review before accepting any suggestion.",
                    reason: "Suggestions are non-destructive evidence proposals, not workflow mutations."
                ),
                AutomationCLINextAction(
                    command: "Use Draft Preview validate/simulate/import only after user review.",
                    reason: "S4 returns explainable suggestions; Review and Draft Preview own accepted mutations."
                )
            ]
        )
    }
}

private func semanticRecordingCLIFixtureWarnings(_ fixture: String?) -> [AutomationCLIMessage] {
    guard let fixture else {
        return []
    }
    return [
        AutomationCLIMessage(
            code: "fixtureMode",
            message: "This result uses the S1 '\(fixture)' fixture, not a live semantic recording bundle."
        )
    ]
}

private func semanticRecordingCLISuggestionWarnings(
    _ result: SemanticRecordingSuggestionResult,
    artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
) -> [AutomationCLIMessage] {
    var warnings: [AutomationCLIMessage] = []
    if result.availability == .unavailable {
        warnings.append(
            AutomationCLIMessage(
                code: "suggestionsUnavailable",
                message: result.unavailableReason
                    ?? "Stored bundle suggestion synthesis is not implemented yet; this command returns only available deterministic suggestions."
            )
        )
    }
    if artifactFiles?.hasIssues == true {
        warnings.append(
            AutomationCLIMessage(
                code: "recordingArtifactsDegraded",
                message: "One or more semantic recording bundle artifact refs are missing, deleted, empty, unsafe or directories; inspect artifactFiles before accepting suggestions."
            )
        )
    }
    return warnings
}

private func semanticRecordingCLIReadinessWarnings(
    _ readiness: SemanticRecordingBundleReadiness,
    loadResult: SemanticRecordingBundleLoadResult,
    artifactFiles: SemanticRecordingCLIArtifactFileSummary? = nil
) -> [AutomationCLIMessage] {
    var warnings: [AutomationCLIMessage] = []
    if readiness.status != .ready {
        warnings.append(
            AutomationCLIMessage(
                code: semanticRecordingCLIReadinessWarningCode(readiness.status),
                message: "Semantic recording readiness is \(readiness.status.rawValue); inspect issues before treating this bundle as product-ready evidence."
            )
        )
    }
    if loadResult.sidecarDiagnostics.isDegraded {
        warnings.append(
            AutomationCLIMessage(
                code: "recordingSidecarsDegraded",
                message: "One or more semantic recording sidecars are missing or failed to load; inspect load.sidecarDiagnostics before using this bundle for Review or AI."
            )
        )
    }
    if artifactFiles?.hasIssues == true {
        warnings.append(
            AutomationCLIMessage(
                code: "recordingArtifactsDegraded",
                message: "One or more semantic recording artifact refs are missing, deleted, empty, unsafe or directories; inspect artifactFiles before treating this as live product evidence."
            )
        )
    }
    return warnings
}

private func semanticRecordingCLIReadinessWarningCode(
    _ status: SemanticRecordingBundleReadinessStatus
) -> String {
    switch status {
    case .ready:
        return "recordingReadinessReady"
    case .degraded:
        return "recordingReadinessDegraded"
    case .notReady:
        return "recordingReadinessNotReady"
    }
}

private func semanticRecordingCLIMacroLinkWarnings(
    _ payload: SemanticRecordingCLIMacroLinksPayload
) -> [AutomationCLIMessage] {
    var warnings: [AutomationCLIMessage] = []
    if payload.failedCount > 0 {
        warnings.append(
            AutomationCLIMessage(
                code: "macroSemanticRecordingLinkFailed",
                message: "\(payload.failedCount) saved macro semantic recording link(s) could not be loaded from the selected recordings root."
            )
        )
    }
    if payload.notReadyCount > 0 {
        warnings.append(
            AutomationCLIMessage(
                code: "macroSemanticRecordingNotReady",
                message: "\(payload.notReadyCount) saved macro semantic recording link(s) loaded but are not ready for product evidence."
            )
        )
    }
    if payload.degradedCount > 0 {
        warnings.append(
            AutomationCLIMessage(
                code: "macroSemanticRecordingDegraded",
                message: "\(payload.degradedCount) saved macro semantic recording link(s) are degraded; inspect readiness issues before using them."
            )
        )
    }
    let artifactIssueCount = payload.links.filter { $0.artifactFiles?.hasIssues == true }.count
    if artifactIssueCount > 0 {
        warnings.append(
            AutomationCLIMessage(
                code: "macroSemanticRecordingArtifactsDegraded",
                message: "\(artifactIssueCount) linked semantic recording bundle(s) have missing, empty, unsafe or directory artifact refs."
            )
        )
    }
    return warnings
}

private func semanticRecordingCLIFixtureOption(_ fixture: String?) -> String {
    guard let fixture else {
        return ""
    }
    return " --fixture \(fixture)"
}

private func semanticRecordingCLISourceOption(
    fixture: String?,
    sourceOption: String?
) -> String {
    if let sourceOption {
        return sourceOption
    }
    return semanticRecordingCLIFixtureOption(fixture)
}

private func semanticRecordingCLIUniqueUUIDs(_ ids: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    var result: [UUID] = []
    for id in ids where !seen.contains(id) {
        seen.insert(id)
        result.append(id)
    }
    return result
}

public struct AutomationWorkflowMacroCatalogPayload: Codable, Equatable, Sendable {
    public var count: Int
    public var search: String?
    public var macros: [AutomationWorkflowDraftMacroCatalogEntry]

    public init(
        macros: [AutomationWorkflowDraftMacroCatalogEntry],
        search: String? = nil
    ) {
        self.macros = macros
        self.count = macros.count
        self.search = search
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowMacroCatalogPayload {
    static func workflowMacroCatalog(
        command: String,
        macros: [AutomationWorkflowDraftMacroCatalogEntry],
        search: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowMacroCatalogPayload(
                macros: macros,
                search: search
            )
        )
    }
}

public struct AutomationWorkflowDraftValidationPayload: Codable, Equatable, Sendable {
    public var isValid: Bool
    public var issueCount: Int
    public var issues: [AutomationWorkflowDraftIssue]

    public init(result: AutomationWorkflowDraftValidationResult) {
        self.isValid = result.isValid
        self.issueCount = result.issues.count
        self.issues = result.issues
    }
}

public struct AutomationWorkflowDraftSimulationPayload: Codable, Equatable, Sendable {
    public var isSimulatable: Bool
    public var result: AutomationWorkflowDraftSimulationResult

    public init(result: AutomationWorkflowDraftSimulationResult) {
        self.isSimulatable = result.isSimulatable
        self.result = result
    }
}

public struct AutomationWorkflowDraftImportPayload: Codable, Equatable, Sendable {
    public var mode: AutomationWorkflowDraftImportMode
    public var isImportable: Bool
    public var result: AutomationWorkflowDraftImportResult

    public init(result: AutomationWorkflowDraftImportResult) {
        self.mode = result.mode
        self.isImportable = result.isImportable
        self.result = result
    }
}

public struct AutomationWorkflowDraftEditPayload: Codable, Equatable, Sendable {
    public var operation: String
    public var isValid: Bool
    public var document: AutomationWorkflowDraftDocument
    public var validation: AutomationWorkflowDraftValidationResult
    public var changedTaskKeys: [String]
    public var changedDependencyKeys: [String]
    public var wrotePath: String?

    public init(result: AutomationWorkflowDraftEditResult) {
        self.operation = result.operation
        self.isValid = result.isValid
        self.document = result.document
        self.validation = result.validation
        self.changedTaskKeys = result.changedTaskKeys
        self.changedDependencyKeys = result.changedDependencyKeys
        self.wrotePath = result.wrotePath
    }
}

public struct AutomationWorkflowSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var version: Int
    public var taskCount: Int
    public var dependencyCount: Int
    public var enabledTaskCount: Int
    public var runCount: Int
    public var latestRunID: UUID?
    public var latestRunStatus: AutomationTaskRunStatus?
    public var latestRunOutcome: AutomationOutcome?
    public var createdAt: Date
    public var modifiedAt: Date
    public var validationIssueCount: Int

    public init(
        workflow: AutomationWorkflow,
        runs: [AutomationTaskRun] = []
    ) {
        let latestRun = runs.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first

        self.id = workflow.id
        self.name = workflow.name
        self.version = workflow.version
        self.taskCount = workflow.tasks.count
        self.dependencyCount = workflow.dependencies.count
        self.enabledTaskCount = workflow.tasks.filter(\.isEnabled).count
        self.runCount = runs.count
        self.latestRunID = latestRun?.id
        self.latestRunStatus = latestRun?.status
        self.latestRunOutcome = latestRun?.outcome
        self.createdAt = workflow.createdAt
        self.modifiedAt = workflow.modifiedAt
        self.validationIssueCount = workflow.validationIssues().count
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowListPayload: Codable, Equatable, Sendable {
    public var count: Int
    public var workflows: [AutomationWorkflowSummary]

    public init(workflows: [AutomationWorkflowSummary]) {
        self.count = workflows.count
        self.workflows = workflows
    }
}

public struct AutomationWorkflowShowPayload: Codable, Equatable, Sendable {
    public var summary: AutomationWorkflowSummary
    public var workflow: AutomationWorkflow
    public var runHistory: [AutomationTaskRun]

    public init(
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) {
        let workflowRuns = runHistory.filter { $0.workflowID == workflow.id }
        self.summary = AutomationWorkflowSummary(workflow: workflow, runs: workflowRuns)
        self.workflow = workflow
        self.runHistory = workflowRuns
    }
}

public struct AutomationWorkflowDraftExportPayload: Codable, Equatable, Sendable {
    public var result: AutomationWorkflowDraftExportResult
    public var wrotePath: String?

    public init(
        result: AutomationWorkflowDraftExportResult,
        wrotePath: String? = nil
    ) {
        self.result = result
        self.wrotePath = wrotePath
    }
}

public enum AutomationWorkflowStatusKind: String, Codable, Equatable, Sendable {
    case idle
    case planned
    case waitingForDependencies
    case waitingForResource
    case queued
    case running
    case completed
    case needsAttention
}

public struct AutomationTaskStatusSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { taskID }

    public var taskID: UUID
    public var taskName: String
    public var isEnabled: Bool
    public var requiresForegroundInput: Bool
    public var status: AutomationWorkflowStatusKind
    public var statusLabel: String
    public var statusDetail: String
    public var latestRunID: UUID?
    public var latestExecutionID: UUID?
    public var latestRunStatus: AutomationTaskRunStatus?
    public var latestOutcome: AutomationOutcome?
    public var scheduledStartTime: Date?
    public var earliestStartTime: Date?
    public var actualStartTime: Date?
    public var completedAt: Date?
    public var attempt: Int?

    public init(task: AutomationTask, runs: [AutomationTaskRun]) {
        let latestRun = runs.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first
        let status = Self.status(for: latestRun)

        self.taskID = task.id
        self.taskName = task.name
        self.isEnabled = task.isEnabled
        self.requiresForegroundInput = task.resourceRequirement.requiresForegroundInput
        self.status = status
        self.statusLabel = Self.label(for: status)
        self.statusDetail = Self.detail(for: status, run: latestRun)
        self.latestRunID = latestRun?.id
        self.latestExecutionID = latestRun?.executionID
        self.latestRunStatus = latestRun?.status
        self.latestOutcome = latestRun?.outcome
        self.scheduledStartTime = latestRun?.scheduledStartTime
        self.earliestStartTime = latestRun?.earliestStartTime
        self.actualStartTime = latestRun?.actualStartTime
        self.completedAt = latestRun?.completedAt
        self.attempt = latestRun?.attempt
    }

    private static func status(for run: AutomationTaskRun?) -> AutomationWorkflowStatusKind {
        guard let run else {
            return .idle
        }

        switch run.status {
        case .planned:
            return .planned
        case .waitingForDependencies:
            return .waitingForDependencies
        case .waitingForResource:
            return .waitingForResource
        case .queued:
            return .queued
        case .running:
            return .running
        case .completed:
            guard let outcome = run.outcome else {
                return .completed
            }
            return outcome.needsWorkflowAttention ? .needsAttention : .completed
        }
    }

    private static func label(for status: AutomationWorkflowStatusKind) -> String {
        switch status {
        case .idle:
            return "未运行"
        case .planned:
            return "已计划"
        case .waitingForDependencies:
            return "等待上一步"
        case .waitingForResource:
            return "等待资源"
        case .queued:
            return "准备执行"
        case .running:
            return "正在执行"
        case .completed:
            return "已完成"
        case .needsAttention:
            return "需要处理"
        }
    }

    private static func detail(for status: AutomationWorkflowStatusKind, run: AutomationTaskRun?) -> String {
        switch status {
        case .idle:
            return "这个任务还没有运行记录。"
        case .planned:
            return "已计划，等待触发。"
        case .waitingForDependencies:
            return "正在等待上一步完成。"
        case .waitingForResource:
            return "正在等待鼠标键盘空闲。"
        case .queued:
            return "已进入执行队列。"
        case .running:
            return "正在执行当前任务。"
        case .completed:
            return "最近一次运行已完成。"
        case .needsAttention:
            return run?.outcome?.workflowAttentionDetail ?? "最近一次运行需要处理。"
        }
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowStatus: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { summary.id }

    public var summary: AutomationWorkflowSummary
    public var overallStatus: AutomationWorkflowStatusKind
    public var statusLabel: String
    public var statusDetail: String
    public var activeRunCount: Int
    public var waitingRunCount: Int
    public var completedRunCount: Int
    public var attentionRunCount: Int
    public var latestRun: AutomationTaskRun?
    public var tasks: [AutomationTaskStatusSummary]

    public init(workflow: AutomationWorkflow, runHistory: [AutomationTaskRun]) {
        let workflowRuns = runHistory.filter { $0.workflowID == workflow.id }
        let runsByTask = Dictionary(grouping: workflowRuns, by: \.taskID)
        let tasks = workflow.tasks.map { task in
            AutomationTaskStatusSummary(task: task, runs: runsByTask[task.id] ?? [])
        }
        let latestRun = workflowRuns.sorted { left, right in
            Self.sortDate(for: left) > Self.sortDate(for: right)
        }.first
        let overallStatus = Self.overallStatus(
            taskSummaries: tasks,
            validationIssueCount: workflow.validationIssues().count
        )

        self.summary = AutomationWorkflowSummary(workflow: workflow, runs: workflowRuns)
        self.overallStatus = overallStatus
        self.statusLabel = Self.label(for: overallStatus)
        self.statusDetail = Self.detail(
            for: overallStatus,
            activeRunCount: tasks.filter { $0.status == .running }.count,
            waitingRunCount: tasks.filter { $0.status == .waitingForDependencies || $0.status == .waitingForResource }.count,
            attentionRunCount: tasks.filter { $0.status == .needsAttention }.count,
            validationIssueCount: workflow.validationIssues().count
        )
        self.activeRunCount = tasks.filter { $0.status == .running }.count
        self.waitingRunCount = tasks.filter { $0.status == .waitingForDependencies || $0.status == .waitingForResource }.count
        self.completedRunCount = tasks.filter { $0.status == .completed }.count
        self.attentionRunCount = tasks.filter { $0.status == .needsAttention }.count
        self.latestRun = latestRun
        self.tasks = tasks
    }

    private static func overallStatus(
        taskSummaries: [AutomationTaskStatusSummary],
        validationIssueCount: Int
    ) -> AutomationWorkflowStatusKind {
        if validationIssueCount > 0 {
            return .needsAttention
        }
        if taskSummaries.contains(where: { $0.status == .running }) {
            return .running
        }
        if taskSummaries.contains(where: { $0.status == .waitingForResource }) {
            return .waitingForResource
        }
        if taskSummaries.contains(where: { $0.status == .queued }) {
            return .queued
        }
        if taskSummaries.contains(where: { $0.status == .waitingForDependencies }) {
            return .waitingForDependencies
        }
        if taskSummaries.contains(where: { $0.status == .needsAttention }) {
            return .needsAttention
        }
        if taskSummaries.contains(where: { $0.status == .planned }) {
            return .planned
        }
        if !taskSummaries.isEmpty, taskSummaries.allSatisfy({ $0.status == .completed }) {
            return .completed
        }
        return .idle
    }

    private static func label(for status: AutomationWorkflowStatusKind) -> String {
        switch status {
        case .idle:
            return "未运行"
        case .planned:
            return "已计划"
        case .waitingForDependencies:
            return "等待上一步"
        case .waitingForResource:
            return "等待鼠标键盘空闲"
        case .queued:
            return "准备执行"
        case .running:
            return "正在执行"
        case .completed:
            return "已完成"
        case .needsAttention:
            return "需要处理"
        }
    }

    private static func detail(
        for status: AutomationWorkflowStatusKind,
        activeRunCount: Int,
        waitingRunCount: Int,
        attentionRunCount: Int,
        validationIssueCount: Int
    ) -> String {
        if validationIssueCount > 0 {
            return "\(validationIssueCount) 个工作流结构问题需要处理。"
        }

        switch status {
        case .idle:
            return "这个工作流还没有运行记录。"
        case .planned:
            return "任务已计划，等待触发。"
        case .waitingForDependencies:
            return "有任务正在等待上一步完成。"
        case .waitingForResource:
            return "有任务正在等待鼠标键盘空闲。"
        case .queued:
            return "有任务已进入执行队列。"
        case .running:
            return "\(max(activeRunCount, 1)) 个任务正在执行。"
        case .completed:
            return "最近一次运行已完成。"
        case .needsAttention:
            return "\(max(attentionRunCount, 1)) 个任务需要处理。"
        }
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowStatusPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var count: Int
    public var workflows: [AutomationWorkflowStatus]

    public init(
        workflows: [AutomationWorkflowStatus],
        generatedAt: Date = Date.now
    ) {
        self.generatedAt = generatedAt
        self.count = workflows.count
        self.workflows = workflows
    }
}

public struct AutomationWorkflowRunPayload: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var requestedTaskID: UUID
    public var requestedAt: Date
    public var executionID: UUID?
    public var startedRunID: UUID?
    public var isComplete: Bool
    public var timedOut: Bool
    public var workflowStatus: AutomationWorkflowStatus
    public var executionRuns: [AutomationTaskRun]

    public init(
        workflow: AutomationWorkflow,
        requestedTaskID: UUID,
        requestedAt: Date,
        beforeRuns: [AutomationTaskRun],
        afterState: AutomationRunState,
        timedOut: Bool = false
    ) {
        let beforeRunIDs = Set(beforeRuns.map(\.id))
        let newRuns = afterState.runs.filter { run in
            run.workflowID == workflow.id && !beforeRunIDs.contains(run.id)
        }
        let startedRun = newRuns.first { $0.taskID == requestedTaskID } ?? newRuns.first
        let executionID = startedRun?.executionID
        let executionRuns = afterState.runs
            .filter { run in
                run.workflowID == workflow.id &&
                    (executionID.map { run.executionID == $0 } ?? newRuns.contains(where: { $0.id == run.id }))
            }
            .sorted { left, right in
                Self.sortDate(for: left) < Self.sortDate(for: right)
            }

        self.workflowID = workflow.id
        self.workflowName = workflow.name
        self.requestedTaskID = requestedTaskID
        self.requestedAt = requestedAt
        self.executionID = executionID
        self.startedRunID = startedRun?.id
        self.isComplete = !executionRuns.isEmpty && executionRuns.allSatisfy(\.isTerminal)
        self.timedOut = timedOut
        self.workflowStatus = AutomationWorkflowStatus(workflow: workflow, runHistory: afterState.runs)
        self.executionRuns = executionRuns
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowCancelPayload: Codable, Equatable, Sendable {
    public var runID: UUID
    public var requestedAt: Date
    public var cancelled: Bool
    public var run: AutomationTaskRun?
    public var workflowStatus: AutomationWorkflowStatus?

    public init(
        runID: UUID,
        requestedAt: Date,
        beforeRun: AutomationTaskRun?,
        afterState: AutomationRunState
    ) {
        let afterRun = afterState.run(id: runID)
        let workflow = afterRun.flatMap { run in afterState.workflow(id: run.workflowID) }

        self.runID = runID
        self.requestedAt = requestedAt
        self.cancelled = beforeRun?.isTerminal == false &&
            afterRun?.outcome == .cancelled(reason: "User cancelled")
        self.run = afterRun
        self.workflowStatus = workflow.map { AutomationWorkflowStatus(workflow: $0, runHistory: afterState.runs) }
    }
}

public enum AutomationRuntimeHandoffTarget: String, Codable, Equatable, Sendable {
    case appHost
}

public struct AutomationRuntimeHandoffPayload: Codable, Equatable, Sendable {
    public var target: AutomationRuntimeHandoffTarget
    public var command: AutomationRuntimeHandoffCommand
    public var enqueuedAt: Date
    public var pendingCommandCount: Int

    public init(
        target: AutomationRuntimeHandoffTarget = .appHost,
        command: AutomationRuntimeHandoffCommand,
        enqueuedAt: Date,
        pendingCommandCount: Int
    ) {
        self.target = target
        self.command = command
        self.enqueuedAt = enqueuedAt
        self.pendingCommandCount = pendingCommandCount
    }
}

public struct AutomationWorkflowBoundWindowSurfaceSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { surfaceID }
    public var surfaceID: String
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var recordedFrame: RectValue
    public var recordedContentFrame: RectValue?

    public init(surfaceID: String, surface: PlaybackSurface) {
        self.surfaceID = surfaceID
        self.appName = surface.appName
        self.bundleIdentifier = surface.bundleIdentifier
        self.windowTitle = surface.windowTitle
        self.recordedFrame = surface.recordedFrame
        self.recordedContentFrame = surface.recordedContentFrame
    }
}

public struct AutomationWorkflowBoundWindowActivationResult: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var appName: String?
    public var wasRunning: Bool
    public var didLaunch: Bool
    public var didActivate: Bool
    public var errorMessage: String?

    public init(
        bundleIdentifier: String,
        appName: String? = nil,
        wasRunning: Bool,
        didLaunch: Bool = false,
        didActivate: Bool,
        errorMessage: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.wasRunning = wasRunning
        self.didLaunch = didLaunch
        self.didActivate = didActivate
        self.errorMessage = errorMessage
    }
}

public struct AutomationWorkflowBoundWindowAcceptancePayload: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var taskID: UUID
    public var taskName: String
    public var macroID: UUID
    public var macroName: String
    public var macroEventCount: Int
    public var macroSurfaceCount: Int
    public var playbackContextSurfaceCount: Int
    public var coordinateMode: CoordinateMode
    public var resourceRequiresForegroundInput: Bool
    public var surfaces: [AutomationWorkflowBoundWindowSurfaceSummary]
    public var activationRequested: Bool
    public var launchRequested: Bool
    public var playbackHandoffRequested: Bool
    public var activationResults: [AutomationWorkflowBoundWindowActivationResult]
    public var handoff: AutomationRuntimeHandoffPayload?
    public var checkedAt: Date

    public init(
        workflow: AutomationWorkflow,
        task: AutomationTask,
        macro: SavedMacro,
        activationRequested: Bool = false,
        launchRequested: Bool = false,
        playbackHandoffRequested: Bool = false,
        activationResults: [AutomationWorkflowBoundWindowActivationResult] = [],
        handoff: AutomationRuntimeHandoffPayload? = nil,
        checkedAt: Date = Date.now
    ) {
        let playbackContext = macro.playbackContext
        self.workflowID = workflow.id
        self.workflowName = workflow.name
        self.taskID = task.id
        self.taskName = task.name
        self.macroID = macro.id
        self.macroName = macro.name
        self.macroEventCount = macro.eventCount
        self.macroSurfaceCount = macro.surfaces.count
        self.playbackContextSurfaceCount = playbackContext.surfaces.count
        self.coordinateMode = playbackContext.coordinateMode
        self.resourceRequiresForegroundInput = task.resourceRequirement.requiresForegroundInput
        self.surfaces = macro.surfaces
            .map { surfaceID, surface in
                AutomationWorkflowBoundWindowSurfaceSummary(
                    surfaceID: surfaceID,
                    surface: surface
                )
            }
            .sorted { $0.surfaceID < $1.surfaceID }
        self.activationRequested = activationRequested
        self.launchRequested = launchRequested
        self.playbackHandoffRequested = playbackHandoffRequested
        self.activationResults = activationResults.sorted {
            $0.bundleIdentifier < $1.bundleIdentifier
        }
        self.handoff = handoff
        self.checkedAt = checkedAt
    }

    public var readyForBoundWindowPlayback: Bool {
        macroEventCount > 0 &&
            macroSurfaceCount > 0 &&
            playbackContextSurfaceCount > 0
    }
}

public enum AutomationRuntimeHandoffDeliveryState: String, Codable, Equatable, Sendable {
    case pending
    case dispatched
    case failed
    case missing
}

public struct AutomationRuntimeHandoffStatusPayload: Codable, Equatable, Sendable {
    public var target: AutomationRuntimeHandoffTarget
    public var commandID: UUID
    public var state: AutomationRuntimeHandoffDeliveryState
    public var command: AutomationRuntimeHandoffCommand?
    public var receipt: AutomationRuntimeHandoffReceipt?
    public var workflowStatus: AutomationWorkflowStatus?
    public var runs: [AutomationTaskRun]
    public var pendingCommandCount: Int
    public var receiptCount: Int
    public var checkedAt: Date

    public init(
        target: AutomationRuntimeHandoffTarget = .appHost,
        commandID: UUID,
        command: AutomationRuntimeHandoffCommand?,
        receipt: AutomationRuntimeHandoffReceipt?,
        workflowStatus: AutomationWorkflowStatus? = nil,
        runs: [AutomationTaskRun] = [],
        pendingCommandCount: Int,
        receiptCount: Int,
        checkedAt: Date
    ) {
        self.target = target
        self.commandID = commandID
        self.command = command
        self.receipt = receipt
        self.workflowStatus = workflowStatus
        self.runs = Self.orderedRuns(runs, receipt: receipt)
        self.pendingCommandCount = pendingCommandCount
        self.receiptCount = receiptCount
        self.checkedAt = checkedAt

        if let receipt {
            switch receipt.status {
            case .dispatched:
                self.state = .dispatched
            case .failed:
                self.state = .failed
            }
        } else if command != nil {
            self.state = .pending
        } else {
            self.state = .missing
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case commandID
        case state
        case command
        case receipt
        case workflowStatus
        case runs
        case pendingCommandCount
        case receiptCount
        case checkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try container.decodeIfPresent(
            AutomationRuntimeHandoffTarget.self,
            forKey: .target
        ) ?? .appHost
        self.commandID = try container.decode(UUID.self, forKey: .commandID)
        self.state = try container.decodeIfPresent(
            AutomationRuntimeHandoffDeliveryState.self,
            forKey: .state
        ) ?? .missing
        self.command = try container.decodeIfPresent(
            AutomationRuntimeHandoffCommand.self,
            forKey: .command
        )
        self.receipt = try container.decodeIfPresent(
            AutomationRuntimeHandoffReceipt.self,
            forKey: .receipt
        )
        self.workflowStatus = try container.decodeIfPresent(
            AutomationWorkflowStatus.self,
            forKey: .workflowStatus
        )
        self.runs = Self.orderedRuns(
            try container.decodeIfPresent([AutomationTaskRun].self, forKey: .runs) ?? [],
            receipt: receipt
        )
        self.pendingCommandCount = try container.decodeIfPresent(Int.self, forKey: .pendingCommandCount) ?? 0
        self.receiptCount = try container.decodeIfPresent(Int.self, forKey: .receiptCount) ?? 0
        self.checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt) ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(commandID, forKey: .commandID)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(receipt, forKey: .receipt)
        try container.encodeIfPresent(workflowStatus, forKey: .workflowStatus)
        try container.encode(runs, forKey: .runs)
        try container.encode(pendingCommandCount, forKey: .pendingCommandCount)
        try container.encode(receiptCount, forKey: .receiptCount)
        try container.encode(checkedAt, forKey: .checkedAt)
    }

    private static func orderedRuns(
        _ runs: [AutomationTaskRun],
        receipt: AutomationRuntimeHandoffReceipt?
    ) -> [AutomationTaskRun] {
        guard let receipt, !receipt.runIDs.isEmpty else {
            return runs.sorted { sortDate(for: $0) > sortDate(for: $1) }
        }

        var runsByID = Dictionary(grouping: runs, by: \.id)
            .mapValues { groupedRuns in
                groupedRuns.sorted { sortDate(for: $0) > sortDate(for: $1) }.first!
            }
        var ordered = receipt.runIDs.compactMap { runID in
            runsByID.removeValue(forKey: runID)
        }
        ordered.append(contentsOf: runsByID.values.sorted { sortDate(for: $0) > sortDate(for: $1) })
        return ordered
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public struct AutomationWorkflowRunsPayload: Codable, Equatable, Sendable {
    public var workflowID: UUID
    public var workflowName: String
    public var count: Int
    public var runs: [AutomationTaskRun]
    public var status: AutomationWorkflowStatus

    public init(
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) {
        let workflowRuns = runHistory
            .filter { $0.workflowID == workflow.id }
            .sorted { left, right in
                Self.sortDate(for: left) > Self.sortDate(for: right)
            }

        self.workflowID = workflow.id
        self.workflowName = workflow.name
        self.count = workflowRuns.count
        self.runs = workflowRuns
        self.status = AutomationWorkflowStatus(workflow: workflow, runHistory: runHistory)
    }

    private static func sortDate(for run: AutomationTaskRun) -> Date {
        run.completedAt ??
            run.actualStartTime ??
            run.earliestStartTime ??
            run.scheduledStartTime ??
            run.createdAt
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationRuntimeHandoffPayload {
    static func workflowHandoff(
        command: String,
        payload: AutomationRuntimeHandoffPayload
    ) -> AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload> {
        let nextActions: [AutomationCLINextAction]
        switch payload.command.kind {
        case .manualStart(let workflowID, _):
            nextActions = [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow handoff status \(payload.command.id.uuidString) --json",
                    reason: "Check whether the running App host has dispatched or rejected the handoff command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflowID.uuidString) --json",
                    reason: "Read workflow status after the App host consumes the handoff command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(workflowID.uuidString) --json",
                    reason: "Inspect run history after the App host starts or finishes the workflow."
                )
            ]
        case .cancelRun:
            nextActions = [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow handoff status \(payload.command.id.uuidString) --json",
                    reason: "Check whether the running App host has dispatched or rejected the cancellation command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status --json",
                    reason: "Read workflow status after the App host consumes the cancellation command."
                )
            ]
        }

        return AutomationCLIResultEnvelope<AutomationRuntimeHandoffPayload>(
            ok: true,
            command: command,
            data: payload,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowBoundWindowAcceptancePayload {
    static func workflowBoundWindowAcceptance(
        command: String,
        payload: AutomationWorkflowBoundWindowAcceptancePayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowBoundWindowAcceptancePayload> {
        var warnings: [AutomationCLIMessage] = []
        if !payload.resourceRequiresForegroundInput {
            warnings.append(AutomationCLIMessage(
                code: "foregroundInputNotRequired",
                message: "The selected workflow task does not require the foregroundInput resource."
            ))
        }
        for result in payload.activationResults where result.errorMessage != nil || !result.didActivate {
            warnings.append(AutomationCLIMessage(
                code: "targetActivationIncomplete",
                message: result.errorMessage ?? "Target app '\(result.bundleIdentifier)' was not activated."
            ))
        }

        var nextActions: [AutomationCLINextAction] = []
        if let handoff = payload.handoff {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow handoff status \(handoff.command.id.uuidString) --json",
                reason: "Check whether the running App host consumed the live bound-window playback command."
            ))
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow runs \(payload.workflowID.uuidString) --json",
                reason: "Inspect the run created by the App-host workflow playback."
            ))
        } else {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow acceptance bound-window \(payload.workflowID.uuidString) --task \"\(payload.taskName)\" --activate-target --json",
                reason: "Activate the bound target app/window without enqueuing playback."
            ))
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow acceptance bound-window \(payload.workflowID.uuidString) --task \"\(payload.taskName)\" --activate-target --confirm-playback --handoff app --json",
                reason: "Run the same bound-window workflow path through the App host after review."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowBoundWindowAcceptancePayload>(
            ok: payload.readyForBoundWindowPlayback && warnings.isEmpty,
            command: command,
            data: payload,
            warnings: warnings,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationRuntimeHandoffStatusPayload {
    static func workflowHandoffStatus(
        command: String,
        payload: AutomationRuntimeHandoffStatusPayload
    ) -> AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload> {
        var nextActions: [AutomationCLINextAction] = []
        switch payload.state {
        case .pending:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow handoff status \(payload.commandID.uuidString) --json",
                reason: "Poll until the running App host records a dispatched or failed receipt."
            ))
        case .dispatched:
            if let workflowID = payload.workflowID {
                nextActions.append(AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflowID.uuidString) --json",
                    reason: "Read workflow status after the App host dispatched the command."
                ))
                nextActions.append(AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(workflowID.uuidString) --json",
                    reason: "Inspect run history for the dispatched command."
                ))
            }
        case .failed:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow handoff status \(payload.commandID.uuidString) --json",
                reason: "Review the failed handoff receipt before retrying the command."
            ))
        case .missing:
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow run <workflow-id> --task <task> --confirm --handoff app --json",
                reason: "Create a new App-host handoff command if this command ID is not known."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationRuntimeHandoffStatusPayload>(
            ok: payload.state != .missing,
            command: command,
            data: payload,
            nextActions: nextActions
        )
    }
}

private extension AutomationRuntimeHandoffStatusPayload {
    var workflowID: UUID? {
        if let workflowStatus {
            return workflowStatus.summary.id
        }
        if let workflowID = runs.first?.workflowID {
            return workflowID
        }
        if let command {
            switch command.kind {
            case .manualStart(let workflowID, _):
                return workflowID
            case .cancelRun:
                return nil
            }
        }
        if let receipt {
            switch receipt.commandKind {
            case .manualStart(let workflowID, _):
                return workflowID
            case .cancelRun:
                return nil
            }
        }
        return nil
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowListPayload {
    static func workflowList(
        command: String,
        workflows: [AutomationWorkflow],
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowListPayload> {
        let runsByWorkflow = Dictionary(grouping: runHistory, by: \.workflowID)
        let summaries = workflows
            .map { workflow in
                AutomationWorkflowSummary(
                    workflow: workflow,
                    runs: runsByWorkflow[workflow.id] ?? []
                )
            }
            .sorted { left, right in
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt > right.modifiedAt
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

        return AutomationCLIResultEnvelope<AutomationWorkflowListPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowListPayload(workflows: summaries),
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow show <workflow-id> --json",
                    reason: "Inspect a workflow before exporting or running it."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowRunPayload {
    static func workflowRun(
        command: String,
        payload: AutomationWorkflowRunPayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowRunPayload> {
        var warnings: [AutomationCLIMessage] = []
        if payload.timedOut {
            warnings.append(AutomationCLIMessage(
                code: "runWaitTimedOut",
                message: "Workflow run did not reach a terminal state before the wait timeout."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowRunPayload>(
            ok: payload.startedRunID != nil && !payload.timedOut,
            command: command,
            data: payload,
            warnings: warnings,
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(payload.workflowID.uuidString) --json",
                    reason: "Read the latest workflow status after this runtime command."
                ),
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow runs \(payload.workflowID.uuidString) --json",
                    reason: "Inspect run history and outcomes for this workflow."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowCancelPayload {
    static func workflowCancel(
        command: String,
        payload: AutomationWorkflowCancelPayload
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowCancelPayload>(
            ok: payload.cancelled || payload.run?.isTerminal == true,
            command: command,
            data: payload,
            warnings: payload.cancelled ? [] : [
                AutomationCLIMessage(
                    code: "runAlreadyTerminal",
                    message: "The requested run was already terminal or could not be cancelled from this runtime session."
                )
            ],
            nextActions: payload.workflowStatus.map { status in
                [
                    AutomationCLINextAction(
                        command: "SparkleRecorder workflow status \(status.summary.id.uuidString) --json",
                        reason: "Read the workflow status after cancellation."
                    )
                ]
            } ?? []
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowRunsPayload {
    static func workflowRuns(
        command: String,
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowRunsPayload> {
        let payload = AutomationWorkflowRunsPayload(workflow: workflow, runHistory: runHistory)
        return AutomationCLIResultEnvelope<AutomationWorkflowRunsPayload>(
            ok: true,
            command: command,
            data: payload,
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow status \(workflow.id.uuidString) --json",
                    reason: "Read the summarized workflow status for these runs."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowStatusPayload {
    static func workflowStatus(
        command: String,
        workflows: [AutomationWorkflow],
        runHistory: [AutomationTaskRun],
        generatedAt: Date = Date.now
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload> {
        let statuses = workflows
            .map { workflow in
                AutomationWorkflowStatus(workflow: workflow, runHistory: runHistory)
            }
            .sorted { left, right in
                if left.summary.modifiedAt != right.summary.modifiedAt {
                    return left.summary.modifiedAt > right.summary.modifiedAt
                }
                return left.summary.name.localizedCaseInsensitiveCompare(right.summary.name) == .orderedAscending
            }

        var nextActions: [AutomationCLINextAction] = []
        if statuses.isEmpty {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow import <draft.json> --confirm --json",
                reason: "Import a validated workflow draft before checking runtime status."
            ))
        } else {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow show <workflow-id> --json",
                reason: "Inspect the workflow graph and run history for a status item."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowStatusPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowStatusPayload(
                workflows: statuses,
                generatedAt: generatedAt
            ),
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowShowPayload {
    static func workflowShow(
        command: String,
        workflow: AutomationWorkflow,
        runHistory: [AutomationTaskRun]
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowShowPayload> {
        AutomationCLIResultEnvelope<AutomationWorkflowShowPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowShowPayload(
                workflow: workflow,
                runHistory: runHistory
            ),
            warnings: workflow.validationIssues().map { issue in
                AutomationCLIMessage(
                    code: "workflowValidationIssue",
                    message: "Workflow validation issue: \(issue)."
                )
            },
            nextActions: [
                AutomationCLINextAction(
                    command: "SparkleRecorder workflow export \(workflow.id.uuidString) --format draft-json --json",
                    reason: "Export this workflow to an AI-editable draft before asking an agent to modify it."
                )
            ]
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftExportPayload {
    static func workflowDraftExport(
        command: String,
        result: AutomationWorkflowDraftExportResult,
        wrotePath: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload> {
        let warnings = result.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if result.isExportable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <exported-draft.json> --json",
                reason: "Validate the exported draft before editing or re-importing it."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftExportPayload>(
            ok: result.isExportable,
            command: command,
            data: AutomationWorkflowDraftExportPayload(result: result, wrotePath: wrotePath),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftEditPayload {
    static func workflowDraftEdit(
        command: String,
        result: AutomationWorkflowDraftEditResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload> {
        let warnings = result.validation.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validation.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isValid {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --json",
                reason: "Fix draft errors before simulating or importing this workflow."
            ))
        } else if result.document.workflow.tasks.isEmpty {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft task add <draft.json> --key <task-key> --type macro --json",
                reason: "Add at least one task to make the workflow useful."
            ))
        } else {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft simulate <draft.json> --json",
                reason: "Preview task order, branches, and resource usage before import."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftEditPayload>(
            ok: true,
            command: command,
            data: AutomationWorkflowDraftEditPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

private extension AutomationOutcome {
    var needsWorkflowAttention: Bool {
        switch self {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return false
        case .failed, .cancelled, .timedOut, .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return true
        }
    }

    var workflowAttentionDetail: String {
        switch self {
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return "最近一次运行已完成。"
        case .failed:
            return "最近一次运行失败。"
        case .cancelled(let reason):
            return reason.map { "最近一次运行已取消：\($0)" } ?? "最近一次运行已取消。"
        case .timedOut:
            return "最近一次运行超时。"
        case .resourceConflict(let resource):
            return resource.map { "资源冲突：\($0.rawValue)。" } ?? "最近一次运行发生资源冲突。"
        case .permissionDenied(let permission, let message):
            return "缺少权限 \(permission.rawValue)：\(message)"
        case .missingMacro(let macroID):
            return "缺少宏 \(macroID.uuidString)。"
        case .rejected(let reason):
            return "运行被拒绝：\(reason)"
        }
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftImportPayload {
    static func workflowDraftImport(
        command: String,
        result: AutomationWorkflowDraftImportResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload> {
        let warnings = result.validationIssues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validationIssues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isImportable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --macro-catalog <catalog.json> --json",
                reason: "Fix import-blocking draft issues before confirming this workflow."
            ))
        } else if result.mode == .dryRun {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow import <draft.json> --confirm --json",
                reason: "Dry-run passed; confirm import once UI preview and user review are complete."
            ))
        } else if let workflowID = result.workflow?.id {
            nextActions.append(AutomationCLINextAction(
                command: "Open SparkleRecorder Workflow page",
                reason: "Workflow \(workflowID.uuidString) was imported; review it in the app before running mouse or keyboard automation."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>(
            ok: result.isImportable,
            command: command,
            data: AutomationWorkflowDraftImportPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftSimulationPayload {
    static func workflowDraftSimulation(
        command: String,
        result: AutomationWorkflowDraftSimulationResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload> {
        let warnings = result.validationIssues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.validationIssues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        var nextActions: [AutomationCLINextAction] = []
        if !result.isSimulatable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft validate <draft.json> --json",
                reason: "Fix validation errors before simulating this workflow draft."
            ))
        }
        if result.steps.isEmpty && result.isSimulatable {
            nextActions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft task add <draft.json> --key <task-key> --type macro --json",
                reason: "Add at least one enabled root task so the simulation has a starting point."
            ))
        }

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>(
            ok: result.isSimulatable,
            command: command,
            data: AutomationWorkflowDraftSimulationPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions
        )
    }
}

public extension AutomationCLIResultEnvelope where Value == AutomationWorkflowDraftValidationPayload {
    static func workflowDraftValidation(
        command: String,
        result: AutomationWorkflowDraftValidationResult
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload> {
        let warnings = result.issues
            .filter { $0.severity != .error }
            .map(AutomationCLIMessage.init(issue:))
        let errors = result.issues
            .filter { $0.severity == .error }
            .map(AutomationCLIMessage.init(issue:))

        return AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>(
            ok: result.isValid,
            command: command,
            data: AutomationWorkflowDraftValidationPayload(result: result),
            warnings: warnings,
            errors: errors,
            nextActions: nextActions(for: result)
        )
    }

    static func workflowDraftValidationFailure(
        command: String,
        code: String,
        message: String,
        path: String? = nil
    ) -> AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload> {
        failure(command: command, code: code, message: message, path: path)
    }

    private static func nextActions(
        for result: AutomationWorkflowDraftValidationResult
    ) -> [AutomationCLINextAction] {
        var actions: [AutomationCLINextAction] = []
        if result.issues.contains(where: { $0.code == .ambiguousMacroRef || $0.code == .missingMacroRef }) {
            actions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow macros --json",
                reason: "Choose an exact macro ID from the local macro catalog."
            ))
        }
        if result.issues.contains(where: { $0.code == .missingTimeoutBranch }) {
            actions.append(AutomationCLINextAction(
                command: "SparkleRecorder workflow draft dependency add <draft.json> --from <task-key> --to <fallback-task-key> --trigger timeout --json",
                reason: "Add an explicit timeout branch so long waits have a visible fallback."
            ))
        }
        return actions
    }
}

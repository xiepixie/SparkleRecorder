import Foundation

public enum SemanticRecordingBundleReadinessStatus: String, Codable, Equatable, Sendable {
    case ready
    case degraded
    case notReady
}

public enum SemanticRecordingBundleReadinessSeverity: String, Codable, Equatable, Sendable {
    case blocking
    case degraded
    case note
}

public enum SemanticRecordingBundleReadinessIssueCode: String, Codable, Equatable, Sendable {
    case invalidBundle
    case missingVideoSegment
    case missingKeyframe
    case missingTimelineEvent
    case missingAISafeEvent
    case missingOCRObservation
    case missingWindowOrAXObservation
    case frameMissingVideoSegment
    case frameMissingVideoTime
    case timelineEventMissingFrame
    case semanticEventMissingFrame
    case redactingSuppressionMissingFrameRedaction
    case redactingSuppressionMissingVideoRedaction
    case redactingSuppressionHasNoVisualEvidence
}

public struct SemanticRecordingBundleReadinessIssue: Codable, Equatable, Sendable {
    public var code: SemanticRecordingBundleReadinessIssueCode
    public var severity: SemanticRecordingBundleReadinessSeverity
    public var message: String
    public var frameID: UUID?
    public var videoSegmentID: UUID?
    public var timelineEventID: UUID?
    public var semanticEventID: UUID?
    public var suppressionID: UUID?

    public init(
        code: SemanticRecordingBundleReadinessIssueCode,
        severity: SemanticRecordingBundleReadinessSeverity,
        message: String,
        frameID: UUID? = nil,
        videoSegmentID: UUID? = nil,
        timelineEventID: UUID? = nil,
        semanticEventID: UUID? = nil,
        suppressionID: UUID? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.frameID = frameID
        self.videoSegmentID = videoSegmentID
        self.timelineEventID = timelineEventID
        self.semanticEventID = semanticEventID
        self.suppressionID = suppressionID
    }
}

public struct SemanticRecordingBundleReadinessPolicy: Codable, Equatable, Sendable {
    public var requiresVideoSegments: Bool
    public var requiresEventAlignedKeyframes: Bool
    public var requiresTimelineEvents: Bool
    public var requiresAISafeEvents: Bool
    public var requiresOCRObservations: Bool
    public var requiresWindowOrAXObservations: Bool
    public var requiresRedactionSidecars: Bool

    public init(
        capturePolicy: RecordingCapturePolicy = RecordingCapturePolicy(),
        requiresTimelineEvents: Bool = true,
        requiresAISafeEvents: Bool = true,
        requiresOCRObservations: Bool = false,
        requiresWindowOrAXObservations: Bool = false,
        requiresRedactionSidecars: Bool = true
    ) {
        self.requiresVideoSegments = capturePolicy.recordsVideo
        self.requiresEventAlignedKeyframes = capturePolicy.recordsKeyframes
        self.requiresTimelineEvents = requiresTimelineEvents
        self.requiresAISafeEvents = requiresAISafeEvents
        self.requiresOCRObservations = requiresOCRObservations
        self.requiresWindowOrAXObservations = requiresWindowOrAXObservations
        self.requiresRedactionSidecars = requiresRedactionSidecars
    }
}

public struct SemanticRecordingBundleReadiness: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var status: SemanticRecordingBundleReadinessStatus
    public var policy: SemanticRecordingBundleReadinessPolicy
    public var issues: [SemanticRecordingBundleReadinessIssue]

    public init(
        recordingID: UUID,
        status: SemanticRecordingBundleReadinessStatus,
        policy: SemanticRecordingBundleReadinessPolicy,
        issues: [SemanticRecordingBundleReadinessIssue]
    ) {
        self.recordingID = recordingID
        self.status = status
        self.policy = policy
        self.issues = issues
    }

    public var blockingIssueCount: Int {
        issues.filter { $0.severity == .blocking }.count
    }

    public var degradedIssueCount: Int {
        issues.filter { $0.severity == .degraded }.count
    }

    public static func evaluate(
        _ bundle: SemanticRecordingBundle,
        policy: SemanticRecordingBundleReadinessPolicy? = nil
    ) -> SemanticRecordingBundleReadiness {
        let resolvedPolicy = policy ?? SemanticRecordingBundleReadinessPolicy(
            capturePolicy: bundle.capturePolicy
        )
        let issues = makeIssues(for: bundle, policy: resolvedPolicy)
        return SemanticRecordingBundleReadiness(
            recordingID: bundle.id,
            status: status(for: issues),
            policy: resolvedPolicy,
            issues: issues
        )
    }

    private static func makeIssues(
        for bundle: SemanticRecordingBundle,
        policy: SemanticRecordingBundleReadinessPolicy
    ) -> [SemanticRecordingBundleReadinessIssue] {
        var issues: [SemanticRecordingBundleReadinessIssue] = []
        let validationIssues = bundle.validate()
        if !validationIssues.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .invalidBundle,
                    severity: .blocking,
                    message: "Bundle validation reported \(validationIssues.count) schema/reference issue(s)."
                )
            )
        }

        if policy.requiresVideoSegments && bundle.videoSegments.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingVideoSegment,
                    severity: .blocking,
                    message: "Capture policy records video, but the bundle has no video segment."
                )
            )
        }
        if policy.requiresEventAlignedKeyframes && bundle.frames.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingKeyframe,
                    severity: .blocking,
                    message: "Capture policy records keyframes, but the bundle has no frame reference."
                )
            )
        }
        if policy.requiresTimelineEvents && bundle.timelineEvents.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingTimelineEvent,
                    severity: .blocking,
                    message: "Bundle has no timeline events to align playable actions with visual evidence."
                )
            )
        }
        if policy.requiresAISafeEvents && bundle.semanticEvents.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingAISafeEvent,
                    severity: .blocking,
                    message: "Bundle has no AI-safe semantic events."
                )
            )
        }
        if policy.requiresOCRObservations &&
            !bundle.visualObservations.contains(where: { $0.kind == .ocrText }) {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingOCRObservation,
                    severity: .degraded,
                    message: "Bundle has no OCR text observation for text search or OCR conditions."
                )
            )
        }
        if policy.requiresWindowOrAXObservations &&
            !bundle.visualObservations.contains(where: { $0.kind == .axElement || $0.kind == .windowSnapshot }) {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .missingWindowOrAXObservation,
                    severity: .degraded,
                    message: "Bundle has no window snapshot or AX element observation."
                )
            )
        }

        if policy.requiresVideoSegments && !bundle.videoSegments.isEmpty {
            issues.append(contentsOf: frameVideoAlignmentIssues(in: bundle))
        }
        issues.append(contentsOf: eventFrameAlignmentIssues(in: bundle))

        if policy.requiresRedactionSidecars {
            issues.append(contentsOf: redactionReadinessIssues(in: bundle))
        }

        return issues
    }

    private static func frameVideoAlignmentIssues(
        in bundle: SemanticRecordingBundle
    ) -> [SemanticRecordingBundleReadinessIssue] {
        bundle.frames.flatMap { frame -> [SemanticRecordingBundleReadinessIssue] in
            var issues: [SemanticRecordingBundleReadinessIssue] = []
            if frame.videoSegmentID == nil {
                issues.append(
                    SemanticRecordingBundleReadinessIssue(
                        code: .frameMissingVideoSegment,
                        severity: .blocking,
                        message: "Frame has no video segment id even though video capture is required.",
                        frameID: frame.id
                    )
                )
            }
            if frame.videoTime == nil {
                issues.append(
                    SemanticRecordingBundleReadinessIssue(
                        code: .frameMissingVideoTime,
                        severity: .blocking,
                        message: "Frame has no video-relative timestamp even though video capture is required.",
                        frameID: frame.id,
                        videoSegmentID: frame.videoSegmentID
                    )
                )
            }
            return issues
        }
    }

    private static func eventFrameAlignmentIssues(
        in bundle: SemanticRecordingBundle
    ) -> [SemanticRecordingBundleReadinessIssue] {
        var issues: [SemanticRecordingBundleReadinessIssue] = []
        for event in bundle.timelineEvents where event.kind == .recordedEvent && event.frameID == nil {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .timelineEventMissingFrame,
                    severity: .degraded,
                    message: "Recorded timeline event has no frame id for Review navigation.",
                    timelineEventID: event.id
                )
            )
        }
        for event in bundle.semanticEvents where event.frameID == nil && event.evidenceFrameIDs.isEmpty {
            issues.append(
                SemanticRecordingBundleReadinessIssue(
                    code: .semanticEventMissingFrame,
                    severity: .degraded,
                    message: "AI-safe semantic event has no direct or evidence frame reference.",
                    semanticEventID: event.id
                )
            )
        }
        return issues
    }

    private static func redactionReadinessIssues(
        in bundle: SemanticRecordingBundle
    ) -> [SemanticRecordingBundleReadinessIssue] {
        var issues: [SemanticRecordingBundleReadinessIssue] = []
        for suppression in bundle.suppressions where suppression.reason.redactsSemanticEvidence {
            let frames = matchingFrames(for: suppression, in: bundle)
            let videos = matchingVideoSegments(
                for: suppression,
                matchingFrames: frames,
                in: bundle
            )
            if frames.isEmpty && videos.isEmpty {
                issues.append(
                    SemanticRecordingBundleReadinessIssue(
                        code: .redactingSuppressionHasNoVisualEvidence,
                        severity: .note,
                        message: "Redacting suppression did not match captured frame or video evidence.",
                        suppressionID: suppression.id
                    )
                )
            }
            for frame in frames where !hasRenderedFrameRedaction(
                for: frame.id,
                suppressionID: suppression.id,
                in: bundle
            ) {
                issues.append(
                    SemanticRecordingBundleReadinessIssue(
                        code: .redactingSuppressionMissingFrameRedaction,
                        severity: .blocking,
                        message: "Redacting suppression matches a frame but no rendered redacted frame sidecar records it.",
                        frameID: frame.id,
                        suppressionID: suppression.id
                    )
                )
            }
            for video in videos where !hasRenderedVideoRedaction(
                for: video.id,
                suppressionID: suppression.id,
                in: bundle
            ) {
                issues.append(
                    SemanticRecordingBundleReadinessIssue(
                        code: .redactingSuppressionMissingVideoRedaction,
                        severity: .blocking,
                        message: "Redacting suppression matches a video segment but no rendered redacted video sidecar records it.",
                        videoSegmentID: video.id,
                        suppressionID: suppression.id
                    )
                )
            }
        }
        return issues
    }

    private static func matchingFrames(
        for suppression: RecordingSuppressionRecord,
        in bundle: SemanticRecordingBundle
    ) -> [RecordingFrameReference] {
        var matchedFrameIDs = Set<UUID>()
        if let frameID = suppression.frameID {
            matchedFrameIDs.insert(frameID)
        }
        if let eventID = suppression.eventID {
            matchedFrameIDs.formUnion(bundle.frames(relatedToEventID: eventID).map(\.id))
            if let frameID = bundle.timelineEvents.first(where: { $0.id == eventID })?.frameID {
                matchedFrameIDs.insert(frameID)
            }
        }
        if let timeRange = suppression.timeRange {
            matchedFrameIDs.formUnion(
                bundle.frames
                    .filter { timeRange.contains($0.recordingTime) }
                    .map(\.id)
            )
        } else if let recordingTime = suppression.recordingTime {
            matchedFrameIDs.formUnion(
                bundle.frames
                    .filter { abs($0.recordingTime - recordingTime) <= 0.001 }
                    .map(\.id)
            )
        }
        return bundle.frames.filter { matchedFrameIDs.contains($0.id) }
    }

    private static func matchingVideoSegments(
        for suppression: RecordingSuppressionRecord,
        matchingFrames: [RecordingFrameReference],
        in bundle: SemanticRecordingBundle
    ) -> [RecordingVideoSegment] {
        var matchedVideoIDs = Set<UUID>()
        matchedVideoIDs.formUnion(matchingFrames.compactMap(\.videoSegmentID))
        if let eventID = suppression.eventID,
           let videoSegmentID = bundle.timelineEvents.first(where: { $0.id == eventID })?.videoSegmentID {
            matchedVideoIDs.insert(videoSegmentID)
        }
        if let timeRange = suppression.timeRange {
            matchedVideoIDs.formUnion(
                bundle.videoSegments
                    .filter { $0.endTime >= timeRange.startTime && $0.startTime <= timeRange.endTime }
                    .map(\.id)
            )
        } else if let recordingTime = suppression.recordingTime {
            matchedVideoIDs.formUnion(
                bundle.videoSegments
                    .filter { $0.contains(recordingTime) }
                    .map(\.id)
            )
        }
        return bundle.videoSegments.filter { matchedVideoIDs.contains($0.id) }
    }

    private static func hasRenderedFrameRedaction(
        for frameID: UUID,
        suppressionID: UUID,
        in bundle: SemanticRecordingBundle
    ) -> Bool {
        bundle.redactedFrames.contains { redaction in
            redaction.frameID == frameID &&
                redaction.sourceSuppressionIDs.contains(suppressionID)
        }
    }

    private static func hasRenderedVideoRedaction(
        for videoSegmentID: UUID,
        suppressionID: UUID,
        in bundle: SemanticRecordingBundle
    ) -> Bool {
        bundle.redactedVideos.contains { redaction in
            redaction.videoSegmentID == videoSegmentID &&
                redaction.sourceSuppressionIDs.contains(suppressionID)
        }
    }

    private static func status(
        for issues: [SemanticRecordingBundleReadinessIssue]
    ) -> SemanticRecordingBundleReadinessStatus {
        if issues.contains(where: { $0.severity == .blocking }) {
            return .notReady
        }
        if issues.contains(where: { $0.severity == .degraded }) {
            return .degraded
        }
        return .ready
    }
}

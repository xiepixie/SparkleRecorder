import Foundation

public struct SemanticRecordingDebugSmokePersistedBundleLoadEvidence: Codable, Equatable, Sendable {
    public var reloaded: Bool
    public var degraded: Bool
    public var videoSegmentCount: Int
    public var frameCount: Int
    public var timelineEventCount: Int
    public var aiSafeEventCount: Int
    public var visualObservationCount: Int
    public var suppressionCount: Int
    public var redactedFrameCount: Int
    public var redactedVideoCount: Int
    public var sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics

    public init(
        reloaded: Bool,
        degraded: Bool,
        videoSegmentCount: Int = 0,
        frameCount: Int = 0,
        timelineEventCount: Int = 0,
        aiSafeEventCount: Int = 0,
        visualObservationCount: Int = 0,
        suppressionCount: Int = 0,
        redactedFrameCount: Int = 0,
        redactedVideoCount: Int = 0,
        sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics = SemanticRecordingBundleSidecarLoadDiagnostics()
    ) {
        self.reloaded = reloaded
        self.degraded = degraded
        self.videoSegmentCount = max(0, videoSegmentCount)
        self.frameCount = max(0, frameCount)
        self.timelineEventCount = max(0, timelineEventCount)
        self.aiSafeEventCount = max(0, aiSafeEventCount)
        self.visualObservationCount = max(0, visualObservationCount)
        self.suppressionCount = max(0, suppressionCount)
        self.redactedFrameCount = max(0, redactedFrameCount)
        self.redactedVideoCount = max(0, redactedVideoCount)
        self.sidecarDiagnostics = sidecarDiagnostics
    }

    public init(loadResult: SemanticRecordingBundleLoadResult) {
        let bundle = loadResult.bundle
        self.init(
            reloaded: true,
            degraded: loadResult.sidecarDiagnostics.isDegraded,
            videoSegmentCount: bundle.videoSegments.count,
            frameCount: bundle.frames.count,
            timelineEventCount: bundle.timelineEvents.count,
            aiSafeEventCount: bundle.aiSafeEvents.count,
            visualObservationCount: bundle.visualObservations.count,
            suppressionCount: bundle.suppressions.count,
            redactedFrameCount: bundle.redactedFrames.count,
            redactedVideoCount: bundle.redactedVideos.count,
            sidecarDiagnostics: loadResult.sidecarDiagnostics
        )
    }
}

public struct SemanticRecordingDebugSmokeCommandPlan: Codable, Equatable, Sendable {
    public var invocationCommand: String
    public var preflightCommand: String
    public var liveCaptureCommand: String

    public init(
        invocationCommand: String,
        preflightCommand: String,
        liveCaptureCommand: String
    ) {
        self.invocationCommand = invocationCommand
        self.preflightCommand = preflightCommand
        self.liveCaptureCommand = liveCaptureCommand
    }
}

public enum SemanticRecordingDebugSmokePersistedBundleCountField: String, Codable, Equatable, Sendable {
    case video
    case frames
    case timeline
    case aiSafe
    case observations
    case suppressions
    case redactedFrames
    case redactedVideos
}

public enum SemanticRecordingDebugSmokePersistedBundleCountCheckStatus: String, Codable, Equatable, Sendable {
    case none
    case matched
    case mismatched
}

public struct SemanticRecordingDebugSmokePersistedBundleCountMismatch: Codable, Equatable, Sendable {
    public var field: SemanticRecordingDebugSmokePersistedBundleCountField
    public var memoryCount: Int
    public var persistedCount: Int

    public init(
        field: SemanticRecordingDebugSmokePersistedBundleCountField,
        memoryCount: Int,
        persistedCount: Int
    ) {
        self.field = field
        self.memoryCount = max(0, memoryCount)
        self.persistedCount = max(0, persistedCount)
    }

    public var summary: String {
        "\(field.rawValue)=memory:\(memoryCount) persisted:\(persistedCount)"
    }
}

public struct SemanticRecordingDebugSmokePersistedBundleCountCheck: Codable, Equatable, Sendable {
    public var status: SemanticRecordingDebugSmokePersistedBundleCountCheckStatus
    public var mismatches: [SemanticRecordingDebugSmokePersistedBundleCountMismatch]

    public init(
        status: SemanticRecordingDebugSmokePersistedBundleCountCheckStatus,
        mismatches: [SemanticRecordingDebugSmokePersistedBundleCountMismatch] = []
    ) {
        self.status = status
        self.mismatches = status == .mismatched ? mismatches : []
    }

    public static let none = SemanticRecordingDebugSmokePersistedBundleCountCheck(status: .none)
    public static let matched = SemanticRecordingDebugSmokePersistedBundleCountCheck(status: .matched)

    public static func evaluate(
        videoSegmentCount: Int,
        frameCount: Int,
        timelineEventCount: Int,
        aiSafeEventCount: Int,
        visualObservationCount: Int,
        suppressionCount: Int,
        redactedFrameCount: Int,
        redactedVideoCount: Int,
        persistedBundleLoad evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> SemanticRecordingDebugSmokePersistedBundleCountCheck {
        guard let evidence else {
            return .none
        }

        let mismatches = [
            mismatch(field: .video, memory: videoSegmentCount, persisted: evidence.videoSegmentCount),
            mismatch(field: .frames, memory: frameCount, persisted: evidence.frameCount),
            mismatch(field: .timeline, memory: timelineEventCount, persisted: evidence.timelineEventCount),
            mismatch(field: .aiSafe, memory: aiSafeEventCount, persisted: evidence.aiSafeEventCount),
            mismatch(field: .observations, memory: visualObservationCount, persisted: evidence.visualObservationCount),
            mismatch(field: .suppressions, memory: suppressionCount, persisted: evidence.suppressionCount),
            mismatch(field: .redactedFrames, memory: redactedFrameCount, persisted: evidence.redactedFrameCount),
            mismatch(field: .redactedVideos, memory: redactedVideoCount, persisted: evidence.redactedVideoCount)
        ].compactMap { $0 }

        guard !mismatches.isEmpty else {
            return .matched
        }
        return SemanticRecordingDebugSmokePersistedBundleCountCheck(
            status: .mismatched,
            mismatches: mismatches
        )
    }

    public var summary: String {
        switch status {
        case .none:
            return "none"
        case .matched:
            return "matched"
        case .mismatched:
            guard !mismatches.isEmpty else {
                return "mismatched"
            }
            return mismatches
                .map(\.summary)
                .joined(separator: ", ")
        }
    }

    private static func mismatch(
        field: SemanticRecordingDebugSmokePersistedBundleCountField,
        memory: Int,
        persisted: Int
    ) -> SemanticRecordingDebugSmokePersistedBundleCountMismatch? {
        guard memory != persisted else {
            return nil
        }
        return SemanticRecordingDebugSmokePersistedBundleCountMismatch(
            field: field,
            memoryCount: memory,
            persistedCount: persisted
        )
    }
}

public struct SemanticRecordingDebugSmokeEvidenceInput: Equatable, Sendable {
    public var status: String
    public var command: String
    public var commandPlan: SemanticRecordingDebugSmokeCommandPlan?
    public var generatedAt: Date
    public var recordingID: UUID
    public var capturePolicy: RecordingCapturePolicy
    public var captureTarget: RecordingCaptureTarget
    public var preflight: SemanticRecordingPreflightResult
    public var bundleDirectory: String?
    public var manifestPath: String?
    public var evidenceSidecarPath: String?
    public var videoSegmentCount: Int
    public var frameCount: Int
    public var timelineEventCount: Int
    public var aiSafeEventCount: Int
    public var visualObservationCount: Int
    public var suppressionCount: Int
    public var syntheticSuppressionCount: Int
    public var syntheticRedactionReason: RecordingSuppressionReason?
    public var bundleReadinessPolicy: SemanticRecordingBundleReadinessPolicy?
    public var bundleReadinessStatus: SemanticRecordingBundleReadinessStatus?
    public var bundleReadinessIssueCount: Int
    public var bundleReadinessBlockingIssueCount: Int
    public var bundleReadinessDegradedIssueCount: Int
    public var bundleReadinessIssues: [SemanticRecordingBundleReadinessIssue]
    public var bundleReadinessFollowUps: [String]
    public var redactedFrameCount: Int
    public var redactedFrameIndexPath: String?
    public var redactedVideoCount: Int
    public var redactedVideoIndexPath: String?
    public var pendingVideoRangeRedactionCount: Int
    public var persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?

    public init(
        status: String,
        command: String,
        commandPlan: SemanticRecordingDebugSmokeCommandPlan? = nil,
        generatedAt: Date = Date(),
        recordingID: UUID,
        capturePolicy: RecordingCapturePolicy,
        captureTarget: RecordingCaptureTarget,
        preflight: SemanticRecordingPreflightResult,
        bundleDirectory: String? = nil,
        manifestPath: String? = nil,
        evidenceSidecarPath: String? = nil,
        videoSegmentCount: Int = 0,
        frameCount: Int = 0,
        timelineEventCount: Int = 0,
        aiSafeEventCount: Int = 0,
        visualObservationCount: Int = 0,
        suppressionCount: Int = 0,
        syntheticSuppressionCount: Int = 0,
        syntheticRedactionReason: RecordingSuppressionReason? = nil,
        bundleReadinessPolicy: SemanticRecordingBundleReadinessPolicy? = nil,
        bundleReadinessStatus: SemanticRecordingBundleReadinessStatus? = nil,
        bundleReadinessIssueCount: Int = 0,
        bundleReadinessBlockingIssueCount: Int = 0,
        bundleReadinessDegradedIssueCount: Int = 0,
        bundleReadinessIssues: [SemanticRecordingBundleReadinessIssue] = [],
        bundleReadinessFollowUps: [String] = [],
        redactedFrameCount: Int = 0,
        redactedFrameIndexPath: String? = nil,
        redactedVideoCount: Int = 0,
        redactedVideoIndexPath: String? = nil,
        pendingVideoRangeRedactionCount: Int = 0,
        persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence? = nil
    ) {
        self.status = status
        self.command = command
        self.commandPlan = commandPlan
        self.generatedAt = generatedAt
        self.recordingID = recordingID
        self.capturePolicy = capturePolicy
        self.captureTarget = captureTarget
        self.preflight = preflight
        self.bundleDirectory = bundleDirectory
        self.manifestPath = manifestPath
        self.evidenceSidecarPath = evidenceSidecarPath
        self.videoSegmentCount = max(0, videoSegmentCount)
        self.frameCount = max(0, frameCount)
        self.timelineEventCount = max(0, timelineEventCount)
        self.aiSafeEventCount = max(0, aiSafeEventCount)
        self.visualObservationCount = max(0, visualObservationCount)
        self.suppressionCount = max(0, suppressionCount)
        self.syntheticSuppressionCount = max(0, syntheticSuppressionCount)
        self.syntheticRedactionReason = syntheticRedactionReason
        self.bundleReadinessPolicy = bundleReadinessPolicy
        self.bundleReadinessStatus = bundleReadinessStatus
        self.bundleReadinessIssueCount = max(0, bundleReadinessIssueCount)
        self.bundleReadinessBlockingIssueCount = max(0, bundleReadinessBlockingIssueCount)
        self.bundleReadinessDegradedIssueCount = max(0, bundleReadinessDegradedIssueCount)
        self.bundleReadinessIssues = bundleReadinessIssues
        self.bundleReadinessFollowUps = bundleReadinessFollowUps
        self.redactedFrameCount = max(0, redactedFrameCount)
        self.redactedFrameIndexPath = redactedFrameIndexPath
        self.redactedVideoCount = max(0, redactedVideoCount)
        self.redactedVideoIndexPath = redactedVideoIndexPath
        self.pendingVideoRangeRedactionCount = max(0, pendingVideoRangeRedactionCount)
        self.persistedBundleLoad = persistedBundleLoad
    }

    public var persistedBundleCountCheck: SemanticRecordingDebugSmokePersistedBundleCountCheck {
        SemanticRecordingDebugSmokePersistedBundleCountCheck.evaluate(
            videoSegmentCount: videoSegmentCount,
            frameCount: frameCount,
            timelineEventCount: timelineEventCount,
            aiSafeEventCount: aiSafeEventCount,
            visualObservationCount: visualObservationCount,
            suppressionCount: suppressionCount,
            redactedFrameCount: redactedFrameCount,
            redactedVideoCount: redactedVideoCount,
            persistedBundleLoad: persistedBundleLoad
        )
    }
}

public enum SemanticRecordingDebugSmokeEvidenceSidecar {
    public static func markdown(
        for input: SemanticRecordingDebugSmokeEvidenceInput
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let generatedAt = formatter.string(from: input.generatedAt)
        let checklist = checklistItem(for: input.status)
        let readiness = readinessSummary(for: input)
        let preflightPresentation = SemanticRecordingPreflightPresenter.presentation(
            for: input.preflight
        )

        return """
        # Semantic Recording Debug Smoke Evidence

        Capture date: \(generatedAt)
        Checklist item: \(checklist)
        Evidence source: live `semantic-recording debug-smoke` command output
        Command: \(input.command)
        Recording ID: \(input.recordingID.uuidString)
        Status: \(input.status)
        Readiness: \(readiness)

        ## Command Plan

        - invocation: \(input.commandPlan?.invocationCommand ?? input.command)
        - preflight: \(input.commandPlan?.preflightCommand ?? "none")
        - live capture: \(input.commandPlan?.liveCaptureCommand ?? "none")

        ## Capture Target

        - kind: \(input.captureTarget.kind.rawValue)
        - surface id: \(input.captureTarget.surfaceID ?? "none")
        - display id: \(input.captureTarget.displayID.map(String.init) ?? "none")
        - window id: \(input.captureTarget.windowID.map(String.init) ?? "none")
        - app bundle id: \(input.captureTarget.appBundleIdentifier ?? "none")
        - window title: \(input.captureTarget.windowTitle ?? "none")
        - policy mode: \(input.capturePolicy.mode.rawValue)

        ## Preflight

        - input monitoring: \(input.preflight.snapshot.inputMonitoring.rawValue)
        - screen recording: \(input.preflight.snapshot.screenRecording.rawValue)
        - accessibility: \(input.preflight.snapshot.accessibility.rawValue)
        - available capabilities: \(capabilityList(input.preflight.availableCapabilities))
        - blocking issues: \(issueList(input.preflight.blockingIssues))
        - degraded issues: \(issueList(input.preflight.degradedIssues))

        ## Preflight Guidance

        - status: \(preflightPresentation.status.rawValue)
        - can start: \(preflightPresentation.canStart)
        - title: \(preflightPresentation.title)
        - summary: \(preflightPresentation.summary)
        - available capability labels: \(preflightCapabilityLabelList(preflightPresentation.availableCapabilityLabels))
        - primary action: \(preflightActionSummary(preflightPresentation.primaryAction))
        - secondary action: \(preflightActionSummary(preflightPresentation.secondaryAction))
        - issue guidance: \(preflightIssueGuidanceList(preflightPresentation.issues))

        ## Bundle Evidence

        - bundle directory: \(input.bundleDirectory ?? "none")
        - manifest path: \(input.manifestPath ?? "none")
        - sidecar path: \(input.evidenceSidecarPath ?? "none")
        - video segments: \(input.videoSegmentCount)
        - frames: \(input.frameCount)
        - timeline events: \(input.timelineEventCount)
        - AI-safe events: \(input.aiSafeEventCount)
        - visual observations: \(input.visualObservationCount)
        - suppressions: \(input.suppressionCount)
        - synthetic suppressions: \(input.syntheticSuppressionCount)
        - synthetic redaction reason: \(input.syntheticRedactionReason?.rawValue ?? "none")
        - bundle readiness policy: \(readinessPolicySummary(input.bundleReadinessPolicy))
        - bundle readiness: \(input.bundleReadinessStatus?.rawValue ?? "none")
        - bundle readiness issues: \(input.bundleReadinessIssueCount)
        - bundle readiness blocking issues: \(input.bundleReadinessBlockingIssueCount)
        - bundle readiness degraded issues: \(input.bundleReadinessDegradedIssueCount)
        - bundle readiness issue details: \(readinessIssueList(input.bundleReadinessIssues))
        - bundle readiness follow-up: \(readinessFollowUpList(input.bundleReadinessFollowUps))
        - persisted bundle reload: \(persistedBundleReloadSummary(input.persistedBundleLoad))
        - persisted bundle counts: \(persistedBundleCountSummary(input.persistedBundleLoad))
        - persisted bundle count match: \(persistedBundleCountMatchSummary(input))
        - persisted bundle loaded sidecars: \(persistedBundleLoadedSidecars(input.persistedBundleLoad))
        - persisted bundle missing sidecars: \(persistedBundleMissingSidecars(input.persistedBundleLoad))
        - persisted bundle failed sidecars: \(persistedBundleFailedSidecars(input.persistedBundleLoad))

        ## Redaction Evidence

        - redacted frames: \(input.redactedFrameCount)
        - redacted frame index: \(input.redactedFrameIndexPath ?? "none")
        - redacted videos: \(input.redactedVideoCount)
        - redacted video index: \(input.redactedVideoIndexPath ?? "none")
        - pending video range redactions: \(input.pendingVideoRangeRedactionCount)

        ## Review Notes

        - This sidecar is generated evidence metadata. It does not by itself close S2 product evidence.
        - Keep the live recording bundle directory available until the manifest, video segment sidecar, frame index and redaction indexes have been reviewed.
        - If status is `blocked`, fix the listed preflight issues and rerun the same command before attempting live capture.
        - If status is `finished`, inspect `manifest.json`, `video/segments.json`, `frames/index.jsonl`, `timeline.jsonl`, `events.jsonl`, `ocr/observations.jsonl`, `suppressed.jsonl`, and any `redacted/*/index.json` sidecars.
        - Product evidence still needs a reviewed live clip or screenshot showing the user-facing flow when the target gate asks for UI proof.

        """
    }

    private static func checklistItem(for status: String) -> String {
        switch status {
        case "finished":
            return "S2 live semantic recording bundle smoke"
        case "preflightReady":
            return "S2 semantic recording preflight readiness"
        case "blocked":
            return "S2 semantic recording blocked preflight"
        default:
            return "S2 semantic recording debug smoke"
        }
    }

    private static func readinessSummary(
        for input: SemanticRecordingDebugSmokeEvidenceInput
    ) -> String {
        if input.status == "finished" {
            return "bundle written"
        }
        if input.preflight.isReadyToStart {
            return input.preflight.isDegraded ? "ready with degraded capabilities" : "ready"
        }
        return "blocked"
    }

    private static func capabilityList(
        _ capabilities: Set<SemanticRecordingPreflightCapability>
    ) -> String {
        guard !capabilities.isEmpty else {
            return "none"
        }
        return capabilities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
    }

    private static func issueList(
        _ issues: [SemanticRecordingPreflightIssue]
    ) -> String {
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .sorted { lhs, rhs in
                if lhs.permission.rawValue == rhs.permission.rawValue {
                    return lhs.message < rhs.message
                }
                return lhs.permission.rawValue < rhs.permission.rawValue
            }
            .map { issue in
                let capabilities = issue.affectedCapabilities
                    .map(\.rawValue)
                    .sorted()
                    .joined(separator: "+")
                return "\(issue.permission.rawValue)=\(issue.state.rawValue) \(issue.severity.rawValue) [\(capabilities)] \(issue.message)"
            }
            .joined(separator: " | ")
    }

    private static func preflightCapabilityLabelList(
        _ labels: [String]
    ) -> String {
        guard !labels.isEmpty else {
            return "none"
        }
        return labels.joined(separator: ", ")
    }

    private static func preflightActionSummary(
        _ action: SemanticRecordingPreflightPresentationAction?
    ) -> String {
        guard let action else {
            return "none"
        }
        return [
            "kind=\(action.kind.rawValue)",
            "label=\(action.label)",
            "permission=\(action.permission?.rawValue ?? "none")"
        ].joined(separator: " ")
    }

    private static func preflightIssueGuidanceList(
        _ issues: [SemanticRecordingPreflightIssuePresentation]
    ) -> String {
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .map { issue in
                [
                    "\(issue.permission.rawValue)=\(issue.severity.rawValue)",
                    "title=\(issue.title)",
                    "action=\(issue.action.kind.rawValue)",
                    "capabilities=\(preflightCapabilityLabelList(issue.affectedCapabilityLabels))"
                ].joined(separator: " ")
            }
            .joined(separator: " | ")
    }

    private static func readinessIssueList(
        _ issues: [SemanticRecordingBundleReadinessIssue]
    ) -> String {
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .map { issue in
                var parts = [
                    "\(issue.code.rawValue)=\(issue.severity.rawValue)",
                    issue.message
                ]
                if let frameID = issue.frameID {
                    parts.append("frame=\(frameID.uuidString)")
                }
                if let videoSegmentID = issue.videoSegmentID {
                    parts.append("video=\(videoSegmentID.uuidString)")
                }
                if let timelineEventID = issue.timelineEventID {
                    parts.append("timeline=\(timelineEventID.uuidString)")
                }
                if let semanticEventID = issue.semanticEventID {
                    parts.append("semantic=\(semanticEventID.uuidString)")
                }
                if let suppressionID = issue.suppressionID {
                    parts.append("suppression=\(suppressionID.uuidString)")
                }
                return parts.joined(separator: " ")
            }
            .joined(separator: " | ")
    }

    private static func readinessPolicySummary(
        _ policy: SemanticRecordingBundleReadinessPolicy?
    ) -> String {
        guard let policy else {
            return "none"
        }
        return [
            "video=\(policy.requiresVideoSegments)",
            "keyframes=\(policy.requiresEventAlignedKeyframes)",
            "timeline=\(policy.requiresTimelineEvents)",
            "aiSafe=\(policy.requiresAISafeEvents)",
            "ocr=\(policy.requiresOCRObservations)",
            "windowOrAX=\(policy.requiresWindowOrAXObservations)",
            "redactions=\(policy.requiresRedactionSidecars)"
        ].joined(separator: ", ")
    }

    private static func readinessFollowUpList(_ followUps: [String]) -> String {
        guard !followUps.isEmpty else {
            return "none"
        }
        return followUps.joined(separator: " | ")
    }

    private static func persistedBundleReloadSummary(
        _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> String {
        guard let evidence else {
            return "none"
        }
        return evidence.degraded ? "degraded" : "loaded"
    }

    private static func persistedBundleCountSummary(
        _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> String {
        guard let evidence else {
            return "none"
        }
        return [
            "video=\(evidence.videoSegmentCount)",
            "frames=\(evidence.frameCount)",
            "timeline=\(evidence.timelineEventCount)",
            "aiSafe=\(evidence.aiSafeEventCount)",
            "observations=\(evidence.visualObservationCount)",
            "suppressions=\(evidence.suppressionCount)",
            "redactedFrames=\(evidence.redactedFrameCount)",
            "redactedVideos=\(evidence.redactedVideoCount)"
        ].joined(separator: ", ")
    }

    private static func persistedBundleCountMatchSummary(
        _ input: SemanticRecordingDebugSmokeEvidenceInput
    ) -> String {
        input.persistedBundleCountCheck.summary
    }

    private static func persistedBundleLoadedSidecars(
        _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> String {
        sidecarKindList(evidence?.sidecarDiagnostics.loadedKinds ?? [])
    }

    private static func persistedBundleMissingSidecars(
        _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> String {
        sidecarKindList(evidence?.sidecarDiagnostics.missingKinds ?? [])
    }

    private static func persistedBundleFailedSidecars(
        _ evidence: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    ) -> String {
        guard let evidence else {
            return "none"
        }
        let issues = evidence.sidecarDiagnostics.failedIssues
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .map { issue in
                "\(issue.kind.rawValue)=failed path=\(issue.relativePath) fallback=\(issue.fallbackToManifest) \(issue.message)"
            }
            .joined(separator: " | ")
    }

    private static func sidecarKindList(
        _ kinds: [SemanticRecordingBundleSidecarKind]
    ) -> String {
        guard !kinds.isEmpty else {
            return "none"
        }
        return kinds
            .map(\.rawValue)
            .joined(separator: ", ")
    }
}

public struct SemanticRecordingDebugSmokeSyntheticRedaction: Equatable, Sendable {
    public var suppressionID: UUID
    public var reason: RecordingSuppressionReason
    public var eventTime: TimeInterval
    public var totalDuration: TimeInterval
    public var target: RecordingCaptureTarget
    public var createdAt: Date

    public init(
        suppressionID: UUID = UUID(),
        reason: RecordingSuppressionReason = .privateRegion,
        eventTime: TimeInterval,
        totalDuration: TimeInterval,
        target: RecordingCaptureTarget,
        createdAt: Date = Date()
    ) {
        self.suppressionID = suppressionID
        self.reason = reason
        self.eventTime = max(0, eventTime)
        self.totalDuration = max(0.001, totalDuration)
        self.target = target
        self.createdAt = createdAt
    }

    public var suppressionRecord: RecordingSuppressionRecord {
        RecordingSuppressionRecord(
            id: suppressionID,
            reason: reason,
            recordingTime: eventTime,
            timeRange: timeRange,
            target: target,
            detail: "Synthetic debug-smoke redaction trigger for S2 redaction pipeline verification.",
            createdAt: createdAt
        )
    }

    public var timeRange: RecordingTimeRange {
        let start = min(eventTime, totalDuration)
        let remaining = max(0.001, totalDuration - start)
        let requested = max(0.05, totalDuration * 0.25)
        return RecordingTimeRange(
            startTime: start,
            duration: min(requested, remaining)
        )
    }
}

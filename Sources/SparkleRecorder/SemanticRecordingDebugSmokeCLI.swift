import Foundation
import SparkleRecorderCore
import SparkleRecorderTooling

enum SemanticRecordingDebugSmokeStatus: String, Codable, Equatable, Sendable {
    case blocked
    case finished
    case preflightReady
}

struct SemanticRecordingDebugSmokePayload: Codable, Equatable, Sendable {
    var status: SemanticRecordingDebugSmokeStatus
    var recordingID: UUID
    var commandPlan: SemanticRecordingDebugSmokeCommandPlan?
    var capturePolicy: RecordingCapturePolicy
    var captureTarget: RecordingCaptureTarget
    var preflight: SemanticRecordingPreflightResult
    var preflightPresentation: SemanticRecordingPreflightPresentation
    var bundleDirectory: String?
    var manifestPath: String?
    var evidenceSidecarPath: String?
    var videoSegmentCount: Int
    var frameCount: Int
    var timelineEventCount: Int
    var aiSafeEventCount: Int
    var visualObservationCount: Int
    var suppressionCount: Int
    var syntheticSuppressionCount: Int
    var syntheticRedactionReason: RecordingSuppressionReason?
    var bundleReadinessPolicy: SemanticRecordingBundleReadinessPolicy
    var bundleReadinessStatus: SemanticRecordingBundleReadinessStatus?
    var bundleReadinessIssueCount: Int
    var bundleReadinessBlockingIssueCount: Int
    var bundleReadinessDegradedIssueCount: Int
    var bundleReadinessIssues: [SemanticRecordingBundleReadinessIssue]
    var bundleReadinessFollowUps: [String]
    var redactedFrameCount: Int
    var redactedFrameIndexPath: String?
    var redactedVideoCount: Int
    var redactedVideoIndexPath: String?
    var pendingVideoRangeRedactionCount: Int
    var persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence?
    var persistedBundleCountCheck: SemanticRecordingDebugSmokePersistedBundleCountCheck
}

enum SemanticRecordingDebugSmokeCLI {
    struct Request {
        var duration: TimeInterval
        var recordingID: UUID
        var rootDirectory: URL?
        var capturePolicy: RecordingCapturePolicy
        var preflightOnly: Bool
        var captureTarget: RecordingCaptureTarget
        var evidenceSidecarURL: URL?
        var syntheticRedactionReason: RecordingSuppressionReason?
        var readinessPolicy: SemanticRecordingBundleReadinessPolicy
        var commandPlan: SemanticRecordingDebugSmokeCommandPlan
    }

    static func run(
        _ arguments: [String],
        wantsJSON: Bool
    ) throws -> Int {
        let request = try parse(arguments)
        var payload = try waitForWorkflowCLIAsync {
            try await makePayload(request: request)
        }
        payload.commandPlan = request.commandPlan

        if let evidenceSidecarURL = request.evidenceSidecarURL {
            payload.evidenceSidecarPath = evidenceSidecarURL.path
            try writeEvidenceSidecar(
                payload,
                command: commandLine(arguments),
                to: evidenceSidecarURL
            )
        }

        let envelope = AutomationCLIResultEnvelope<SemanticRecordingDebugSmokePayload>(
            ok: payload.status != .blocked,
            command: "semantic-recording debug-smoke",
            data: payload,
            warnings: messages(from: payload.preflight.degradedIssues),
            errors: payload.status == .blocked
                ? messages(from: payload.preflight.blockingIssues)
                : [],
            nextActions: nextActions(payload)
        )

        if wantsJSON {
            writeWorkflowJSON(envelope)
        } else {
            writeSummary(payload)
        }
        return payload.status == .blocked ? 2 : 0
    }

    static func parse(_ arguments: [String]) throws -> Request {
        var duration: TimeInterval = 1.0
        var recordingID = UUID()
        var rootDirectory: URL?
        var keyframesOnly = false
        var preflightOnly = false
        var displayID: UInt32?
        var windowID: UInt32?
        var appBundleIdentifier: String?
        var windowTitle: String?
        var evidenceSidecarURL: URL?
        var syntheticRedactionReason: RecordingSuppressionReason?
        var requiresOCRReadiness = false
        var requiresWindowOrAXReadiness = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--json":
                break
            case "--duration":
                duration = try positiveDouble(arguments, index: index, option: token)
                index += 1
            case "--recording-id":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--recording-id requires a UUID.", path: token)
                }
                recordingID = try uuid(arguments[index + 1], path: token)
                index += 1
            case "--root-directory":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--root-directory requires a path.", path: token)
                }
                rootDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                index += 1
            case "--keyframes-only":
                keyframesOnly = true
            case "--preflight-only":
                preflightOnly = true
            case "--require-ocr":
                requiresOCRReadiness = true
            case "--require-window-or-ax":
                requiresWindowOrAXReadiness = true
            case "--display-id":
                guard index + 1 < arguments.count,
                      let parsedDisplayID = UInt32(arguments[index + 1]) else {
                    throw WorkflowCLIError("invalidArgument", "--display-id requires a UInt32 display ID.", path: token)
                }
                displayID = parsedDisplayID
                index += 1
            case "--window-id":
                guard index + 1 < arguments.count,
                      let parsedWindowID = UInt32(arguments[index + 1]) else {
                    throw WorkflowCLIError("invalidArgument", "--window-id requires a UInt32 window ID.", path: token)
                }
                windowID = parsedWindowID
                index += 1
            case "--app-bundle-id":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--app-bundle-id requires a bundle identifier.", path: token)
                }
                appBundleIdentifier = arguments[index + 1]
                index += 1
            case "--window-title":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--window-title requires a title.", path: token)
                }
                windowTitle = arguments[index + 1]
                index += 1
            case "--evidence-sidecar":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--evidence-sidecar requires a path.", path: token)
                }
                evidenceSidecarURL = URL(fileURLWithPath: arguments[index + 1])
                index += 1
            case "--synthetic-redaction":
                syntheticRedactionReason = syntheticRedactionReason ?? .privateRegion
            case "--synthetic-redaction-reason":
                guard index + 1 < arguments.count else {
                    throw WorkflowCLIError("missingArgument", "--synthetic-redaction-reason requires a suppression reason.", path: token)
                }
                guard let reason = RecordingSuppressionReason(rawValue: arguments[index + 1]),
                      reason.redactsSemanticEvidence else {
                    throw WorkflowCLIError(
                        "invalidArgument",
                        "--synthetic-redaction-reason requires a redacting suppression reason.",
                        path: arguments[index + 1]
                    )
                }
                syntheticRedactionReason = reason
                index += 1
            default:
                if token.hasPrefix("--") {
                    throw WorkflowCLIError("unsupportedOption", "Unsupported option '\(token)'.", path: token)
                }
                throw WorkflowCLIError("unexpectedArgument", "Unexpected argument '\(token)'.", path: token)
            }
            index += 1
        }

        let captureTarget = target(
            displayID: displayID,
            windowID: windowID,
            appBundleIdentifier: appBundleIdentifier,
            windowTitle: windowTitle
        )
        let capturePolicy = RecordingCapturePolicy(
            mode: keyframesOnly ? .keyframesOnly : .videoAndKeyframes
        )
        let readinessPolicy = SemanticRecordingBundleReadinessPolicy(
            capturePolicy: capturePolicy,
            requiresOCRObservations: requiresOCRReadiness,
            requiresWindowOrAXObservations: requiresWindowOrAXReadiness
        )

        return Request(
            duration: duration,
            recordingID: recordingID,
            rootDirectory: rootDirectory,
            capturePolicy: capturePolicy,
            preflightOnly: preflightOnly,
            captureTarget: captureTarget,
            evidenceSidecarURL: evidenceSidecarURL,
            syntheticRedactionReason: syntheticRedactionReason,
            readinessPolicy: readinessPolicy,
            commandPlan: commandPlan(arguments)
        )
    }

    static func makePayload(
        request: Request,
        preflightClient: SemanticRecordingPreflightClient = .liveCommandLine
    ) async throws -> SemanticRecordingDebugSmokePayload {
        let preflightPolicy = SemanticRecordingPreflightPolicy(capturePolicy: request.capturePolicy)
        if request.preflightOnly {
            let preflight = await preflightClient.evaluate(policy: preflightPolicy)
            return emptyPayload(
                status: preflight.isReadyToStart ? .preflightReady : .blocked,
                request: request,
                preflight: preflight
            )
        }

        let store = request.rootDirectory.map { RecordingBundleStore(rootDirectory: $0) } ?? RecordingBundleStore()
        let configuration = SemanticRecordingCaptureConfiguration(
            recordingID: request.recordingID,
            createdAt: Date.now,
            capturePolicy: request.capturePolicy,
            captureTarget: request.captureTarget,
            defaultSurfaceID: request.captureTarget.surfaceID ?? "semantic-debug-smoke"
        )
        let session = LiveSemanticRecordingSession(
            configuration: configuration,
            dependencies: LiveSemanticRecordingSessionDependencies(
                store: store,
                preflightClient: preflightClient
            )
        )

        let start = try await session.start(recordingTime: 0)
        guard case .started(let preflight, _) = start else {
            return emptyPayload(
                status: .blocked,
                request: request,
                preflight: start.preflight
            )
        }

        let eventTime = max(0.05, min(request.duration * 0.5, request.duration))
        try await sleep(seconds: eventTime)
        try await session.record(
            event(time: eventTime, captureTarget: request.captureTarget),
            index: 0
        )
        var syntheticSuppressionCount = 0
        if let syntheticRedactionReason = request.syntheticRedactionReason {
            let suppression = SemanticRecordingDebugSmokeSyntheticRedaction(
                reason: syntheticRedactionReason,
                eventTime: eventTime,
                totalDuration: request.duration,
                target: request.captureTarget
            )
            try await session.addSuppression(suppression.suppressionRecord)
            syntheticSuppressionCount = 1
        }
        try await sleep(seconds: max(0, request.duration - eventTime))

        let finish = try await session.finish(recordingTime: request.duration)
        let persistedBundleLoadResult = try await store.loadBundleTolerant(from: finish.bundleDirectory)
        let persistedBundleLoad = SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
            loadResult: persistedBundleLoadResult
        )
        let readiness = SemanticRecordingBundleReadiness.evaluate(
            persistedBundleLoadResult.bundle,
            policy: request.readinessPolicy
        )
        let readinessFollowUps = SemanticRecordingCLIPresentation.readinessFollowUps(readiness)
        let persistedBundleCountCheck = SemanticRecordingDebugSmokePersistedBundleCountCheck.evaluate(
            videoSegmentCount: finish.bundle.videoSegments.count,
            frameCount: finish.bundle.frames.count,
            timelineEventCount: finish.bundle.timelineEvents.count,
            aiSafeEventCount: finish.bundle.aiSafeEvents.count,
            visualObservationCount: finish.bundle.visualObservations.count,
            suppressionCount: finish.bundle.suppressions.count,
            redactedFrameCount: finish.redactionResult?.renderedFrameRelativePaths.count ?? 0,
            redactedVideoCount: finish.redactionResult?.renderedVideoRelativePaths.count ?? 0,
            persistedBundleLoad: persistedBundleLoad
        )
        return SemanticRecordingDebugSmokePayload(
            status: .finished,
            recordingID: request.recordingID,
            commandPlan: nil,
            capturePolicy: request.capturePolicy,
            captureTarget: request.captureTarget,
            preflight: preflight,
            preflightPresentation: SemanticRecordingPreflightPresenter.presentation(for: preflight),
            bundleDirectory: finish.bundleDirectory.path,
            manifestPath: finish.bundleDirectory
                .appendingPathComponent(SemanticRecordingSchema.manifestFileName)
                .path,
            evidenceSidecarPath: nil,
            videoSegmentCount: finish.bundle.videoSegments.count,
            frameCount: finish.bundle.frames.count,
            timelineEventCount: finish.bundle.timelineEvents.count,
            aiSafeEventCount: finish.bundle.aiSafeEvents.count,
            visualObservationCount: finish.bundle.visualObservations.count,
            suppressionCount: finish.bundle.suppressions.count,
            syntheticSuppressionCount: syntheticSuppressionCount,
            syntheticRedactionReason: request.syntheticRedactionReason,
            bundleReadinessPolicy: request.readinessPolicy,
            bundleReadinessStatus: readiness.status,
            bundleReadinessIssueCount: readiness.issues.count,
            bundleReadinessBlockingIssueCount: readiness.blockingIssueCount,
            bundleReadinessDegradedIssueCount: readiness.degradedIssueCount,
            bundleReadinessIssues: readiness.issues,
            bundleReadinessFollowUps: readinessFollowUps,
            redactedFrameCount: finish.redactionResult?.renderedFrameRelativePaths.count ?? 0,
            redactedFrameIndexPath: redactedFrameIndexPath(
                finish.redactionResult,
                bundleDirectory: finish.bundleDirectory
            ),
            redactedVideoCount: finish.redactionResult?.renderedVideoRelativePaths.count ?? 0,
            redactedVideoIndexPath: redactedVideoIndexPath(
                finish.redactionResult,
                bundleDirectory: finish.bundleDirectory
            ),
            pendingVideoRangeRedactionCount: finish.redactionResult?.pendingVideoRangeRedactions.count ?? 0,
            persistedBundleLoad: persistedBundleLoad,
            persistedBundleCountCheck: persistedBundleCountCheck
        )
    }

    private static func emptyPayload(
        status: SemanticRecordingDebugSmokeStatus,
        request: Request,
        preflight: SemanticRecordingPreflightResult
    ) -> SemanticRecordingDebugSmokePayload {
        SemanticRecordingDebugSmokePayload(
            status: status,
            recordingID: request.recordingID,
            commandPlan: nil,
            capturePolicy: request.capturePolicy,
            captureTarget: request.captureTarget,
            preflight: preflight,
            preflightPresentation: SemanticRecordingPreflightPresenter.presentation(for: preflight),
            bundleDirectory: nil,
            manifestPath: nil,
            evidenceSidecarPath: nil,
            videoSegmentCount: 0,
            frameCount: 0,
            timelineEventCount: 0,
            aiSafeEventCount: 0,
            visualObservationCount: 0,
            suppressionCount: 0,
            syntheticSuppressionCount: 0,
            syntheticRedactionReason: request.syntheticRedactionReason,
            bundleReadinessPolicy: request.readinessPolicy,
            bundleReadinessStatus: nil,
            bundleReadinessIssueCount: 0,
            bundleReadinessBlockingIssueCount: 0,
            bundleReadinessDegradedIssueCount: 0,
            bundleReadinessIssues: [],
            bundleReadinessFollowUps: [],
            redactedFrameCount: 0,
            redactedFrameIndexPath: nil,
            redactedVideoCount: 0,
            redactedVideoIndexPath: nil,
            pendingVideoRangeRedactionCount: 0,
            persistedBundleLoad: nil,
            persistedBundleCountCheck: .none
        )
    }

    private static func redactedFrameIndexPath(
        _ result: RecordingBundleRedactionApplicationResult?,
        bundleDirectory: URL
    ) -> String? {
        guard let result,
              let ref = try? RecordingArtifactRef(result.frameIndexRelativePath) else {
            return nil
        }
        return bundleDirectory.appendingRecordingArtifactRef(ref).path
    }

    private static func redactedVideoIndexPath(
        _ result: RecordingBundleRedactionApplicationResult?,
        bundleDirectory: URL
    ) -> String? {
        guard let result,
              let ref = try? RecordingArtifactRef(result.videoIndexRelativePath) else {
            return nil
        }
        return bundleDirectory.appendingRecordingArtifactRef(ref).path
    }

    private static func writeEvidenceSidecar(
        _ payload: SemanticRecordingDebugSmokePayload,
        command: String,
        to url: URL
    ) throws {
        let input = SemanticRecordingDebugSmokeEvidenceInput(
            status: payload.status.rawValue,
            command: command,
            commandPlan: payload.commandPlan,
            generatedAt: Date(),
            recordingID: payload.recordingID,
            capturePolicy: payload.capturePolicy,
            captureTarget: payload.captureTarget,
            preflight: payload.preflight,
            bundleDirectory: payload.bundleDirectory,
            manifestPath: payload.manifestPath,
            evidenceSidecarPath: payload.evidenceSidecarPath,
            videoSegmentCount: payload.videoSegmentCount,
            frameCount: payload.frameCount,
            timelineEventCount: payload.timelineEventCount,
            aiSafeEventCount: payload.aiSafeEventCount,
            visualObservationCount: payload.visualObservationCount,
            suppressionCount: payload.suppressionCount,
            syntheticSuppressionCount: payload.syntheticSuppressionCount,
            syntheticRedactionReason: payload.syntheticRedactionReason,
            bundleReadinessPolicy: payload.bundleReadinessPolicy,
            bundleReadinessStatus: payload.bundleReadinessStatus,
            bundleReadinessIssueCount: payload.bundleReadinessIssueCount,
            bundleReadinessBlockingIssueCount: payload.bundleReadinessBlockingIssueCount,
            bundleReadinessDegradedIssueCount: payload.bundleReadinessDegradedIssueCount,
            bundleReadinessIssues: payload.bundleReadinessIssues,
            bundleReadinessFollowUps: payload.bundleReadinessFollowUps,
            redactedFrameCount: payload.redactedFrameCount,
            redactedFrameIndexPath: payload.redactedFrameIndexPath,
            redactedVideoCount: payload.redactedVideoCount,
            redactedVideoIndexPath: payload.redactedVideoIndexPath,
            pendingVideoRangeRedactionCount: payload.pendingVideoRangeRedactionCount,
            persistedBundleLoad: payload.persistedBundleLoad
        )
        let parent = url.deletingLastPathComponent()
        if !parent.path.isEmpty {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        try SemanticRecordingDebugSmokeEvidenceSidecar
            .markdown(for: input)
            .write(to: url, atomically: true, encoding: .utf8)
    }

    static func commandLine(_ arguments: [String]) -> String {
        (["semantic-recording", "debug-smoke"] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    static func commandPlan(_ arguments: [String]) -> SemanticRecordingDebugSmokeCommandPlan {
        SemanticRecordingDebugSmokeCommandPlan(
            invocationCommand: commandLine(arguments),
            preflightCommand: commandLine(withPreflightOnly(arguments, enabled: true)),
            liveCaptureCommand: commandLine(withPreflightOnly(arguments, enabled: false))
        )
    }

    private static func withPreflightOnly(
        _ arguments: [String],
        enabled: Bool
    ) -> [String] {
        var updated = arguments.filter { $0 != "--preflight-only" }
        if enabled {
            updated.append("--preflight-only")
        }
        return updated
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !value.contains("'") else {
            return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return value
    }

    private static func target(
        displayID: UInt32?,
        windowID: UInt32?,
        appBundleIdentifier: String?,
        windowTitle: String?
    ) -> RecordingCaptureTarget {
        let isWindowTarget = windowID != nil ||
            appBundleIdentifier?.isEmpty == false ||
            windowTitle?.isEmpty == false
        return RecordingCaptureTarget(
            kind: isWindowTarget ? .window : .display,
            surfaceID: isWindowTarget ? "semantic-debug-window" : "semantic-debug-display",
            displayID: displayID,
            windowID: windowID,
            appBundleIdentifier: appBundleIdentifier,
            windowTitle: windowTitle
        )
    }

    private static func event(
        time: TimeInterval,
        captureTarget: RecordingCaptureTarget
    ) -> RecordedEvent {
        RecordedEvent(
            kind: .leftMouseUp,
            time: time,
            x: 1,
            y: 1,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 1,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            surfaceId: captureTarget.surfaceID ?? "semantic-debug-smoke"
        )
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        guard nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func messages(
        from issues: [SemanticRecordingPreflightIssue]
    ) -> [AutomationCLIMessage] {
        issues.map { issue in
            AutomationCLIMessage(
                code: issue.severity.rawValue,
                message: issue.message,
                path: issue.permission.rawValue
            )
        }
    }

    private static func nextActions(
        _ payload: SemanticRecordingDebugSmokePayload
    ) -> [AutomationCLINextAction] {
        switch payload.status {
        case .finished:
            var actions = [
                AutomationCLINextAction(
                    command: "Open the manifest path printed by this command and inspect video/segments.json plus frames/index.jsonl.",
                    reason: "This smoke path proves live S2 capture wrote a semantic recording bundle, but it is not product evidence by itself."
                )
            ]
            actions += payload.bundleReadinessFollowUps.map { followUp in
                AutomationCLINextAction(
                    command: followUp,
                    reason: "Bundle readiness reported a missing or degraded S2 evidence requirement."
                )
            }
            if payload.persistedBundleLoad?.degraded == true {
                actions.append(
                    AutomationCLINextAction(
                        command: "Inspect the persisted bundle failed sidecars in the debug-smoke JSON or evidence sidecar, then rerun semantic-recording debug-smoke after repairing the capture path.",
                        reason: "The bundle was written, but at least one persisted sidecar could not be decoded during the post-write reload audit."
                    )
                )
            }
            if payload.persistedBundleCountCheck.status == .mismatched {
                actions.append(
                    AutomationCLINextAction(
                        command: "Compare persistedBundleCountCheck.mismatches with manifest and sidecar writers before using this bundle as live S2 product evidence.",
                        reason: "The in-memory finish result and the just-reloaded bundle disagree on persisted evidence counts: \(payload.persistedBundleCountCheck.summary)."
                    )
                )
            }
            return actions
        case .preflightReady:
            return [
                AutomationCLINextAction(
                    command: payload.commandPlan?.liveCaptureCommand ??
                        "semantic-recording debug-smoke --json",
                    reason: "Preflight-only mode proves S2 capture readiness without creating a bundle or touching ScreenCaptureKit."
                )
            ]
        case .blocked:
            return [
                AutomationCLINextAction(
                    command: "Grant Input Monitoring and Screen Recording permissions, then rerun semantic-recording debug-smoke --json.",
                    reason: "S2 capture is blocked before bundle creation when required permissions are missing."
                ),
                AutomationCLINextAction(
                    command: payload.commandPlan?.preflightCommand ??
                        "semantic-recording debug-smoke --preflight-only --json",
                    reason: "Use the same target/root/readiness options to verify preflight again before attempting live capture."
                )
            ]
        }
    }

    private static func writeSummary(
        _ payload: SemanticRecordingDebugSmokePayload
    ) {
        switch payload.status {
        case .finished:
            FileHandle.standardOutput.write(Data("""
            SparkleRecorder: semantic recording debug smoke finished.
            - bundle: \(payload.bundleDirectory ?? "(missing)")
            - manifest: \(payload.manifestPath ?? "(missing)")
            - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
            - video segments: \(payload.videoSegmentCount)
            - frames: \(payload.frameCount)
            - timeline events: \(payload.timelineEventCount)
            - AI-safe events: \(payload.aiSafeEventCount)
            - suppressions: \(payload.suppressionCount)
            - synthetic suppressions: \(payload.syntheticSuppressionCount)
            - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
            - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
            - preflight primary action: \(preflightActionSummary(payload.preflightPresentation.primaryAction))
            - bundle readiness policy: \(readinessPolicySummary(payload.bundleReadinessPolicy))
            - bundle readiness: \(payload.bundleReadinessStatus?.rawValue ?? "none")
            - bundle readiness issues: \(payload.bundleReadinessIssueCount) (blocking: \(payload.bundleReadinessBlockingIssueCount), degraded: \(payload.bundleReadinessDegradedIssueCount))
            - bundle readiness issue codes: \(readinessIssueCodes(payload.bundleReadinessIssues))
            - bundle readiness follow-up: \(readinessFollowUpSummary(payload.bundleReadinessFollowUps))
            - persisted bundle reload: \(persistedBundleReloadSummary(payload.persistedBundleLoad))
            - persisted bundle counts: \(persistedBundleCountSummary(payload.persistedBundleLoad))
            - persisted bundle count match: \(payload.persistedBundleCountCheck.summary)
            - persisted bundle loaded sidecars: \(SemanticRecordingCLIPresentation.sidecarKindSummary(payload.persistedBundleLoad?.sidecarDiagnostics.loadedKinds ?? []))
            - persisted bundle missing sidecars: \(SemanticRecordingCLIPresentation.sidecarKindSummary(payload.persistedBundleLoad?.sidecarDiagnostics.missingKinds ?? []))
            - persisted bundle failed sidecars: \(SemanticRecordingCLIPresentation.failedSidecarSummary(payload.persistedBundleLoad?.sidecarDiagnostics.failedIssues ?? []))
            - redacted frames: \(payload.redactedFrameCount)
            - redacted videos: \(payload.redactedVideoCount)
            - pending video redactions: \(payload.pendingVideoRangeRedactionCount)

            """.utf8))
        case .preflightReady:
            let degraded = payload.preflight.degradedIssues
                .map { "- \($0.permission.rawValue): \($0.message)" }
                .joined(separator: "\n")
            let degradedText = degraded.isEmpty ? "- none" : degraded
            FileHandle.standardOutput.write(Data("""
            SparkleRecorder: semantic recording debug smoke preflight ready.
            - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
            - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
            - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
            - preflight primary action: \(preflightActionSummary(payload.preflightPresentation.primaryAction))
            - degraded issues:
            \(degradedText)

            """.utf8))
        case .blocked:
            let issues = payload.preflight.blockingIssues
                .map { "- \($0.permission.rawValue): \($0.message)" }
                .joined(separator: "\n")
            FileHandle.standardOutput.write(Data("""
            SparkleRecorder: semantic recording debug smoke blocked by preflight.
            - evidence sidecar: \(payload.evidenceSidecarPath ?? "(not written)")
            - synthetic redaction reason: \(payload.syntheticRedactionReason?.rawValue ?? "none")
            - preflight guidance: \(payload.preflightPresentation.status.rawValue) - \(payload.preflightPresentation.title)
            - preflight primary action: \(preflightActionSummary(payload.preflightPresentation.primaryAction))
            \(issues)

            """.utf8))
        }
    }

    private static func readinessIssueCodes(
        _ issues: [SemanticRecordingBundleReadinessIssue]
    ) -> String {
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .map { "\($0.code.rawValue):\($0.severity.rawValue)" }
            .joined(separator: ", ")
    }

    private static func preflightActionSummary(
        _ action: SemanticRecordingPreflightPresentationAction
    ) -> String {
        [
            "kind=\(action.kind.rawValue)",
            "label=\(action.label)",
            "permission=\(action.permission?.rawValue ?? "none")"
        ].joined(separator: " ")
    }

    private static func readinessFollowUpSummary(_ followUps: [String]) -> String {
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

    private static func readinessPolicySummary(
        _ policy: SemanticRecordingBundleReadinessPolicy
    ) -> String {
        [
            "video=\(policy.requiresVideoSegments)",
            "keyframes=\(policy.requiresEventAlignedKeyframes)",
            "timeline=\(policy.requiresTimelineEvents)",
            "aiSafe=\(policy.requiresAISafeEvents)",
            "ocr=\(policy.requiresOCRObservations)",
            "windowOrAX=\(policy.requiresWindowOrAXObservations)",
            "redactions=\(policy.requiresRedactionSidecars)"
        ].joined(separator: ", ")
    }

    private static func positiveDouble(
        _ arguments: [String],
        index: Int,
        option: String
    ) throws -> Double {
        guard index + 1 < arguments.count else {
            throw WorkflowCLIError("missingArgument", "\(option) requires a positive numeric value.", path: option)
        }
        guard let value = Double(arguments[index + 1]), value > 0 else {
            throw WorkflowCLIError("invalidArgument", "\(option) requires a positive numeric value.", path: option)
        }
        return value
    }

    private static func uuid(_ value: String, path: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw WorkflowCLIError("invalidUUID", "Expected a UUID for \(path), got '\(value)'.", path: path)
        }
        return id
    }
}

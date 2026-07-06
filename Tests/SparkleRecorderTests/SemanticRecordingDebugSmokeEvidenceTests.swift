import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Debug Smoke Evidence Tests")
struct SemanticRecordingDebugSmokeEvidenceTests {
    @Test("Finished sidecar captures bundle counts and redaction paths")
    func finishedSidecarCapturesBundleCountsAndRedactionPaths() throws {
        let recordingID = try #require(UUID(uuidString: "8A000000-0000-0000-0000-000000000001"))
        let preflight = SemanticRecordingPreflightEvaluator.evaluate(
            policy: SemanticRecordingPreflightPolicy(),
            snapshot: SemanticRecordingPermissionSnapshot(
                inputMonitoring: .authorized,
                accessibility: .authorized,
                screenRecording: .authorized
            )
        )
        let input = SemanticRecordingDebugSmokeEvidenceInput(
            status: "finished",
            command: "semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md",
            commandPlan: SemanticRecordingDebugSmokeCommandPlan(
                invocationCommand: "semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md",
                preflightCommand: "semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md --preflight-only",
                liveCaptureCommand: "semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md"
            ),
            generatedAt: Date(timeIntervalSince1970: 1_800_001_000),
            recordingID: recordingID,
            capturePolicy: RecordingCapturePolicy(),
            captureTarget: RecordingCaptureTarget(
                kind: .window,
                surfaceID: "surface-1",
                displayID: 1,
                windowID: 42,
                appBundleIdentifier: "com.example.App",
                windowTitle: "Example"
            ),
            preflight: preflight,
            bundleDirectory: "/tmp/SemanticRecordings/\(recordingID.uuidString)",
            manifestPath: "/tmp/SemanticRecordings/\(recordingID.uuidString)/manifest.json",
            evidenceSidecarPath: "/tmp/s2.md",
            videoSegmentCount: 1,
            frameCount: 3,
            timelineEventCount: 1,
            aiSafeEventCount: 1,
            visualObservationCount: 2,
            suppressionCount: 1,
            syntheticSuppressionCount: 1,
            syntheticRedactionReason: .privateRegion,
            bundleReadinessPolicy: SemanticRecordingBundleReadinessPolicy(
                requiresOCRObservations: true,
                requiresWindowOrAXObservations: true
            ),
            bundleReadinessStatus: .ready,
            bundleReadinessIssueCount: 0,
            bundleReadinessBlockingIssueCount: 0,
            bundleReadinessDegradedIssueCount: 0,
            bundleReadinessIssues: [],
            redactedFrameCount: 1,
            redactedFrameIndexPath: "/tmp/SemanticRecordings/redacted/frames/index.json",
            redactedVideoCount: 1,
            redactedVideoIndexPath: "/tmp/SemanticRecordings/redacted/video/index.json",
            pendingVideoRangeRedactionCount: 0,
            persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
                reloaded: true,
                degraded: false,
                videoSegmentCount: 1,
                frameCount: 3,
                timelineEventCount: 1,
                aiSafeEventCount: 1,
                visualObservationCount: 2,
                suppressionCount: 1,
                redactedFrameCount: 1,
                redactedVideoCount: 1,
                sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics(
                    loadedKinds: [
                        .videoSegments,
                        .frames,
                        .timelineEvents,
                        .semanticEvents,
                        .visualObservations,
                        .suppressions,
                        .redactedFrames,
                        .redactedVideos
                    ]
                )
            )
        )

        let markdown = SemanticRecordingDebugSmokeEvidenceSidecar.markdown(for: input)

        #expect(input.persistedBundleCountCheck == .matched)
        #expect(markdown.contains("Checklist item: S2 live semantic recording bundle smoke"))
        #expect(markdown.contains("Status: finished"))
        #expect(markdown.contains("Readiness: bundle written"))
        #expect(markdown.contains("## Command Plan"))
        #expect(markdown.contains("- invocation: semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md"))
        #expect(markdown.contains("- preflight: semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md --preflight-only"))
        #expect(markdown.contains("- live capture: semantic-recording debug-smoke --json --evidence-sidecar /tmp/s2.md"))
        #expect(markdown.contains("- window id: 42"))
        #expect(markdown.contains("- app bundle id: com.example.App"))
        #expect(markdown.contains("- policy mode: videoAndKeyframes"))
        #expect(markdown.contains("## Preflight Guidance"))
        #expect(markdown.contains("- status: ready"))
        #expect(markdown.contains("- can start: true"))
        #expect(markdown.contains("- title: Semantic recording is ready"))
        #expect(markdown.contains("- primary action: kind=startRecording label=Start semantic recording permission=none"))
        #expect(markdown.contains("- issue guidance: none"))
        #expect(markdown.contains("- video segments: 1"))
        #expect(markdown.contains("- frames: 3"))
        #expect(markdown.contains("- visual observations: 2"))
        #expect(markdown.contains("- suppressions: 1"))
        #expect(markdown.contains("- synthetic suppressions: 1"))
        #expect(markdown.contains("- synthetic redaction reason: privateRegion"))
        #expect(markdown.contains("- bundle readiness policy: video=true, keyframes=true, timeline=true, aiSafe=true, ocr=true, windowOrAX=true, redactions=true"))
        #expect(markdown.contains("- bundle readiness: ready"))
        #expect(markdown.contains("- bundle readiness issues: 0"))
        #expect(markdown.contains("- bundle readiness blocking issues: 0"))
        #expect(markdown.contains("- bundle readiness degraded issues: 0"))
        #expect(markdown.contains("- bundle readiness issue details: none"))
        #expect(markdown.contains("- bundle readiness follow-up: none"))
        #expect(markdown.contains("- persisted bundle reload: loaded"))
        #expect(markdown.contains("- persisted bundle counts: video=1, frames=3, timeline=1, aiSafe=1, observations=2, suppressions=1, redactedFrames=1, redactedVideos=1"))
        #expect(markdown.contains("- persisted bundle count match: matched"))
        #expect(markdown.contains("- persisted bundle loaded sidecars: videoSegments, frames, timelineEvents, semanticEvents, visualObservations, suppressions, redactedFrames, redactedVideos"))
        #expect(markdown.contains("- persisted bundle failed sidecars: none"))
        #expect(markdown.contains("- redacted frames: 1"))
        #expect(markdown.contains("- redacted videos: 1"))
        #expect(markdown.contains("/tmp/s2.md"))
        #expect(markdown.contains("This sidecar is generated evidence metadata."))
    }

    @Test("Blocked sidecar records preflight issues without bundle paths")
    func blockedSidecarRecordsPreflightIssuesWithoutBundlePaths() throws {
        let recordingID = try #require(UUID(uuidString: "8B000000-0000-0000-0000-000000000001"))
        let preflight = SemanticRecordingPreflightEvaluator.evaluate(
            policy: SemanticRecordingPreflightPolicy(),
            snapshot: SemanticRecordingPermissionSnapshot(
                inputMonitoring: .denied,
                accessibility: .notDetermined,
                screenRecording: .denied
            )
        )
        let input = SemanticRecordingDebugSmokeEvidenceInput(
            status: "blocked",
            command: "semantic-recording debug-smoke --preflight-only --json",
            commandPlan: SemanticRecordingDebugSmokeCommandPlan(
                invocationCommand: "semantic-recording debug-smoke --preflight-only --json",
                preflightCommand: "semantic-recording debug-smoke --json --preflight-only",
                liveCaptureCommand: "semantic-recording debug-smoke --json"
            ),
            generatedAt: Date(timeIntervalSince1970: 1_800_001_100),
            recordingID: recordingID,
            capturePolicy: RecordingCapturePolicy(),
            captureTarget: RecordingCaptureTarget(kind: .display, surfaceID: "display"),
            preflight: preflight
        )

        let markdown = SemanticRecordingDebugSmokeEvidenceSidecar.markdown(for: input)

        #expect(input.persistedBundleCountCheck == .none)
        #expect(markdown.contains("Checklist item: S2 semantic recording blocked preflight"))
        #expect(markdown.contains("Status: blocked"))
        #expect(markdown.contains("Readiness: blocked"))
        #expect(markdown.contains("- invocation: semantic-recording debug-smoke --preflight-only --json"))
        #expect(markdown.contains("- preflight: semantic-recording debug-smoke --json --preflight-only"))
        #expect(markdown.contains("- live capture: semantic-recording debug-smoke --json"))
        #expect(markdown.contains("- bundle directory: none"))
        #expect(markdown.contains("- manifest path: none"))
        #expect(markdown.contains("- bundle readiness: none"))
        #expect(markdown.contains("- persisted bundle reload: none"))
        #expect(markdown.contains("- persisted bundle counts: none"))
        #expect(markdown.contains("- persisted bundle count match: none"))
        #expect(markdown.contains("- persisted bundle loaded sidecars: none"))
        #expect(markdown.contains("- persisted bundle failed sidecars: none"))
        #expect(markdown.contains("## Preflight Guidance"))
        #expect(markdown.contains("- status: blocked"))
        #expect(markdown.contains("- can start: false"))
        #expect(markdown.contains("- title: Semantic recording is blocked"))
        #expect(markdown.contains("- primary action: kind=openPermissionSettings label=Open Input Monitoring settings permission=inputMonitoring"))
        #expect(markdown.contains("- secondary action: kind=retryPreflight label=Check again permission=none"))
        #expect(markdown.contains("inputMonitoring=blocking title=Input Monitoring required action=openPermissionSettings capabilities=Playable macro events"))
        #expect(markdown.contains("screenRecording=blocking title=Screen Recording required action=openPermissionSettings capabilities=Video recording"))
        #expect(markdown.contains("screenRecording=blocking title=Screen Recording required action=openPermissionSettings capabilities=Event-aligned keyframes, OCR indexing"))
        #expect(markdown.contains("inputMonitoring=denied blocking"))
        #expect(markdown.contains("screenRecording=denied blocking"))
        #expect(markdown.contains("accessibility=notDetermined degraded"))
        #expect(markdown.contains("fix the listed preflight issues"))
    }

    @Test("Command plan round trips exact preflight and live capture commands")
    func commandPlanRoundTripsCommands() throws {
        let plan = SemanticRecordingDebugSmokeCommandPlan(
            invocationCommand: "semantic-recording debug-smoke --preflight-only --json --root-directory /tmp/root",
            preflightCommand: "semantic-recording debug-smoke --json --root-directory /tmp/root --preflight-only",
            liveCaptureCommand: "semantic-recording debug-smoke --json --root-directory /tmp/root"
        )

        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingDebugSmokeCommandPlan.self,
            from: encoded
        )

        #expect(decoded == plan)
    }

    @Test("Persisted bundle load evidence summarizes tolerant loader result")
    func persistedBundleLoadEvidenceSummarizesTolerantLoaderResult() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let redactedFrame = SemanticRecordingRenderedFrameRedaction(
            frameID: SemanticRecordingFixture.afterClickFrameID,
            sourceImageRef: try RecordingArtifactRef("frames/000016-after-click.png"),
            redactedImageRef: try RecordingArtifactRef("redacted/frames/after-click.png"),
            renderedMaskCount: 1,
            sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID]
        )
        let redactedVideo = SemanticRecordingRenderedVideoRedaction(
            videoSegmentID: SemanticRecordingFixture.videoSegmentID,
            sourceVideoRef: try RecordingArtifactRef("video/recording.mov"),
            redactedVideoRef: try RecordingArtifactRef("redacted/video/recording.mov"),
            renderedRangeCount: 1,
            sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID],
            reasons: [.passwordField]
        )
        let diagnostics = SemanticRecordingBundleSidecarLoadDiagnostics(
            loadedKinds: [.videoSegments, .frames, .semanticEvents],
            missingKinds: [.visualObservations],
            failedIssues: [
                SemanticRecordingBundleSidecarLoadIssue(
                    kind: .timelineEvents,
                    relativePath: "timeline.jsonl",
                    message: "Could not decode sidecar."
                )
            ]
        )
        let loadResult = SemanticRecordingBundleLoadResult(
            manifest: SemanticRecordingBundle(
                id: bundle.id,
                schemaVersion: bundle.schemaVersion,
                createdAt: bundle.createdAt,
                capturePolicy: bundle.capturePolicy,
                captureTarget: bundle.captureTarget
            ),
            sidecars: SemanticRecordingBundleSidecars(
                videoSegments: bundle.videoSegments,
                frames: bundle.frames,
                timelineEvents: bundle.timelineEvents,
                semanticEvents: bundle.semanticEvents,
                visualObservations: bundle.visualObservations,
                suppressions: bundle.suppressions,
                redactedFrames: [redactedFrame],
                redactedVideos: [redactedVideo]
            ),
            sidecarDiagnostics: diagnostics
        )

        let evidence = SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
            loadResult: loadResult
        )

        #expect(evidence.reloaded)
        #expect(evidence.degraded)
        #expect(evidence.videoSegmentCount == 1)
        #expect(evidence.frameCount == 3)
        #expect(evidence.timelineEventCount == 3)
        #expect(evidence.aiSafeEventCount == 3)
        #expect(evidence.visualObservationCount == 2)
        #expect(evidence.suppressionCount == 1)
        #expect(evidence.redactedFrameCount == 1)
        #expect(evidence.redactedVideoCount == 1)
        #expect(evidence.sidecarDiagnostics == diagnostics)

        let encoded = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingDebugSmokePersistedBundleLoadEvidence.self,
            from: encoded
        )
        #expect(decoded == evidence)
    }

    @Test("Finished sidecar highlights memory persisted count mismatches")
    func finishedSidecarHighlightsCountMismatches() throws {
        let recordingID = try #require(UUID(uuidString: "8A000000-0000-0000-0000-000000000201"))
        let preflight = SemanticRecordingPreflightEvaluator.evaluate(
            policy: SemanticRecordingPreflightPolicy(),
            snapshot: SemanticRecordingPermissionSnapshot(
                inputMonitoring: .authorized,
                accessibility: .authorized,
                screenRecording: .authorized
            )
        )
        let input = SemanticRecordingDebugSmokeEvidenceInput(
            status: "finished",
            command: "semantic-recording debug-smoke --json",
            recordingID: recordingID,
            capturePolicy: RecordingCapturePolicy(),
            captureTarget: RecordingCaptureTarget(kind: .display, surfaceID: "display"),
            preflight: preflight,
            videoSegmentCount: 1,
            frameCount: 3,
            timelineEventCount: 2,
            aiSafeEventCount: 2,
            visualObservationCount: 1,
            suppressionCount: 1,
            redactedFrameCount: 1,
            redactedVideoCount: 1,
            persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
                reloaded: true,
                degraded: true,
                videoSegmentCount: 1,
                frameCount: 2,
                timelineEventCount: 2,
                aiSafeEventCount: 1,
                visualObservationCount: 0,
                suppressionCount: 1,
                redactedFrameCount: 0,
                redactedVideoCount: 1
            )
        )

        let markdown = SemanticRecordingDebugSmokeEvidenceSidecar.markdown(for: input)

        let check = input.persistedBundleCountCheck
        #expect(check.status == .mismatched)
        #expect(check.mismatches.map(\.field) == [
            .frames,
            .aiSafe,
            .observations,
            .redactedFrames
        ])
        #expect(check.summary == "frames=memory:3 persisted:2, aiSafe=memory:2 persisted:1, observations=memory:1 persisted:0, redactedFrames=memory:1 persisted:0")
        let encoded = try JSONEncoder().encode(check)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingDebugSmokePersistedBundleCountCheck.self,
            from: encoded
        )
        #expect(decoded == check)
        #expect(markdown.contains("- persisted bundle count match: frames=memory:3 persisted:2, aiSafe=memory:2 persisted:1, observations=memory:1 persisted:0, redactedFrames=memory:1 persisted:0"))
    }

    @Test("Finished sidecar lists readiness issue details")
    func finishedSidecarListsReadinessIssueDetails() throws {
        let recordingID = try #require(UUID(uuidString: "8A000000-0000-0000-0000-000000000101"))
        let frameID = try #require(UUID(uuidString: "8A000000-0000-0000-0000-000000000102"))
        let suppressionID = try #require(UUID(uuidString: "8A000000-0000-0000-0000-000000000103"))
        let preflight = SemanticRecordingPreflightEvaluator.evaluate(
            policy: SemanticRecordingPreflightPolicy(),
            snapshot: SemanticRecordingPermissionSnapshot(
                inputMonitoring: .authorized,
                accessibility: .authorized,
                screenRecording: .authorized
            )
        )
        let issue = SemanticRecordingBundleReadinessIssue(
            code: .redactingSuppressionMissingFrameRedaction,
            severity: .blocking,
            message: "Redacting suppression matches a frame but no rendered redacted frame sidecar records it.",
            frameID: frameID,
            suppressionID: suppressionID
        )
        let input = SemanticRecordingDebugSmokeEvidenceInput(
            status: "finished",
            command: "semantic-recording debug-smoke --json",
            recordingID: recordingID,
            capturePolicy: RecordingCapturePolicy(),
            captureTarget: RecordingCaptureTarget(kind: .window, surfaceID: "surface-1"),
            preflight: preflight,
            videoSegmentCount: 1,
            frameCount: 1,
            timelineEventCount: 1,
            aiSafeEventCount: 1,
            visualObservationCount: 0,
            suppressionCount: 1,
            bundleReadinessStatus: .notReady,
            bundleReadinessIssueCount: 1,
            bundleReadinessBlockingIssueCount: 1,
            bundleReadinessIssues: [issue],
            bundleReadinessFollowUps: [
                "Inspect redacted/frames/index.json and redacted/video/index.json."
            ],
            persistedBundleLoad: SemanticRecordingDebugSmokePersistedBundleLoadEvidence(
                reloaded: true,
                degraded: true,
                frameCount: 1,
                sidecarDiagnostics: SemanticRecordingBundleSidecarLoadDiagnostics(
                    failedIssues: [
                        SemanticRecordingBundleSidecarLoadIssue(
                            kind: .frames,
                            relativePath: "frames/index.jsonl",
                            message: "Could not decode sidecar."
                        )
                    ]
                )
            )
        )

        let markdown = SemanticRecordingDebugSmokeEvidenceSidecar.markdown(for: input)

        #expect(markdown.contains("- bundle readiness: notReady"))
        #expect(markdown.contains("- bundle readiness issues: 1"))
        #expect(markdown.contains("redactingSuppressionMissingFrameRedaction=blocking"))
        #expect(markdown.contains("frame=\(frameID.uuidString)"))
        #expect(markdown.contains("suppression=\(suppressionID.uuidString)"))
        #expect(markdown.contains("- bundle readiness follow-up: Inspect redacted/frames/index.json and redacted/video/index.json."))
        #expect(markdown.contains("- persisted bundle reload: degraded"))
        #expect(markdown.contains("- persisted bundle failed sidecars: frames=failed path=frames/index.jsonl fallback=true Could not decode sidecar."))
    }

    @Test("Synthetic redaction builds a deterministic debug suppression")
    func syntheticRedactionBuildsDeterministicDebugSuppression() throws {
        let suppressionID = try #require(UUID(uuidString: "8C000000-0000-0000-0000-000000000001"))
        let createdAt = Date(timeIntervalSince1970: 1_800_001_200)
        let target = RecordingCaptureTarget(
            kind: .window,
            surfaceID: "surface-1",
            displayID: 1,
            windowID: 42,
            appBundleIdentifier: "com.example.App",
            windowTitle: "Example"
        )

        let syntheticRedaction = SemanticRecordingDebugSmokeSyntheticRedaction(
            suppressionID: suppressionID,
            reason: .passwordField,
            eventTime: 0.5,
            totalDuration: 2.0,
            target: target,
            createdAt: createdAt
        )

        let record = syntheticRedaction.suppressionRecord

        #expect(record.id == suppressionID)
        #expect(record.reason == .passwordField)
        #expect(record.recordingTime == 0.5)
        #expect(record.timeRange == RecordingTimeRange(startTime: 0.5, duration: 0.5))
        #expect(record.target == target)
        #expect(record.createdAt == createdAt)
        #expect(record.detail?.contains("Synthetic debug-smoke redaction trigger") == true)
    }
}

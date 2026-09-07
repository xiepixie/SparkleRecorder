import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Semantic Recording Debug Smoke CLI Tests")
struct SemanticRecordingDebugSmokeCLITests {
    @Test("Debug smoke parsing keeps target capture and readiness policy behind one interface")
    func parsesTargetCaptureAndReadinessPolicy() throws {
        let recordingID = UUID()
        let request = try SemanticRecordingDebugSmokeCLI.parse([
            "--duration", "2.5",
            "--recording-id", recordingID.uuidString,
            "--keyframes-only",
            "--window-id", "42",
            "--app-bundle-id", "com.example.Editor",
            "--window-title", "Document",
            "--require-ocr",
            "--require-window-or-ax",
            "--synthetic-redaction-reason", RecordingSuppressionReason.privateRegion.rawValue
        ])

        #expect(request.duration == 2.5)
        #expect(request.recordingID == recordingID)
        #expect(request.capturePolicy.mode == .keyframesOnly)
        #expect(!request.capturePolicy.recordsVideo)
        #expect(request.captureTarget.kind == .window)
        #expect(request.captureTarget.surfaceID == "semantic-debug-window")
        #expect(request.captureTarget.windowID == 42)
        #expect(request.captureTarget.appBundleIdentifier == "com.example.Editor")
        #expect(request.captureTarget.windowTitle == "Document")
        #expect(request.readinessPolicy.requiresOCRObservations)
        #expect(request.readinessPolicy.requiresWindowOrAXObservations)
        #expect(request.syntheticRedactionReason == .privateRegion)
    }

    @Test("Command plan preserves shell-safe arguments while toggling only preflight mode")
    func commandPlanPreservesArguments() throws {
        let request = try SemanticRecordingDebugSmokeCLI.parse([
            "--json",
            "--root-directory", "/tmp/root with space",
            "--preflight-only"
        ])

        #expect(
            request.commandPlan.invocationCommand ==
                "semantic-recording debug-smoke --json --root-directory '/tmp/root with space' --preflight-only"
        )
        #expect(
            request.commandPlan.preflightCommand ==
                "semantic-recording debug-smoke --json --root-directory '/tmp/root with space' --preflight-only"
        )
        #expect(
            request.commandPlan.liveCaptureCommand ==
                "semantic-recording debug-smoke --json --root-directory '/tmp/root with space'"
        )
    }

    @Test("Invalid debug smoke options fail before capture begins")
    func invalidOptionsFailBeforeCapture() {
        do {
            _ = try SemanticRecordingDebugSmokeCLI.parse([
                "--synthetic-redaction-reason", RecordingSuppressionReason.oversizedArtifact.rawValue
            ])
            Issue.record("Expected a non-redacting suppression reason to fail")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "invalidArgument")
            #expect(error.path == RecordingSuppressionReason.oversizedArtifact.rawValue)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Preflight-only execution returns evidence without creating a bundle")
    func preflightOnlyDoesNotCreateBundle() async throws {
        let recordingID = UUID()
        let request = try SemanticRecordingDebugSmokeCLI.parse([
            "--recording-id", recordingID.uuidString,
            "--preflight-only"
        ])
        let client = SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .authorized,
            screenRecording: .authorized
        ))

        let payload = try await SemanticRecordingDebugSmokeCLI.makePayload(
            request: request,
            preflightClient: client
        )

        #expect(payload.status == .preflightReady)
        #expect(payload.recordingID == recordingID)
        #expect(payload.bundleDirectory == nil)
        #expect(payload.manifestPath == nil)
        #expect(payload.videoSegmentCount == 0)
        #expect(payload.frameCount == 0)
        #expect(payload.timelineEventCount == 0)
        #expect(payload.persistedBundleLoad == nil)
        #expect(payload.persistedBundleCountCheck == .none)
    }
}

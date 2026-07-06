import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Preflight Tests")
struct SemanticRecordingPreflightTests {
    @Test("Authorized permissions enable default semantic recording capabilities")
    func authorizedPermissionsEnableDefaultSemanticRecordingCapabilities() async throws {
        let result = await SemanticRecordingPreflightClient.fixed(.allAuthorized).evaluate()

        #expect(result.isReadyToStart)
        #expect(!result.isDegraded)
        #expect(result.blockingIssues.isEmpty)
        #expect(result.degradedIssues.isEmpty)
        #expect(result.hasCapability(.playableEvents))
        #expect(result.hasCapability(.movieRecording))
        #expect(result.hasCapability(.keyframeCapture))
        #expect(result.hasCapability(.visionOCR))
        #expect(result.hasCapability(.accessibilitySnapshots))
        #expect(result.hasCapability(.windowMetadata))

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SemanticRecordingPreflightResult.self, from: encoded)
        #expect(decoded == result)
    }

    @Test("Missing screen recording blocks movie keyframes and OCR")
    func missingScreenRecordingBlocksMovieKeyframesAndOCR() async {
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .authorized,
            screenRecording: .denied
        )).evaluate()

        #expect(!result.isReadyToStart)
        #expect(!result.hasCapability(.movieRecording))
        #expect(!result.hasCapability(.keyframeCapture))
        #expect(!result.hasCapability(.visionOCR))
        #expect(result.hasCapability(.playableEvents))
        #expect(result.blockingIssues.count == 2)
        #expect(result.blockingIssues.map(\.permission) == [.screenRecording, .screenRecording])
        #expect(result.blockingIssues.flatMap(\.affectedCapabilities).contains(.movieRecording))
        #expect(result.blockingIssues.flatMap(\.affectedCapabilities).contains(.keyframeCapture))
        #expect(result.blockingIssues.flatMap(\.affectedCapabilities).contains(.visionOCR))
    }

    @Test("Missing accessibility degrades AX and window metadata without blocking capture")
    func missingAccessibilityDegradesAXAndWindowMetadataWithoutBlockingCapture() async {
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .denied,
            screenRecording: .authorized
        )).evaluate()

        #expect(result.isReadyToStart)
        #expect(result.isDegraded)
        #expect(result.blockingIssues.isEmpty)
        #expect(result.degradedIssues.count == 1)
        #expect(result.degradedIssues.first?.permission == .accessibility)
        #expect(result.degradedIssues.first?.affectedCapabilities == [.accessibilitySnapshots, .windowMetadata])
        #expect(result.hasCapability(.movieRecording))
        #expect(result.hasCapability(.keyframeCapture))
        #expect(result.hasCapability(.visionOCR))
        #expect(!result.hasCapability(.accessibilitySnapshots))
        #expect(!result.hasCapability(.windowMetadata))
    }

    @Test("Keyframe-only policy skips movie requirement but still requires screen recording")
    func keyframeOnlyPolicySkipsMovieRequirementButStillRequiresScreenRecording() async {
        let policy = SemanticRecordingPreflightPolicy(
            capturePolicy: RecordingCapturePolicy(mode: .keyframesOnly)
        )
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .authorized,
            screenRecording: .denied
        )).evaluate(policy: policy)

        #expect(!result.isReadyToStart)
        #expect(!result.hasCapability(.movieRecording))
        #expect(result.blockingIssues.count == 1)
        #expect(result.blockingIssues.first?.affectedCapabilities == [.keyframeCapture, .visionOCR])
    }

    @Test("Input monitoring is the playable event blocker")
    func inputMonitoringIsThePlayableEventBlocker() async {
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .denied,
            accessibility: .authorized,
            screenRecording: .authorized
        )).evaluate()

        #expect(!result.isReadyToStart)
        #expect(!result.hasCapability(.playableEvents))
        #expect(result.hasCapability(.movieRecording))
        #expect(result.hasCapability(.keyframeCapture))
        #expect(result.blockingIssues.map(\.permission) == [.inputMonitoring])
        #expect(result.blockingIssues.first?.affectedCapabilities == [.playableEvents])
    }
}

private extension SemanticRecordingPermissionSnapshot {
    static let allAuthorized = SemanticRecordingPermissionSnapshot(
        inputMonitoring: .authorized,
        accessibility: .authorized,
        screenRecording: .authorized
    )
}

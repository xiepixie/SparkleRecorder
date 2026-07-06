import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Preflight Presentation Tests")
struct SemanticRecordingPreflightPresentationTests {
    @Test("Ready preflight presentation offers start action")
    func readyPreflightPresentationOffersStartAction() async throws {
        let result = await SemanticRecordingPreflightClient.fixed(.allAuthorizedForPresentation).evaluate()

        let presentation = SemanticRecordingPreflightPresenter.presentation(for: result)

        #expect(presentation.status == .ready)
        #expect(presentation.canStart)
        #expect(presentation.title == "Semantic recording is ready")
        #expect(presentation.primaryAction.kind == .startRecording)
        #expect(presentation.secondaryAction == nil)
        #expect(presentation.issues.isEmpty)
        #expect(presentation.availableCapabilityLabels == [
            "Playable macro events",
            "Video recording",
            "Event-aligned keyframes",
            "OCR indexing",
            "AX element snapshots",
            "Window metadata"
        ])

        let encoded = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingPreflightPresentation.self,
            from: encoded
        )
        #expect(decoded == presentation)
    }

    @Test("Blocked preflight presentation surfaces permission actions")
    func blockedPreflightPresentationSurfacesPermissionActions() async {
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .denied,
            accessibility: .authorized,
            screenRecording: .denied
        )).evaluate()

        let presentation = SemanticRecordingPreflightPresenter.presentation(for: result)

        #expect(presentation.status == .blocked)
        #expect(!presentation.canStart)
        #expect(presentation.primaryAction.kind == .openPermissionSettings)
        #expect(presentation.primaryAction.permission == .inputMonitoring)
        #expect(presentation.secondaryAction?.kind == .retryPreflight)
        #expect(presentation.availableCapabilityLabels == [
            "AX element snapshots",
            "Window metadata"
        ])
        #expect(presentation.issues.map(\.permission) == [
            .inputMonitoring,
            .screenRecording,
            .screenRecording
        ])
        #expect(presentation.issues.map(\.severity) == [
            .blocking,
            .blocking,
            .blocking
        ])
        #expect(presentation.issues.first?.title == "Input Monitoring required")
        #expect(presentation.issues.first?.affectedCapabilityLabels == ["Playable macro events"])
    }

    @Test("Degraded preflight presentation can continue with guidance")
    func degradedPreflightPresentationCanContinueWithGuidance() async {
        let result = await SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
            inputMonitoring: .authorized,
            accessibility: .denied,
            screenRecording: .authorized
        )).evaluate()

        let presentation = SemanticRecordingPreflightPresenter.presentation(for: result)

        #expect(presentation.status == .degraded)
        #expect(presentation.canStart)
        #expect(presentation.primaryAction.kind == .continueDegraded)
        #expect(presentation.secondaryAction?.kind == .openPermissionSettings)
        #expect(presentation.secondaryAction?.permission == .accessibility)
        #expect(presentation.availableCapabilityLabels == [
            "Playable macro events",
            "Video recording",
            "Event-aligned keyframes",
            "OCR indexing"
        ])
        #expect(presentation.issues.map(\.title) == ["Accessibility recommended"])
        #expect(presentation.issues.first?.affectedCapabilityLabels == [
            "AX element snapshots",
            "Window metadata"
        ])
    }
}

private extension SemanticRecordingPermissionSnapshot {
    static let allAuthorizedForPresentation = SemanticRecordingPermissionSnapshot(
        inputMonitoring: .authorized,
        accessibility: .authorized,
        screenRecording: .authorized
    )
}

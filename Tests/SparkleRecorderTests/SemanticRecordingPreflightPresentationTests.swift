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
        #expect(presentation.decisionRows.map(\.role) == [
            .nextStep,
            .evidenceImpact,
            .privacyBoundary
        ])
        #expect(presentation.decisionRows[0].detail.contains("menu bar"))
        #expect(presentation.decisionRows[1].detail.contains("video"))
        #expect(presentation.decisionRows[2].detail.contains("privacy exclusions"))
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
        #expect(presentation.decisionRows.map(\.role) == [
            .nextStep,
            .evidenceImpact,
            .privacyBoundary
        ])
        #expect(presentation.decisionRows[0].detail.contains("blocked permission"))
        #expect(presentation.decisionRows[1].detail.contains("No visual evidence bundle"))
        #expect(presentation.decisionRows[2].detail.contains("visual evidence stays off"))
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
        #expect(presentation.decisionRows.map(\.role) == [
            .nextStep,
            .evidenceImpact,
            .privacyBoundary
        ])
        #expect(presentation.decisionRows[0].detail.contains("record now"))
        #expect(presentation.decisionRows[1].detail.contains("degraded evidence"))
        #expect(presentation.decisionRows[2].detail.contains("missing context is visible"))
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

    @Test("Preflight presentation decision copy has localized catalog entries")
    func preflightPresentationDecisionCopyHasLocalizedCatalogEntries() async throws {
        let presentations = await [
            SemanticRecordingPreflightClient.fixed(.allAuthorizedForPresentation).evaluate(),
            SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
                inputMonitoring: .denied,
                accessibility: .authorized,
                screenRecording: .denied
            )).evaluate(),
            SemanticRecordingPreflightClient.fixed(SemanticRecordingPermissionSnapshot(
                inputMonitoring: .authorized,
                accessibility: .denied,
                screenRecording: .authorized
            )).evaluate()
        ].map(SemanticRecordingPreflightPresenter.presentation)
        let keys = Set(presentations.flatMap { presentation in
            [presentation.title, presentation.summary] +
                presentation.decisionRows.flatMap { [$0.title, $0.detail] }
        })
        let catalog = try localizationCatalog()

        var missingEntries: [String] = []
        var missingEnglish: [String] = []
        var missingSimplifiedChinese: [String] = []
        for key in keys.sorted() {
            guard let entry = catalog[key] as? [String: Any] else {
                missingEntries.append(key)
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            if localizations["en"] == nil {
                missingEnglish.append(key)
            }
            if localizations["zh-Hans"] == nil {
                missingSimplifiedChinese.append(key)
            }
        }

        #expect(missingEntries.isEmpty, "Missing Localizable.xcstrings entries: \(missingEntries)")
        #expect(missingEnglish.isEmpty, "Missing English localizations: \(missingEnglish)")
        #expect(missingSimplifiedChinese.isEmpty, "Missing Simplified Chinese localizations: \(missingSimplifiedChinese)")
    }

    private func localizationCatalog() throws -> [String: Any] {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/SparkleRecorder/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(rootObject["strings"] as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension SemanticRecordingPermissionSnapshot {
    static let allAuthorizedForPresentation = SemanticRecordingPermissionSnapshot(
        inputMonitoring: .authorized,
        accessibility: .authorized,
        screenRecording: .authorized
    )
}

import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro reconstruction candidate provenance presentation")
struct MacroReconstructionCandidateProvenancePresentationTests {
    @Test("Package provenance summarizes objective and supplied evidence")
    func packageSummary() {
        let provenance = MacroCandidateImportProvenance(
            source: .reconstructionPackage,
            packageVersion: MacroReconstructionPackage.currentVersion,
            packageSourceRevision: "source",
            capabilityVersion: MacroCandidateCapabilities.current.version,
            authoringPolicyVersion: MacroReconstructionAuthoringPolicy.currentVersion,
            objective: .robust,
            visualEvidenceIncluded: true,
            mechanicalEvidenceIncluded: true,
            sourceEventsMatchRecording: true,
            artifactCount: 3,
            warnings: []
        )

        let presentation = MacroReconstructionCandidateProvenancePresentation.make(from: provenance)
        #expect(presentation.systemImage == "checkmark.seal")
        #expect(presentation.title == String(localized: "Verified AI package", table: "EditorUX"))
        #expect(presentation.detail.contains(String(localized: "Robust", table: "EditorUX")))
        #expect(presentation.detail.contains(String(localized: "Visual evidence included", table: "EditorUX")))
        #expect(presentation.detail.contains(String(localized: "Recording aligned", table: "EditorUX")))
    }

    @Test("Standalone candidate explicitly reports missing package provenance")
    func standaloneSummary() {
        let presentation = MacroReconstructionCandidateProvenancePresentation.make(from: nil)
        #expect(presentation.systemImage == "doc")
        #expect(presentation.title == String(localized: "Standalone candidate", table: "EditorUX"))
        #expect(presentation.detail == String(localized: "Package provenance unavailable.", table: "EditorUX"))
    }
}

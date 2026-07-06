import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Product Evidence Audit Tests")
struct AutomationProductEvidenceAuditTests {
    @Test("Fixture-only evidence reports S0 live gaps")
    func fixtureOnlyEvidenceReportsLiveGaps() {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
        )

        #expect(payload.requiredCount == 13)
        #expect(payload.satisfiedRequiredCount == 9)
        #expect(!payload.allRequiredPresent)
        #expect(payload.missingRequiredIDs == [
            "live-visual-diagnostics-open-reveal",
            "live-macro-evidence-open-reveal",
            "live-branch-evidence-consistency",
            "live-authoring-wysiwyg"
        ])
        #expect(payload.items.first { $0.id == "fixture-visual-diagnostics" }?.satisfied == true)
        #expect(payload.items.first { $0.id == "fixture-template-baseline-preview-refs" }?.satisfied == true)
        #expect(payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" }?.satisfied == false)
    }

    @Test("Authoring live evidence accepts either reorder or drag-link pair")
    func authoringLiveEvidenceAcceptsEitherPair() {
        let withDragLink = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoring)
                .union([
                    "live-drag-link-wysiwyg.mov",
                    "live-drag-link-wysiwyg.md"
                ]),
            sidecarContents: Self.validLiveSidecars
        )
        let withTaskReorder = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoring)
                .union([
                    "live-task-reorder-wysiwyg.mov",
                    "live-task-reorder-wysiwyg.md"
                ]),
            sidecarContents: Self.validLiveSidecars
        )

        #expect(withDragLink.allRequiredPresent)
        #expect(withTaskReorder.allRequiredPresent)
        #expect(withDragLink.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
        #expect(withTaskReorder.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
    }

    @Test("Live evidence accepts mp4 with a valid sidecar")
    func liveEvidenceAcceptsMP4WithValidSidecar() {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoringMP4)
                .union([
                    "live-drag-link-wysiwyg.mp4",
                    "live-drag-link-wysiwyg.md"
                ]),
            sidecarContents: Self.validLiveSidecars
        )

        #expect(payload.allRequiredPresent)
        #expect(payload.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
    }

    @Test("Missing a sidecar keeps evidence incomplete")
    func missingSidecarKeepsEvidenceIncomplete() {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoring)
                .union(["live-drag-link-wysiwyg.mov"]),
            sidecarContents: Self.validLiveSidecars
        )

        #expect(!payload.allRequiredPresent)
        #expect(payload.missingRequiredIDs == ["live-authoring-wysiwyg"])
        #expect(payload.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == false)
    }

    @Test("Template baseline preview fixture requires image and sidecar")
    func templateBaselinePreviewFixtureRequiresImageAndSidecar() {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles.subtracting(["template-baseline-preview-refs.md"])
        )

        #expect(!payload.allRequiredPresent)
        #expect(payload.missingRequiredIDs.contains("fixture-template-baseline-preview-refs"))
        #expect(payload.items.first { $0.id == "fixture-template-baseline-preview-refs" }?.satisfied == false)
    }

    @Test("Live sidecar must contain S0 capture fields")
    func liveSidecarMustContainS0CaptureFields() {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoring)
                .union([
                    "live-drag-link-wysiwyg.mov",
                    "live-drag-link-wysiwyg.md"
                ]),
            sidecarContents: Self.validLiveSidecars.merging(["live-drag-link-wysiwyg.md": "too thin"]) { _, new in
                new
            }
        )

        let item = payload.items.first { $0.id == "live-authoring-wysiwyg" }
        #expect(item?.satisfied == false)
        #expect(payload.missingRequiredIDs.contains("live-authoring-wysiwyg"))
        let sidecar = item?.fileGroups.flatMap { $0 }.first { $0.path == "live-drag-link-wysiwyg.md" }
        #expect(sidecar?.missingRequiredPhrases == AutomationProductEvidenceAudit.liveSidecarRequiredPhrases)
    }

    @Test("Live sidecar template uses audit labels and selected clip candidates")
    func liveSidecarTemplateUsesAuditLabelsAndSelectedClipCandidates() throws {
        let payload = try #require(AutomationProductEvidenceAudit.liveSidecarTemplate(
            id: "live-authoring-wysiwyg",
            sidecarPath: "live-drag-link-wysiwyg.md"
        ))

        #expect(payload.id == "live-authoring-wysiwyg")
        #expect(payload.sidecarPath == "live-drag-link-wysiwyg.md")
        #expect(payload.clipPathCandidates == [
            "live-drag-link-wysiwyg.mov",
            "live-drag-link-wysiwyg.mp4"
        ])
        #expect(payload.requiredLabels == AutomationProductEvidenceAudit.liveSidecarRequiredPhrases)
        for label in AutomationProductEvidenceAudit.liveSidecarRequiredPhrases {
            #expect(payload.template.contains(label))
        }
        #expect(payload.template.contains("Do not leave angle-bracket placeholders"))
    }

    @Test("Template placeholders keep live evidence incomplete")
    func templatePlaceholdersKeepLiveEvidenceIncomplete() throws {
        let template = try #require(AutomationProductEvidenceAudit.liveSidecarTemplate(
            id: "live-visual-diagnostics-open-reveal"
        ))
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
                .union(Self.requiredLiveFilesWithoutAuthoring)
                .union([
                    "live-drag-link-wysiwyg.mov",
                    "live-drag-link-wysiwyg.md"
                ]),
            sidecarContents: Self.validLiveSidecars.merging([
                "live-visual-diagnostics-open-reveal.md": template.template
            ]) { _, new in
                new
            }
        )

        let item = payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" }
        #expect(item?.satisfied == false)
        let sidecar = item?.fileGroups.flatMap { $0 }.first { $0.path == "live-visual-diagnostics-open-reveal.md" }
        #expect(sidecar?.missingRequiredPhrases.contains("Capture date:") == true)
        #expect(sidecar?.missingRequiredPhrases.contains("App build/run source:") == true)
    }

    @Test("Audit payload is codable")
    func auditPayloadIsCodable() throws {
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
        )

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AutomationProductEvidenceAuditPayload.self, from: encoded)

        #expect(decoded == payload)
    }

    private static let fixtureFiles: Set<String> = [
        "idle-workflow.png",
        "idle-workflow.md",
        "running-workflow.png",
        "running-workflow.md",
        "visual-diagnostics-drill-in.png",
        "visual-diagnostics-drill-in.md",
        "template-baseline-preview-refs.png",
        "template-baseline-preview-refs.md",
        "branch-evidence-drill-in.png",
        "branch-evidence-drill-in.md",
        "failed-run-detail.png",
        "failed-run-detail.md",
        "failed-run-preview-unavailable.png",
        "failed-run-preview-unavailable.md",
        "drag-link-authoring.png",
        "drag-link-authoring.md",
        "task-reorder-authoring.png",
        "task-reorder-authoring.md"
    ]

    private static let requiredLiveFilesWithoutAuthoring: Set<String> = [
        "live-visual-diagnostics-open-reveal.mov",
        "live-visual-diagnostics-open-reveal.md",
        "live-macro-evidence-open-reveal.mov",
        "live-macro-evidence-open-reveal.md",
        "live-branch-evidence-consistency.mov",
        "live-branch-evidence-consistency.md"
    ]

    private static let requiredLiveFilesWithoutAuthoringMP4: Set<String> = [
        "live-visual-diagnostics-open-reveal.mp4",
        "live-visual-diagnostics-open-reveal.md",
        "live-macro-evidence-open-reveal.mp4",
        "live-macro-evidence-open-reveal.md",
        "live-branch-evidence-consistency.mp4",
        "live-branch-evidence-consistency.md"
    ]

    private static let validLiveSidecars: [String: String] = [
        "live-visual-diagnostics-open-reveal.md": liveSidecar("visual diagnostics"),
        "live-macro-evidence-open-reveal.md": liveSidecar("macro evidence"),
        "live-branch-evidence-consistency.md": liveSidecar("branch evidence"),
        "live-drag-link-wysiwyg.md": liveSidecar("drag link"),
        "live-task-reorder-wysiwyg.md": liveSidecar("task reorder")
    ]

    private static func liveSidecar(_ label: String) -> String {
        """
        # \(label)

        - Capture date: 2026-07-06.
        - App build/run source: local build from current worktree.
        - Workflow/package: live workflow package.
        - User action: captured \(label) interaction.
        - Checklist item: S0 live product evidence.
        - Known gaps: none for this specific capture.
        - Evidence source: live App recording.
        """
    }
}

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
        let dragLinkPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        let taskReorderPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-task-reorder-wysiwyg.mov",
                "live-task-reorder-wysiwyg.md"
            ])
        let withDragLink = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: dragLinkPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: Self.fileByteCounts(for: dragLinkPaths)
        )
        let withTaskReorder = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: taskReorderPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: Self.fileByteCounts(for: taskReorderPaths)
        )

        #expect(withDragLink.allRequiredPresent)
        #expect(withTaskReorder.allRequiredPresent)
        #expect(withDragLink.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
        #expect(withTaskReorder.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
    }

    @Test("Live evidence accepts mp4 with a valid sidecar")
    func liveEvidenceAcceptsMP4WithValidSidecar() {
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoringMP4)
            .union([
                "live-drag-link-wysiwyg.mp4",
                "live-drag-link-wysiwyg.md"
            ])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecarsMP4,
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        #expect(payload.allRequiredPresent)
        #expect(payload.items.first { $0.id == "live-authoring-wysiwyg" }?.satisfied == true)
    }

    @Test("Missing a sidecar keeps evidence incomplete")
    func missingSidecarKeepsEvidenceIncomplete() {
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union(["live-drag-link-wysiwyg.mov"])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
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
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars.merging(["live-drag-link-wysiwyg.md": "too thin"]) { _, new in
                new
            },
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        let item = payload.items.first { $0.id == "live-authoring-wysiwyg" }
        #expect(item?.satisfied == false)
        #expect(payload.missingRequiredIDs.contains("live-authoring-wysiwyg"))
        let sidecar = item?.fileGroups.flatMap { $0 }.first { $0.path == "live-drag-link-wysiwyg.md" }
        #expect(sidecar?.missingRequiredPhrases == AutomationProductEvidenceAudit.liveSidecarRequiredPhrases)
    }

    @Test("Live sidecar must identify a live recording source")
    func liveSidecarMustIdentifyLiveRecordingSource() throws {
        let existingPaths = Self.fixtureFiles.union([
            "live-visual-diagnostics-open-reveal.mov",
            "live-visual-diagnostics-open-reveal.md"
        ])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: [
                "live-visual-diagnostics-open-reveal.md": Self.liveSidecar(
                    "visual diagnostics",
                    clipPath: "live-visual-diagnostics-open-reveal.mov",
                    evidenceSource: "fixture screenshot"
                )
            ],
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        let item = try #require(payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" })
        #expect(!item.satisfied)
        let sidecar = try #require(item.fileGroups.flatMap { $0 }.first {
            $0.path == "live-visual-diagnostics-open-reveal.md"
        })
        #expect(sidecar.missingRequiredPhrases == ["Evidence source:"])
    }

    @Test("Live sidecar clip file must match the satisfying clip")
    func liveSidecarClipFileMustMatchSatisfyingClip() throws {
        let existingPaths = Self.fixtureFiles.union([
            "live-visual-diagnostics-open-reveal.mov",
            "live-visual-diagnostics-open-reveal.md"
        ])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: [
                "live-visual-diagnostics-open-reveal.md": Self.liveSidecar(
                    "visual diagnostics",
                    clipPath: "live-visual-diagnostics-open-reveal.mp4"
                )
            ],
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        let item = try #require(payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" })
        #expect(!item.satisfied)
        let movGroupSidecar = try #require(item.fileGroups.flatMap { $0 }.first { file in
            file.path == "live-visual-diagnostics-open-reveal.md" &&
                file.missingRequiredPhrases.contains("Clip file:")
        })
        #expect(movGroupSidecar.missingRequiredPhrases == ["Clip file:"])
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

    @Test("Completed live sidecar satisfies audit when matching clip exists")
    func completedLiveSidecarSatisfiesAuditWhenMatchingClipExists() throws {
        let completed = try #require(AutomationProductEvidenceAudit.completedLiveSidecar(
            id: "live-visual-diagnostics-open-reveal",
            completion: Self.sidecarCompletion(clipPath: "live-visual-diagnostics-open-reveal.mov")
        ))
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles.union([
                "live-visual-diagnostics-open-reveal.mov",
                "live-visual-diagnostics-open-reveal.md"
            ]),
            sidecarContents: [
                "live-visual-diagnostics-open-reveal.md": completed.content
            ],
            fileByteCounts: [
                "live-visual-diagnostics-open-reveal.mov": 1_024
            ]
        )

        let item = try #require(payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" })
        #expect(item.satisfied)
        #expect(completed.content.contains("- Clip file: `live-visual-diagnostics-open-reveal.mov`"))
        #expect(!completed.content.contains("<YYYY-MM-DD>"))
        #expect(!completed.content.contains("<live App recording"))
    }

    @Test("Completed live sidecar rejects unknown clip candidate")
    func completedLiveSidecarRejectsUnknownClipCandidate() {
        let completed = AutomationProductEvidenceAudit.completedLiveSidecar(
            id: "live-visual-diagnostics-open-reveal",
            completion: Self.sidecarCompletion(clipPath: "wrong-video.mov")
        )

        #expect(completed == nil)
    }

    @Test("Completed authoring sidecar respects selected authoring path")
    func completedAuthoringSidecarRespectsSelectedAuthoringPath() throws {
        let completed = try #require(AutomationProductEvidenceAudit.completedLiveSidecar(
            id: "live-authoring-wysiwyg",
            sidecarPath: "live-drag-link-wysiwyg.md",
            completion: Self.sidecarCompletion(clipPath: "live-drag-link-wysiwyg.mp4")
        ))

        #expect(completed.sidecarPath == "live-drag-link-wysiwyg.md")
        #expect(completed.clipPath == "live-drag-link-wysiwyg.mp4")
        #expect(completed.content.contains("Live Authoring WYSIWYG (`live-authoring-wysiwyg`)"))
    }

    @Test("Live capture plan lists missing S0 gates and sidecar commands")
    func liveCapturePlanListsMissingS0GatesAndSidecarCommands() {
        let payload = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
        )

        #expect(payload.missingLiveCount == 4)
        #expect(!payload.allLiveSatisfied)
        #expect(payload.items.map(\.id) == [
            "live-visual-diagnostics-open-reveal",
            "live-macro-evidence-open-reveal",
            "live-branch-evidence-consistency",
            "live-authoring-wysiwyg"
        ])

        let visual = payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" }
        #expect(visual?.satisfied == false)
        #expect(visual?.options.first?.sidecarPath == "live-visual-diagnostics-open-reveal.md")
        #expect(visual?.options.first?.clipPathCandidates == [
            "live-visual-diagnostics-open-reveal.mov",
            "live-visual-diagnostics-open-reveal.mp4"
        ])
        #expect(visual?.options.first?.missingPaths == [
            "live-visual-diagnostics-open-reveal.md",
            "live-visual-diagnostics-open-reveal.mov",
            "live-visual-diagnostics-open-reveal.mp4"
        ])
        #expect(visual?.options.first?.sidecarTemplateCommand == "SparkleRecorder workflow product-evidence sidecar-template live-visual-diagnostics-open-reveal")
    }

    @Test("Authoring capture plan offers reorder and drag-link options")
    func authoringCapturePlanOffersReorderAndDragLinkOptions() throws {
        let payload = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
        )
        let authoring = try #require(payload.items.first { $0.id == "live-authoring-wysiwyg" })

        #expect(authoring.options.map(\.sidecarPath) == [
            "live-task-reorder-wysiwyg.md",
            "live-drag-link-wysiwyg.md"
        ])
        #expect(authoring.options[0].clipPathCandidates == [
            "live-task-reorder-wysiwyg.mov",
            "live-task-reorder-wysiwyg.mp4"
        ])
        #expect(authoring.options[1].sidecarTemplateCommand == "SparkleRecorder workflow product-evidence sidecar-template live-authoring-wysiwyg --sidecar live-drag-link-wysiwyg.md")
    }

    @Test("Live capture plan reports satisfied live gates")
    func liveCapturePlanReportsSatisfiedLiveGates() {
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        let payload = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        #expect(payload.missingLiveCount == 0)
        #expect(payload.allLiveSatisfied)
        #expect(payload.items.allSatisfy { $0.satisfied })
    }

    @Test("Empty live clip keeps evidence incomplete")
    func emptyLiveClipKeepsEvidenceIncomplete() throws {
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        var fileByteCounts = Self.fileByteCounts(for: existingPaths)
        fileByteCounts["live-visual-diagnostics-open-reveal.mov"] = 0
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: fileByteCounts
        )

        #expect(!payload.allRequiredPresent)
        #expect(payload.missingRequiredIDs == ["live-visual-diagnostics-open-reveal"])
        let visualItem = try #require(payload.items.first { $0.id == "live-visual-diagnostics-open-reveal" })
        let clip = try #require(visualItem.fileGroups.flatMap { $0 }.first {
            $0.path == "live-visual-diagnostics-open-reveal.mov"
        })
        #expect(clip.byteCount == 0)
        #expect(clip.minimumByteCount == AutomationProductEvidenceAudit.minimumLiveClipByteCount)
        #expect(!clip.meetsMinimumByteCount)

        let plan = AutomationProductEvidenceAudit.liveCapturePlan(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: fileByteCounts
        )
        let visualPlan = try #require(plan.items.first { $0.id == "live-visual-diagnostics-open-reveal" })
        #expect(visualPlan.satisfied == false)
        #expect(visualPlan.options.first?.undersizedPaths == ["live-visual-diagnostics-open-reveal.mov"])
    }

    @Test("Live sidecar drafts prepare missing S0 gate notes")
    func liveSidecarDraftsPrepareMissingS0GateNotes() {
        let payload = AutomationProductEvidenceAudit.liveSidecarDrafts(
            directory: "/tmp/product-evidence",
            existingPaths: Self.fixtureFiles
        )

        #expect(payload.includeSatisfied == false)
        #expect(payload.drafts.map(\.sidecarPath) == [
            "live-visual-diagnostics-open-reveal.md",
            "live-macro-evidence-open-reveal.md",
            "live-branch-evidence-consistency.md",
            "live-task-reorder-wysiwyg.md",
            "live-drag-link-wysiwyg.md"
        ])
        #expect(payload.drafts.allSatisfy { draft in
            draft.template.contains("Do not leave angle-bracket placeholders")
        })
    }

    @Test("Live sidecar drafts skip satisfied gates by default")
    func liveSidecarDraftsSkipSatisfiedGatesByDefault() {
        let existingPaths = Self.fixtureFiles
            .union([
                "live-visual-diagnostics-open-reveal.mp4",
                "live-visual-diagnostics-open-reveal.md"
            ])
        let payload = AutomationProductEvidenceAudit.liveSidecarDrafts(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecarsMP4,
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
        )

        #expect(!payload.drafts.map(\.sidecarPath).contains("live-visual-diagnostics-open-reveal.md"))
        #expect(payload.drafts.map(\.sidecarPath).contains("live-macro-evidence-open-reveal.md"))
    }

    @Test("Live sidecar drafts can include satisfied gates for rehearsal")
    func liveSidecarDraftsCanIncludeSatisfiedGatesForRehearsal() {
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        let payload = AutomationProductEvidenceAudit.liveSidecarDrafts(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars,
            fileByteCounts: Self.fileByteCounts(for: existingPaths),
            includeSatisfied: true
        )

        #expect(payload.drafts.map(\.sidecarPath) == [
            "live-visual-diagnostics-open-reveal.md",
            "live-macro-evidence-open-reveal.md",
            "live-branch-evidence-consistency.md",
            "live-task-reorder-wysiwyg.md",
            "live-drag-link-wysiwyg.md"
        ])
    }

    @Test("Template placeholders keep live evidence incomplete")
    func templatePlaceholdersKeepLiveEvidenceIncomplete() throws {
        let template = try #require(AutomationProductEvidenceAudit.liveSidecarTemplate(
            id: "live-visual-diagnostics-open-reveal"
        ))
        let existingPaths = Self.fixtureFiles
            .union(Self.requiredLiveFilesWithoutAuthoring)
            .union([
                "live-drag-link-wysiwyg.mov",
                "live-drag-link-wysiwyg.md"
            ])
        let payload = AutomationProductEvidenceAudit.evaluate(
            directory: "/tmp/product-evidence",
            existingPaths: existingPaths,
            sidecarContents: Self.validLiveSidecars.merging([
                "live-visual-diagnostics-open-reveal.md": template.template
            ]) { _, new in
                new
            },
            fileByteCounts: Self.fileByteCounts(for: existingPaths)
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
        "live-visual-diagnostics-open-reveal.md": liveSidecar(
            "visual diagnostics",
            clipPath: "live-visual-diagnostics-open-reveal.mov"
        ),
        "live-macro-evidence-open-reveal.md": liveSidecar(
            "macro evidence",
            clipPath: "live-macro-evidence-open-reveal.mov"
        ),
        "live-branch-evidence-consistency.md": liveSidecar(
            "branch evidence",
            clipPath: "live-branch-evidence-consistency.mov"
        ),
        "live-drag-link-wysiwyg.md": liveSidecar(
            "drag link",
            clipPath: "live-drag-link-wysiwyg.mov"
        ),
        "live-task-reorder-wysiwyg.md": liveSidecar(
            "task reorder",
            clipPath: "live-task-reorder-wysiwyg.mov"
        )
    ]

    private static let validLiveSidecarsMP4: [String: String] = [
        "live-visual-diagnostics-open-reveal.md": liveSidecar(
            "visual diagnostics",
            clipPath: "live-visual-diagnostics-open-reveal.mp4"
        ),
        "live-macro-evidence-open-reveal.md": liveSidecar(
            "macro evidence",
            clipPath: "live-macro-evidence-open-reveal.mp4"
        ),
        "live-branch-evidence-consistency.md": liveSidecar(
            "branch evidence",
            clipPath: "live-branch-evidence-consistency.mp4"
        ),
        "live-drag-link-wysiwyg.md": liveSidecar(
            "drag link",
            clipPath: "live-drag-link-wysiwyg.mp4"
        ),
        "live-task-reorder-wysiwyg.md": liveSidecar(
            "task reorder",
            clipPath: "live-task-reorder-wysiwyg.mp4"
        )
    ]

    private static func fileByteCounts(for paths: Set<String>) -> [String: Int64] {
        Dictionary(uniqueKeysWithValues: paths.compactMap { path in
            guard path.hasSuffix(".mov") || path.hasSuffix(".mp4") else {
                return nil
            }
            return (path, 1_024)
        })
    }

    private static func liveSidecar(
        _ label: String,
        clipPath: String,
        evidenceSource: String = "live App recording."
    ) -> String {
        """
        # \(label)

        - Capture date: 2026-07-06.
        - Worktree note: main at abc123, dirty only product evidence clip.
        - App build/run source: local build from current worktree.
        - Workflow/package: live workflow package.
        - User action: captured \(label) interaction.
        - Checklist item: S0 live product evidence.
        - Known gaps: none for this specific capture.
        - Evidence source: \(evidenceSource)
        - Clip file: `\(clipPath)`
        """
    }

    private static func sidecarCompletion(
        clipPath: String
    ) -> AutomationProductEvidenceSidecarCompletion {
        AutomationProductEvidenceSidecarCompletion(
            clipPath: clipPath,
            captureDate: "2026-07-06",
            worktreeNote: "main at abc123, dirty only product evidence clip.",
            appBuildRunSource: "local swift run SparkleRecorder",
            workflowPackage: "fixture-owned live workflow package",
            userAction: "opened the artifact preview and reveal action from Run Detail.",
            knownGaps: "none for this specific capture.",
            evidenceSource: "live App recording."
        )
    }
}

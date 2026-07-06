import Foundation
import Testing

@Suite("Semantic Recording Acceptance Checklist Tests")
struct SemanticRecordingAcceptanceChecklistTests {
    @Test("Unchecked checklist items stay covered by the current open gate audit")
    func uncheckedChecklistItemsStayCoveredByOpenGateAudit() throws {
        let checklist = try String(
            contentsOf: acceptanceChecklistURL(),
            encoding: .utf8
        )
        let uncheckedItems = Self.uncheckedChecklistItems(in: checklist)
        let expectedPrefixes = Self.expectedUncheckedItemPrefixes

        let unexpected = uncheckedItems.filter { item in
            !expectedPrefixes.contains { item.hasPrefix($0) }
        }
        let missing = expectedPrefixes.filter { prefix in
            !uncheckedItems.contains { $0.hasPrefix(prefix) }
        }

        #expect(
            unexpected.isEmpty,
            "New unchecked semantic-recording checklist items must be mapped in this audit test and in Current Open Gate Audit: \(unexpected)"
        )
        #expect(
            missing.isEmpty,
            "Expected unchecked semantic-recording checklist items disappeared or changed; update the audit map only after reviewing evidence: \(missing)"
        )

        let auditSection = try #require(Self.section(named: "Current Open Gate Audit", in: checklist))
        for gate in Self.expectedGateGroups {
            #expect(
                auditSection.contains("| \(gate) |"),
                "Current Open Gate Audit is missing gate group: \(gate)"
            )
        }
        for phrase in Self.requiredAuditPhrases {
            #expect(
                auditSection.contains(phrase),
                "Current Open Gate Audit no longer explains open evidence phrase: \(phrase)"
            )
        }
    }

    private static let expectedGateGroups: [String] = [
        "S2 authorized live bundle",
        "S2 ordinary Recorder bridge",
        "S2 safety/privacy/cleanup",
        "S2 root/id policy",
        "S3 live Review and frame-to-condition",
        "S4 product-ready live AI",
        "App Knowledge",
        "Workflow/UI polish not tied to S2 live bundle"
    ]

    private static let requiredAuditPhrases: [String] = [
        "S2 live semantic recording product evidence",
        "target-window `.mov`",
        "target-window keyframes",
        "app-edge persisted bundle artifacts",
        "app-edge Vision OCR",
        "pixel sampling",
        "recorded video/keyframes in Macro Review",
        "Draft Preview evidence refs from live recording frames",
        "redacted frame/video consumption",
        "reviewed text-anchor mutation decision",
        "S4 default/live catalog readiness",
        "image disappeared / region changed / pixel live conditions",
        "visual locator replacement",
        "image-byte visual similarity",
        "stored/live `workflow draft from-recording`",
        "AI cleanup screenshot",
        "natural-language macro reuse",
        "workflow loop product semantics"
    ]

    private static let expectedUncheckedItemPrefixes: [String] = [
        "S2 live semantic recording product evidence is accepted as the unblocker for S3/S4.",
        "S2 authorized live bundle gate is accepted.",
        "S2 ordinary Recorder bridge gate is accepted.",
        "S2 safety/privacy/cleanup gate is accepted.",
        "S2 product root/id policy gate is accepted.",
        "S3 installed-app Review gate is accepted.",
        "S3 live frame-to-condition and Draft Preview gate is accepted.",
        "S4 product-ready live catalog/query gate is accepted.",
        "S4 stored/live suggestion and draft synthesis gate is accepted.",
        "OCR/visual region picker renders wait/verify targets as region boxes with clear labels, and reserves click circles/pulses for actual click actions.",
        "Action preview/grouping follows the user-facing semantics from `13-direction-decision-and-remaining-slices.md`:",
        "Workflow orchestration supports explicit loop semantics without encoding loops as dependency cycles.",
        "Capture live cleanup product evidence for manual and scheduled retention cleanup.",
        "Record target-window `.mov` during macro recording through `SCRecordingOutput`.",
        "Record target-window keyframes during macro recording.",
        "Persist semantic recording bundle files and artifacts through an app-edge bundle store.",
        "Provide keyframe-only light mode only after default video path is safe and reviewable.",
        "Show recorded video/keyframes in Macro Review.",
        "Run OCR on selected/key frames through app-edge Vision adapter.",
        "Support pixel sampling from recorded frames.",
        "Store source frame ID, surface ID, crop bounds, search region and threshold for every extracted visual asset.",
        "User can create image appeared/disappeared condition from recorded frame crop.",
        "User can create region changed baseline from recorded frame region.",
        "User can replace one fragile coordinate click with visual locator suggestion.",
        "Product-ready default/live `recording list/show/explain --json`",
        "Product-ready default/live `recording ocr search --json`",
        "Product-ready image-byte visual similarity search",
        "Live/stored-bundle `recording suggest waits/locators/conditions/cleanup --json` with real suggestion synthesis.",
        "Product-ready stored/live `workflow draft from-recording --json` with real suggestion synthesis, missing/deleted artifact status and Review/Draft Preview alignment.",
        "Draft Preview shows evidence references from recording frames in live product evidence.",
        "Group recordings/macros by app bundle ID and surface family.",
        "Build app knowledge summary from existing recordings.",
        "CLI can answer which existing macros/anchors may satisfy a natural-language goal.",
        "AI can compose a draft from existing macros without requiring a new recording when evidence is sufficient.",
        "UI explains reused recordings and missing evidence.",
        "Recording review screenshot with video frame, event row and OCR overlay.",
        "Frame-to-condition creation clip.",
        "AI cleanup suggestion screenshot with evidence explanation."
    ]

    private static func uncheckedChecklistItems(in markdown: String) -> [String] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let marker = "- [ ] "
                guard line.hasPrefix(marker) else {
                    return nil
                }
                return String(line.dropFirst(marker.count))
            }
    }

    private static func section(named heading: String, in markdown: String) -> String? {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        let headingLine = "## \(heading)"
        guard let start = lines.firstIndex(where: { $0 == headingLine }) else {
            return nil
        }
        let rest = lines[lines.index(after: start)...]
        let end = rest.firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
        return rest[..<end].joined(separator: "\n")
    }

    private func acceptanceChecklistURL() -> URL {
        repositoryRoot()
            .appendingPathComponent("docs/semantic-recording-ai/acceptance-checklist.md")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

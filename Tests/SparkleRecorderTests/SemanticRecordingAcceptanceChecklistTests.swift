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

    @Test("Open live gates stay mapped to playbook and evidence intake directory")
    func openLiveGatesStayMappedToPlaybookAndEvidenceDirectory() throws {
        let checklist = try String(
            contentsOf: semanticRecordingURL("acceptance-checklist.md"),
            encoding: .utf8
        )
        let playbook = try String(
            contentsOf: semanticRecordingURL("15-s2-live-evidence-playbook.md"),
            encoding: .utf8
        )
        let evidenceReadme = try String(
            contentsOf: semanticRecordingURL("live-evidence/README.md"),
            encoding: .utf8
        )
        let auditSection = try #require(Self.section(named: "Current Open Gate Audit", in: checklist))

        for phrase in Self.requiredPlaybookPhrases {
            #expect(
                playbook.contains(phrase),
                "S2 live evidence playbook no longer contains required phrase: \(phrase)"
            )
        }
        for phrase in Self.requiredEvidenceReadmePhrases {
            #expect(
                evidenceReadme.contains(phrase),
                "Live evidence README no longer contains required phrase: \(phrase)"
            )
        }
        for gate in Self.playbookBackedOpenGateGroups {
            #expect(
                auditSection.contains("| \(gate.checklistGroup) |"),
                "Current Open Gate Audit is missing playbook-backed group: \(gate.checklistGroup)"
            )
            #expect(
                playbook.contains(gate.playbookGate),
                "S2 playbook no longer maps gate: \(gate.playbookGate)"
            )
            #expect(
                evidenceReadme.contains(gate.evidenceGate),
                "Live evidence README no longer maps gate: \(gate.evidenceGate)"
            )
        }
    }

    @Test("Final gap alignment preserves S3 closeout and S0 S1 to S2 handoff")
    func finalGapAlignmentPreservesS3CloseoutAndS0S1ToS2Handoff() throws {
        let finalGap = try String(
            contentsOf: semanticRecordingURL("14-s0-s4-final-gap-alignment.md"),
            encoding: .utf8
        )
        let closeoutSection = try #require(Self.section(
            named: "1.3 S3 Closeout Modification Ledger",
            in: finalGap
        ))
        let s2GapSection = try #require(Self.section(
            named: "3. Remaining Gaps From S0/S1 To S2",
            in: finalGap
        ))

        for phrase in Self.requiredS3CloseoutLedgerPhrases {
            #expect(
                closeoutSection.contains(phrase),
                "S3 closeout ledger no longer contains required phrase: \(phrase)"
            )
        }
        for phrase in Self.requiredS0S1ToS2HandoffPhrases {
            #expect(
                s2GapSection.contains(phrase),
                "S0/S1 -> S2 handoff section no longer contains required phrase: \(phrase)"
            )
        }
    }

    @Test("Checked checklist items carry direct evidence anchors")
    func checkedChecklistItemsCarryDirectEvidenceAnchors() throws {
        let checklist = try String(
            contentsOf: semanticRecordingURL("acceptance-checklist.md"),
            encoding: .utf8
        )
        let missingEvidence = Self.checkedChecklistItems(in: checklist).filter { item in
            !Self.acceptedCheckedEvidenceMarkers.contains { marker in
                item.text.contains(marker)
            }
        }

        #expect(
            missingEvidence.isEmpty,
            "Checked semantic-recording checklist items must cite direct evidence or an accepted contract: \(missingEvidence.map { "\($0.line): \($0.text)" })"
        )
    }

    @Test("Unchecked checklist items describe required evidence or current blocker")
    func uncheckedChecklistItemsDescribeRequiredEvidenceOrCurrentBlocker() throws {
        let checklist = try String(
            contentsOf: semanticRecordingURL("acceptance-checklist.md"),
            encoding: .utf8
        )
        let missingCriteria = Self.uncheckedChecklistItemBlocks(in: checklist).filter { item in
            !Self.acceptedUncheckedCriteriaMarkers.contains { marker in
                item.block.contains(marker)
            }
        }

        #expect(
            missingCriteria.isEmpty,
            "Unchecked semantic-recording checklist items must describe required evidence, current proof, or remaining blocker: \(missingCriteria.map { "\($0.line): \($0.title)" })"
        )
    }

    @Test("Semantic recording documentation keeps local markdown links resolvable")
    func semanticRecordingDocumentationKeepsLocalMarkdownLinksResolvable() throws {
        let root = repositoryRoot()
        let docs = try Self.semanticRecordingDocumentationURLs(repositoryRoot: root)
        let missingLinks = try docs.flatMap { sourceURL in
            let markdown = try String(contentsOf: sourceURL, encoding: .utf8)
            return Self.localMarkdownLinks(in: markdown).compactMap { target -> String? in
                guard !Self.isExternalMarkdownTarget(target) else {
                    return nil
                }
                let path = Self.pathTargetWithoutFragment(target)
                guard !path.isEmpty else {
                    return nil
                }
                let resolvedURL = Self.resolvedMarkdownTarget(
                    path,
                    sourceURL: sourceURL,
                    repositoryRoot: root
                )
                guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                    return "\(Self.relativePath(sourceURL, repositoryRoot: root)) -> \(target)"
                }
                return nil
            }
        }

        #expect(
            missingLinks.isEmpty,
            "Semantic recording docs contain broken local markdown links: \(missingLinks)"
        )
    }

    @Test("Live evidence directory rejects placeholder artifacts")
    func liveEvidenceDirectoryRejectsPlaceholderArtifacts() throws {
        let root = repositoryRoot()
        let evidenceRoot = semanticRecordingURL("live-evidence")
        let directContents = try FileManager.default.contentsOfDirectory(
            at: evidenceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        )
        let invalidRootFiles = directContents.filter { url in
            guard !Self.isDirectory(url) else { return false }
            return url.lastPathComponent != "README.md" && !Self.isIgnoredEvidenceFile(url)
        }
        #expect(
            invalidRootFiles.isEmpty,
            "Live evidence files must live inside a reviewed run directory, not the intake root: \(invalidRootFiles.map { Self.relativePath($0, repositoryRoot: root) })"
        )

        let evidenceFiles = try Self.filesUnder(evidenceRoot)
            .filter { $0.lastPathComponent != "README.md" }
            .filter { !Self.isIgnoredEvidenceFile($0) }
        let emptyArtifacts = evidenceFiles.filter { Self.fileSize($0) == 0 }
        let placeholderSidecars = try evidenceFiles.filter { url in
            guard url.pathExtension == "md" else { return false }
            let text = try String(contentsOf: url, encoding: .utf8)
            return !Self.requiredEvidenceSidecarMarkers.allSatisfy { text.contains($0) }
        }
        let emptyVideos = evidenceFiles.filter { url in
            Self.liveEvidenceVideoExtensions.contains(url.pathExtension.lowercased()) &&
                Self.fileSize(url) < Self.minimumLiveEvidenceVideoBytes
        }

        #expect(
            emptyArtifacts.isEmpty,
            "Live evidence artifacts must not be empty placeholders: \(emptyArtifacts.map { Self.relativePath($0, repositoryRoot: root) })"
        )
        #expect(
            placeholderSidecars.isEmpty,
            "Live evidence sidecars must include checklist/gate and remaining-gate markers: \(placeholderSidecars.map { Self.relativePath($0, repositoryRoot: root) })"
        )
        #expect(
            emptyVideos.isEmpty,
            "Live evidence video clips must not be zero-byte or tiny placeholders: \(emptyVideos.map { Self.relativePath($0, repositoryRoot: root) })"
        )
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
        "live app-edge video/keyframe artifact production",
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

    private static let requiredPlaybookPhrases: [String] = [
        "docs/semantic-recording-ai/live-evidence/",
        "Do not check a live-product box",
        "fixture evidence",
        "blocked preflight evidence",
        "explicit temp bundle path only",
        "synthetic redaction rehearsal only",
        "S3/S4 handoff"
    ]

    private static let requiredEvidenceReadmePhrases: [String] = [
        "no live gate is closed by files in this directory alone",
        "s2-preflight.md",
        "s2-live-smoke.md",
        "s2-recorder-bridge.md",
        "s3-frame-to-condition.mov",
        "s4-live-query.md",
        "explicit statement of which gates remain open",
        "fixture evidence",
        "blocked preflight evidence",
        "explicit temp bundle path only",
        "synthetic redaction rehearsal only"
    ]

    private static let playbookBackedOpenGateGroups: [(
        checklistGroup: String,
        playbookGate: String,
        evidenceGate: String
    )] = [
        (
            "S2 authorized live bundle",
            "S2 authorized live bundle",
            "S2 authorized live bundle"
        ),
        (
            "S2 ordinary Recorder bridge",
            "S2 ordinary Recorder bridge",
            "S2 ordinary Recorder bridge"
        ),
        (
            "S2 safety/privacy/cleanup",
            "S2 safety/privacy/cleanup",
            "S2 safety/privacy/cleanup"
        ),
        (
            "S2 root/id policy",
            "S2 root/id policy",
            "S2 root/id policy"
        ),
        (
            "S3 live Review and frame-to-condition",
            "S3 installed-app Review",
            "S3 installed-app Review"
        ),
        (
            "S4 product-ready live AI",
            "S4 product-ready live query",
            "S4 product-ready live query"
        )
    ]

    private static let requiredS3CloseoutLedgerPhrases: [String] = [
        "product-shaping maintenance changes, not new live semantic-recording acceptance",
        "Macro Editor text-target repair",
        "Action preview affordance",
        "Passive wait maintenance",
        "Time Stretch",
        "MacroTransformerTimingTests",
        "Draft Preview loop explanation",
        "Review action contract",
        "S2 bundle-store first pass",
        "Live evidence intake guard",
        "Does not close installed-app preview/grouping product evidence",
        "It is not semantic video evidence",
        "Does not create new S4 live suggestions",
        "It does not close any live gate by itself",
        "proving that the ordinary recorder can produce the live bundle"
    ]

    private static let requiredS0S1ToS2HandoffPhrases: [String] = [
        "S2 should not start by designing new Review UI or new AI surfaces",
        "S0/S1 -> S2 Handoff Checklist",
        "S0 live-evidence discipline",
        "S0 Open/Reveal pattern",
        "S1 safe artifact refs",
        "S1 event/frame/timeline ids",
        "S1 query/suggestion ids",
        "Existing Recorder truth",
        "Experimental bridge",
        "Privacy/safety policy",
        "The playable `RecordedEvent` macro remains the execution truth",
        "Normal stop attaches `SavedMacro.semanticRecording`",
        "sensitive visual capture is suppressed before a bundle is attached"
    ]

    private static let acceptedCheckedEvidenceMarkers: [String] = [
        "Evidence:",
        "Accepted contract:"
    ]

    private static let acceptedUncheckedCriteriaMarkers: [String] = [
        "Required evidence:",
        "Current ",
        "Partial ",
        "Product acceptance",
        "Live ",
        "First-pass",
        "first pass",
        "remaining",
        "remain",
        "open",
        "future",
        "blocked",
        "gated"
    ]

    private static let requiredEvidenceSidecarMarkers: [String] = [
        "Checklist item:",
        "Gates remain open:"
    ]

    private static let liveEvidenceVideoExtensions: Set<String> = [
        "mov",
        "mp4"
    ]

    private static let minimumLiveEvidenceVideoBytes = 1_024

    private static func checkedChecklistItems(in markdown: String) -> [(line: Int, text: String)] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, line -> (line: Int, text: String)? in
                let marker = "- [x] "
                guard line.hasPrefix(marker) else {
                    return nil
                }
                return (offset + 1, String(line.dropFirst(marker.count)))
            }
    }

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

    private static func uncheckedChecklistItemBlocks(
        in markdown: String
    ) -> [(line: Int, title: String, block: String)] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var results: [(line: Int, title: String, block: String)] = []
        var currentLine: Int?
        var currentTitle: String?
        var currentBlock: [String] = []

        func flush() {
            guard let line = currentLine, let title = currentTitle else { return }
            results.append((line, title, currentBlock.joined(separator: "\n")))
            currentLine = nil
            currentTitle = nil
            currentBlock = []
        }

        for (offset, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            if line.hasPrefix("- [ ] ") {
                flush()
                currentLine = offset + 1
                currentTitle = String(line.dropFirst("- [ ] ".count))
                currentBlock = [line]
                continue
            }
            if line.hasPrefix("- [x] ") || line.hasPrefix("## ") {
                flush()
                continue
            }
            if currentLine != nil {
                currentBlock.append(line)
            }
        }
        flush()
        return results
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

    private static func semanticRecordingDocumentationURLs(repositoryRoot: URL) throws -> [URL] {
        let docsRoot = repositoryRoot.appendingPathComponent("docs/semantic-recording-ai")
        let enumerator = try #require(FileManager.default.enumerator(
            at: docsRoot,
            includingPropertiesForKeys: nil
        ))
        let semanticDocs = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "md" }
        return semanticDocs + [
            repositoryRoot.appendingPathComponent("docs/DOCUMENTATION_STATUS.md")
        ]
    }

    private static func localMarkdownLinks(in markdown: String) -> [String] {
        let pattern = #"\[[^\]]+\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: range).compactMap { match in
            guard let targetRange = Range(match.range(at: 1), in: markdown) else {
                return nil
            }
            return String(markdown[targetRange])
        }
    }

    private static func isExternalMarkdownTarget(_ target: String) -> Bool {
        target.contains("://") ||
            target.hasPrefix("mailto:") ||
            target.hasPrefix("#")
    }

    private static func pathTargetWithoutFragment(_ target: String) -> String {
        var path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        if path.hasPrefix("<"), path.hasSuffix(">") {
            path.removeFirst()
            path.removeLast()
        }
        return path
    }

    private static func resolvedMarkdownTarget(
        _ target: String,
        sourceURL: URL,
        repositoryRoot: URL
    ) -> URL {
        if target.hasPrefix("/") {
            return URL(fileURLWithPath: target)
        }
        return sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(target)
            .standardizedFileURL
    }

    private static func relativePath(_ url: URL, repositoryRoot: URL) -> String {
        let rootPath = repositoryRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return path
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func filesUnder(_ directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
        ))
        return enumerator
            .compactMap { $0 as? URL }
            .filter { !isDirectory($0) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func isIgnoredEvidenceFile(_ url: URL) -> Bool {
        url.lastPathComponent == ".DS_Store"
    }

    private func acceptanceChecklistURL() -> URL {
        semanticRecordingURL("acceptance-checklist.md")
    }

    private func semanticRecordingURL(_ relativePath: String) -> URL {
        repositoryRoot()
            .appendingPathComponent("docs/semantic-recording-ai")
            .appendingPathComponent(relativePath)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

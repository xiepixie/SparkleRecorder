import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Issue Presentation Tests")
struct SemanticRecordingReviewIssuePresentationTests {
    @Test("Bundle health issues use user-facing presentation copy")
    func bundleHealthIssuesUseUserFacingCopy() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let unsupported = SemanticRecordingReviewIssuePresenter.validationIssue(
            .unsupportedSchemaVersion(SemanticRecordingSchemaVersion(major: 9, minor: 0))
        )
        let duplicate = SemanticRecordingReviewIssuePresenter.validationIssue(
            .duplicateFrameID(id)
        )
        let brokenReference = SemanticRecordingReviewIssuePresenter.validationIssue(
            .timelineEventReferencesMissingFrame(eventID: id, frameID: UUID())
        )

        #expect(!unsupported.contains("unsupportedSchemaVersion"))
        #expect(!duplicate.contains("duplicateFrameID"))
        #expect(!brokenReference.contains("timelineEventReferencesMissingFrame"))
        #expect(!unsupported.isEmpty)
        #expect(!duplicate.isEmpty)
        #expect(!brokenReference.isEmpty)
    }

    @Test("Suppression reasons never expose raw enum values")
    func suppressionReasonsNeverExposeRawEnumValues() {
        let reasons: [RecordingSuppressionReason] = [
            .secureInput,
            .passwordField,
            .excludedApplication,
            .excludedWindow,
            .excludedDomain,
            .privateRegion,
            .oversizedArtifact,
            .userDeleted,
            .unknown,
        ]

        for reason in reasons {
            let title = SemanticRecordingReviewIssuePresenter.suppressionTitle(reason)
            let explanation = SemanticRecordingReviewIssuePresenter.suppressionExplanation(reason)
            #expect(!title.isEmpty)
            #expect(!explanation.isEmpty)
            #expect(title != reason.rawValue)
        }
    }

    @Test("Review issue presentation keys live in Common catalog")
    func reviewIssuePresentationKeysLiveInCommonCatalog() throws {
        let url = repositoryRoot()
            .appendingPathComponent("Sources/SparkleRecorder/Common.xcstrings")
        let data = try Data(contentsOf: url)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(rootObject["strings"] as? [String: Any])

        let keys = [
            "This recording bundle uses an unsupported format.",
            "The recording bundle contains duplicate evidence identifiers.",
            "The recording bundle contains a broken evidence reference.",
            "Secure Input",
            "Password field",
            "Excluded app",
            "Excluded window",
            "Excluded domain",
            "Private region",
            "Artifact too large",
            "Deleted by user",
            "Protected context",
            "Keyboard and visual evidence were withheld while Secure Input was active.",
            "Typed content and visual evidence were withheld while a password field was focused.",
            "Visual evidence was withheld because this app is excluded by your privacy settings.",
            "Visual evidence was withheld because this window matches a privacy exclusion.",
            "Visual evidence was withheld because this domain is excluded by your privacy settings.",
            "This region was marked private, so its visual evidence was withheld.",
            "This visual artifact exceeded the configured storage limit and was not retained.",
            "This visual evidence was removed by the user and remains marked as deleted.",
            "This context was protected, so the unavailable evidence is shown explicitly instead of being inferred.",
            "Frame %@",
        ]

        var missing: [String] = []
        for key in keys {
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  localizations["en"] != nil,
                  localizations["zh-Hans"] != nil else {
                missing.append(key)
                continue
            }
        }

        #expect(missing.isEmpty, "Missing Common review presentation translations: \(missing)")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

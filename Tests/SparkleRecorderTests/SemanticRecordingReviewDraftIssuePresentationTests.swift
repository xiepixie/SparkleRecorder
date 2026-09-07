import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Draft Issue Presentation Tests")
struct SemanticRecordingReviewDraftIssuePresentationTests {
    @Test("Review patch errors use actionable user-facing copy")
    func reviewPatchErrorsUseActionableCopy() {
        let error = SemanticRecordingReviewDraftPatchError.missingArtifact("candidate-internal-id")

        let message = SemanticRecordingReviewDraftIssuePresentation.message(for: error)

        #expect(message == "The visual evidence needed for this suggestion is unavailable.")
        #expect(!message.contains("candidate-internal-id"))
        #expect(!message.contains("missingArtifact"))
    }

    @Test("Workflow edit errors reuse the workflow draft presentation seam")
    func workflowEditErrorsReuseDraftPresentation() {
        let error = AutomationWorkflowDraftEditError(
            code: "missingTask",
            message: "Task 'internal-key' was not found.",
            path: "$.workflow.tasks"
        )

        let message = SemanticRecordingReviewDraftIssuePresentation.message(for: error)

        #expect(message == "The selected task is no longer in this draft.")
        #expect(!message.contains("internal-key"))
    }

    @Test("Asset materialization errors do not expose internal paths")
    func assetMaterializationErrorsDoNotExposeInternalPaths() {
        let missing = SemanticRecordingReviewAssetMaterializationError
            .missingSourceArtifact("private/recordings/frame.png")
        let unsafe = SemanticRecordingReviewAssetMaterializationError
            .unsafeDestinationPath("../../outside.png")

        let missingMessage = SemanticRecordingReviewDraftIssuePresentation.message(for: missing)
        let unsafeMessage = SemanticRecordingReviewDraftIssuePresentation.message(for: unsafe)

        #expect(missingMessage == "The source visual evidence file could not be found.")
        #expect(unsafeMessage == "The visual evidence could not be prepared for this draft.")
        #expect(!missingMessage.contains("private/recordings"))
        #expect(!unsafeMessage.contains("outside.png"))
    }

    @Test("Saving a patch uses a stable failure message")
    func savingPatchUsesStableFailureMessage() {
        struct DiskFailure: Error {}

        let message = SemanticRecordingReviewDraftIssuePresentation.saveMessage(for: DiskFailure())

        #expect(message == "The draft patch could not be saved. Check the destination and try again.")
        #expect(!message.contains("DiskFailure"))
    }
}

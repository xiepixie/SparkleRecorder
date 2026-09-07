import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Repeat-Until Body Presentation Tests")
struct SemanticRecordingReviewRepeatUntilBodyPresentationTests {
    @Test("Repeat-Until resolution status owns presentation copy outside Core")
    func repeatUntilResolutionStatusOwnsPresentationCopyOutsideCore() {
        let missing = SemanticRecordingReviewRepeatUntilBodyResolution(status: .noLinkedMacro)
        let ambiguous = SemanticRecordingReviewRepeatUntilBodyResolution(status: .ambiguousLinkedMacros)
        let resolved = SemanticRecordingReviewRepeatUntilBodyResolution(
            status: .resolved,
            bodyTasks: [AutomationWorkflowDraftTask(key: "retry", type: "macro", name: "Retry Checkout")]
        )

        #expect(
            SemanticRecordingReviewRepeatUntilBodyPresentation.message(for: missing) ==
                "Link this semantic recording to a macro before creating a Repeat-Until body."
        )
        #expect(
            SemanticRecordingReviewRepeatUntilBodyPresentation.message(for: ambiguous) ==
                "Multiple macros are linked to this recording. Choose one as the Repeat-Until body."
        )
        #expect(
            SemanticRecordingReviewRepeatUntilBodyPresentation.message(for: resolved) ==
                "Repeat-Until body will replay Retry Checkout."
        )
    }
}

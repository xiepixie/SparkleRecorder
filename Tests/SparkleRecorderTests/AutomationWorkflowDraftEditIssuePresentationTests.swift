import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Workflow Draft Edit Issue Presentation Tests")
struct AutomationWorkflowDraftEditIssuePresentationTests {
    @Test("Draft edit errors use stable user-facing copy")
    func draftEditErrorsUseStableUserFacingCopy() {
        let error = AutomationWorkflowDraftEditError(
            code: "missingTask",
            message: "Task 'removed_task' was not found.",
            path: "$.workflow.tasks"
        )

        let message = AutomationWorkflowDraftEditIssuePresentation.message(for: error)

        #expect(message == "The selected task is no longer in this draft.")
        #expect(!message.contains("removed_task"))
        #expect(!message.contains("$.workflow"))
    }

    @Test("Patch edit errors do not expose patch internals")
    func patchEditErrorsDoNotExposePatchInternals() {
        let unsupported = AutomationWorkflowDraftEditError(
            code: "unsupportedPatchOperation",
            message: "Unsupported patch operation 'mutateEverything'.",
            path: "$.ops[0].op"
        )
        let missingField = AutomationWorkflowDraftEditError(
            code: "missingPatchField",
            message: "Patch operation requires 'visualImage'.",
            path: "$.ops[0].visualImage"
        )

        #expect(
            AutomationWorkflowDraftEditIssuePresentation.message(for: unsupported) ==
                "This draft patch contains an unsupported change."
        )
        #expect(
            AutomationWorkflowDraftEditIssuePresentation.message(for: missingField) ==
                "This draft patch is missing information required for the change."
        )
    }

    @Test("Validation diagnostics are localized at the app presentation seam")
    func validationDiagnosticsAreLocalizedAtAppPresentationSeam() {
        let rawMessage = "Task 'tap' needs macroRef.id or macroRef.name."
        let row = AutomationWorkflowDraftPreviewProjection.IssueRow(
            message: AutomationCLIMessage(
                code: AutomationWorkflowDraftIssueCode.missingMacroRef.rawValue,
                message: rawMessage,
                path: "$.workflow.tasks[0].macroRef",
                taskKey: "tap"
            ),
            severity: .error
        )

        #expect(row.message == rawMessage)
        #expect(AutomationWorkflowDraftIssuePresentation.message(for: row) == "Choose a macro for this task.")
    }

    @Test("Unknown validation diagnostics retain their raw fallback")
    func unknownValidationDiagnosticsRetainRawFallback() {
        #expect(
            AutomationWorkflowDraftIssuePresentation.message(
                code: "futureDiagnostic",
                rawMessage: "Future diagnostic detail."
            ) == "Future diagnostic detail."
        )
    }

    @Test("Unknown edit failures use a safe fallback")
    func unknownEditFailuresUseSafeFallback() {
        struct UnexpectedFailure: Error {}

        let message = AutomationWorkflowDraftEditIssuePresentation.message(for: UnexpectedFailure())

        #expect(message == "The draft could not be updated. Review the edit and try again.")
        #expect(!message.contains("UnexpectedFailure"))
    }
}

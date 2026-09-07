import Testing
@testable import SparkleRecorder

@Suite("Automation Task Run Evidence Action Presentation Tests")
struct AutomationTaskRunEvidenceActionPresentationTests {
    @Test("Successful evidence actions use positive feedback")
    func successFeedback() {
        let report = AutomationTaskRunEvidenceActionPresentation.make(.succeeded(.revealReport))
        let screenshot = AutomationTaskRunEvidenceActionPresentation.make(.succeeded(.openScreenshot))

        #expect(!report.isError)
        #expect(report.systemImage == "folder.badge.gearshape")
        #expect(!screenshot.isError)
        #expect(screenshot.systemImage == "photo.badge.checkmark")
    }

    @Test("Evidence action failures preserve the actionable message")
    func failureFeedback() {
        let presentation = AutomationTaskRunEvidenceActionPresentation.make(
            .failed(.openScreenshot, message: "Screenshot is missing.")
        )

        #expect(presentation.isError)
        #expect(presentation.message == "Screenshot is missing.")
        #expect(presentation.systemImage == "exclamationmark.triangle")
    }
}

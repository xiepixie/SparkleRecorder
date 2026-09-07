import Foundation
import Testing
@testable import SparkleRecorder

@Suite("App Status Feedback Tests")
struct AppStatusFeedbackTests {
    @Test("Feedback tone owns a clear default dismissal policy")
    func toneOwnsDismissPolicy() {
        #expect(AppStatusFeedback(message: "Saved", tone: .success).dismissAfter == 4)
        #expect(AppStatusFeedback(message: "Info", tone: .info).dismissAfter == 5)
        #expect(AppStatusFeedback(message: "Warning", tone: .warning).dismissAfter == 7)
        #expect(AppStatusFeedback(message: "Error", tone: .error).dismissAfter == nil)
        #expect(AppStatusFeedback(message: "Working", tone: .progress).dismissAfter == nil)
    }

    @Test("Explicit dismissal duration overrides the tone default")
    func explicitDurationOverridesDefault() {
        let feedback = AppStatusFeedback(
            message: "Keep this visible briefly",
            tone: .error,
            dismissAfter: 2.5
        )
        #expect(feedback.dismissAfter == 2.5)
    }

    @Test("Repeated copy still creates a new presentation identity")
    func repeatedCopyGetsNewIdentity() {
        let first = AppStatusFeedback(message: "Saved", tone: .success)
        let second = AppStatusFeedback(message: "Saved", tone: .success)
        #expect(first.id != second.id)
    }

    @MainActor
    @Test("App state trims feedback and ignores blank messages")
    func appStateTrimsAndIgnoresBlankFeedback() {
        let state = AppState()
        state.presentStatus("  Changes saved.  ", tone: .success)
        #expect(state.statusFeedback?.message == "Changes saved.")

        state.presentStatus("   \n  ", tone: .error)
        #expect(state.statusFeedback == nil)
    }

    @MainActor
    @Test("Repeating the same app status restarts its presentation lifetime")
    func repeatedAppStatusGetsFreshIdentity() throws {
        let state = AppState()
        state.presentStatus("Changes saved.", tone: .success)
        let firstID = try #require(state.statusFeedback?.id)

        state.presentStatus("Changes saved.", tone: .success)
        let secondID = try #require(state.statusFeedback?.id)

        #expect(firstID != secondID)
        state.dismissStatus(firstID)
        #expect(state.statusFeedback?.id == secondID)
        state.dismissStatus(secondID)
        #expect(state.statusFeedback == nil)
    }
}

import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Workflow Recording Handoff Tests")
struct AutomationWorkflowRecordingHandoffTests {
    @Test("Stale completion check cannot clear a newer recording intent")
    func staleCompletionCannotClearNewIntent() {
        let oldIntentID = UUID()
        let newIntentID = UUID()
        var handoff = AutomationWorkflowRecordingHandoff()

        handoff.begin(
            id: oldIntentID,
            targetWorkflowID: UUID(),
            existingMacroIDs: []
        )
        handoff.recordingStarted()

        handoff.begin(
            id: newIntentID,
            targetWorkflowID: UUID(),
            existingMacroIDs: []
        )
        handoff.recordingStarted()

        let completion = handoff.resolveCompletion(
            expectedIntentID: oldIntentID,
            isRecordingMacro: false,
            currentMacroID: nil,
            macros: [],
            clearIfMissing: true
        )

        #expect(completion == .unchanged)
        #expect(handoff.intent?.id == newIntentID)
        #expect(handoff.isRecordingIntoWorkflow)
    }

    @Test("Current newly recorded macro wins over newer fallback candidates")
    func currentMacroWins() {
        let oldMacro = macro(name: "Existing", createdAt: 1)
        let currentMacro = macro(name: "Current", createdAt: 2)
        let newerFallback = macro(name: "Fallback", createdAt: 3)
        let workflowID = UUID()
        let intentID = UUID()
        var handoff = AutomationWorkflowRecordingHandoff()
        handoff.begin(
            id: intentID,
            targetWorkflowID: workflowID,
            existingMacroIDs: [oldMacro.id]
        )
        handoff.recordingStarted()

        let completion = handoff.resolveCompletion(
            expectedIntentID: intentID,
            isRecordingMacro: false,
            currentMacroID: currentMacro.id,
            macros: [oldMacro, currentMacro, newerFallback],
            clearIfMissing: true
        )

        #expect(completion == .recorded(targetWorkflowID: workflowID, macroID: currentMacro.id))
        #expect(handoff.intent == nil)
    }

    @Test("Newest unseen macro is used when current macro is unavailable")
    func newestUnseenMacroIsFallback() {
        let oldMacro = macro(name: "Existing", createdAt: 1)
        let olderNew = macro(name: "Older new", createdAt: 2)
        let newestNew = macro(name: "Newest new", createdAt: 4)
        let intentID = UUID()
        var handoff = AutomationWorkflowRecordingHandoff()
        handoff.begin(
            id: intentID,
            targetWorkflowID: nil,
            existingMacroIDs: [oldMacro.id]
        )
        handoff.recordingStarted()

        let completion = handoff.resolveCompletion(
            expectedIntentID: intentID,
            isRecordingMacro: false,
            currentMacroID: oldMacro.id,
            macros: [newestNew, oldMacro, olderNew],
            clearIfMissing: true
        )

        #expect(completion == .recorded(targetWorkflowID: nil, macroID: newestNew.id))
    }

    @Test("Missing macro can wait for library publication before clearing")
    func missingMacroWaitsBeforeClearing() {
        let intentID = UUID()
        var handoff = AutomationWorkflowRecordingHandoff()
        handoff.begin(
            id: intentID,
            targetWorkflowID: UUID(),
            existingMacroIDs: []
        )
        handoff.recordingStarted()

        let waiting = handoff.resolveCompletion(
            expectedIntentID: intentID,
            isRecordingMacro: false,
            currentMacroID: nil,
            macros: [],
            clearIfMissing: false
        )
        #expect(waiting == .unchanged)
        #expect(handoff.intent?.id == intentID)

        let cleared = handoff.resolveCompletion(
            expectedIntentID: intentID,
            isRecordingMacro: false,
            currentMacroID: nil,
            macros: [],
            clearIfMissing: true
        )
        #expect(cleared == .cleared)
        #expect(handoff.intent == nil)
    }

    @Test("Flow ending before recording starts clears the pending intent")
    func flowEndBeforeStartClearsIntent() {
        var handoff = AutomationWorkflowRecordingHandoff()
        handoff.begin(
            targetWorkflowID: UUID(),
            existingMacroIDs: []
        )

        #expect(handoff.recordingFlowEnded() == nil)
        #expect(handoff.intent == nil)
        #expect(!handoff.isRecordingIntoWorkflow)
    }

    private func macro(name: String, createdAt: TimeInterval) -> SavedMacro {
        SavedMacro(
            name: name,
            events: [],
            createdAt: Date(timeIntervalSince1970: createdAt),
            modifiedAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

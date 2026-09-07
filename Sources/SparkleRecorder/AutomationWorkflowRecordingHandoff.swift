import Foundation
import SparkleRecorderCore

struct AutomationWorkflowRecordingHandoff: Equatable, Sendable {
    struct Intent: Equatable, Sendable, Identifiable {
        let id: UUID
        var targetWorkflowID: UUID?
        var existingMacroIDs: Set<UUID>
        var didStartRecording: Bool

        init(
            id: UUID = UUID(),
            targetWorkflowID: UUID?,
            existingMacroIDs: Set<UUID>,
            didStartRecording: Bool = false
        ) {
            self.id = id
            self.targetWorkflowID = targetWorkflowID
            self.existingMacroIDs = existingMacroIDs
            self.didStartRecording = didStartRecording
        }
    }

    enum Completion: Equatable, Sendable {
        case unchanged
        case cleared
        case recorded(targetWorkflowID: UUID?, macroID: UUID)
    }

    private(set) var intent: Intent?

    var isRecordingIntoWorkflow: Bool {
        intent?.didStartRecording == true
    }

    @discardableResult
    mutating func begin(
        id: UUID = UUID(),
        targetWorkflowID: UUID?,
        existingMacroIDs: Set<UUID>
    ) -> UUID {
        intent = Intent(
            id: id,
            targetWorkflowID: targetWorkflowID,
            existingMacroIDs: existingMacroIDs
        )
        return id
    }

    mutating func recordingStarted() {
        guard var intent else {
            return
        }
        intent.didStartRecording = true
        self.intent = intent
    }

    func completionCheckID() -> UUID? {
        guard intent?.didStartRecording == true else {
            return nil
        }
        return intent?.id
    }

    mutating func recordingFlowEnded() -> UUID? {
        guard let intent else {
            return nil
        }
        guard intent.didStartRecording else {
            self.intent = nil
            return nil
        }
        return intent.id
    }

    mutating func resolveCompletion(
        expectedIntentID: UUID,
        isRecordingMacro: Bool,
        currentMacroID: UUID?,
        macros: [SavedMacro],
        clearIfMissing: Bool
    ) -> Completion {
        guard let intent,
              intent.id == expectedIntentID,
              intent.didStartRecording,
              !isRecordingMacro else {
            return .unchanged
        }

        let currentRecordedMacro = currentMacroID.flatMap { macroID in
            macros.first { macro in
                macro.id == macroID && !intent.existingMacroIDs.contains(macro.id)
            }
        }
        let newestRecordedMacro = macros
            .filter { !intent.existingMacroIDs.contains($0.id) }
            .max { $0.createdAt < $1.createdAt }

        guard let recordedMacro = currentRecordedMacro ?? newestRecordedMacro else {
            if clearIfMissing {
                self.intent = nil
                return .cleared
            }
            return .unchanged
        }

        self.intent = nil
        return .recorded(
            targetWorkflowID: intent.targetWorkflowID,
            macroID: recordedMacro.id
        )
    }
}

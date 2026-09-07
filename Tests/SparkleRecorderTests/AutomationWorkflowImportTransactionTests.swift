import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

private enum AutomationWorkflowImportTransactionTestError: Error, LocalizedError {
    case importFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .importFailed: "Synthetic import failure"
        case .rollbackFailed: "Synthetic rollback failure"
        }
    }
}

@Suite("Automation Workflow Import Transaction Tests")
struct AutomationWorkflowImportTransactionTests {
    @MainActor
    @Test("Partial package imports roll back newly added and replaced workflows")
    func rollsBackPartialImport() async {
        let existing = AutomationWorkflow(name: "Original")
        var replacement = existing
        replacement.name = "Replacement"
        let added = AutomationWorkflow(name: "Added")
        let failing = AutomationWorkflow(name: "Failing")
        var stored = [existing.id: existing]

        do {
            try await AutomationWorkflowImportTransaction.commit(
                [replacement, added, failing],
                replacing: [existing]
            ) { action in
                switch action {
                case .upsertWorkflow(let workflow, _):
                    if workflow.id == failing.id {
                        throw AutomationWorkflowImportTransactionTestError.importFailed
                    }
                    stored[workflow.id] = workflow
                case .deleteWorkflow(let workflowID, _):
                    stored.removeValue(forKey: workflowID)
                default:
                    break
                }
            }
            Issue.record("Expected the import transaction to fail")
        } catch let failure as AutomationWorkflowImportTransactionFailure {
            #expect(failure.rollbackError == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(stored == [existing.id: existing])
    }

    @MainActor
    @Test("Rollback failures are reported as partial-state risk")
    func reportsRollbackFailure() async {
        let added = AutomationWorkflow(name: "Added")
        let failing = AutomationWorkflow(name: "Failing")
        var deleteAttempts = 0

        do {
            try await AutomationWorkflowImportTransaction.commit(
                [added, failing],
                replacing: []
            ) { action in
                switch action {
                case .upsertWorkflow(let workflow, _):
                    if workflow.id == failing.id {
                        throw AutomationWorkflowImportTransactionTestError.importFailed
                    }
                case .deleteWorkflow:
                    deleteAttempts += 1
                    throw AutomationWorkflowImportTransactionTestError.rollbackFailed
                default:
                    break
                }
            }
            Issue.record("Expected the import transaction to fail")
        } catch let failure as AutomationWorkflowImportTransactionFailure {
            #expect(failure.rollbackError != nil)
            #expect(failure.localizedDescription.contains("Synthetic rollback failure"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(deleteAttempts == 1)
    }
}

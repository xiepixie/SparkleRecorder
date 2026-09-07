import Foundation
import SparkleRecorderCore

struct AutomationWorkflowImportTransactionFailure: LocalizedError {
    var importError: Error
    var rollbackError: Error?

    var errorDescription: String? {
        if let rollbackError {
            return String(
                format: String(localized: "Workflow import failed, and some imported changes could not be rolled back: %@", table: "Automation"),
                rollbackError.localizedDescription
            )
        }
        return String(
            format: String(localized: "Workflow import failed and was rolled back: %@", table: "Automation"),
            importError.localizedDescription
        )
    }
}

@MainActor
enum AutomationWorkflowImportTransaction {
    static func commit(
        _ workflows: [AutomationWorkflow],
        replacing existingWorkflows: [AutomationWorkflow],
        perform: @MainActor (AutomationAction) async throws -> Void,
        at date: Date = Date()
    ) async throws {
        let existingByID = Dictionary(uniqueKeysWithValues: existingWorkflows.map { ($0.id, $0) })
        var committed: [AutomationWorkflow] = []

        do {
            for workflow in workflows {
                try await perform(.upsertWorkflow(workflow, at: date))
                committed.append(workflow)
            }
        } catch {
            let importError = error
            var firstRollbackError: Error?

            for workflow in committed.reversed() {
                do {
                    if let previous = existingByID[workflow.id] {
                        try await perform(.upsertWorkflow(previous, at: date))
                    } else {
                        try await perform(.deleteWorkflow(workflowID: workflow.id, at: date))
                    }
                } catch {
                    if firstRollbackError == nil {
                        firstRollbackError = error
                    }
                }
            }

            throw AutomationWorkflowImportTransactionFailure(
                importError: importError,
                rollbackError: firstRollbackError
            )
        }
    }
}

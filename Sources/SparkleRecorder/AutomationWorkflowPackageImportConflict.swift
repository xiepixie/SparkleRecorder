import Foundation
import SparkleRecorderCore

struct AutomationWorkflowPackageImportItem: Equatable {
    var workflow: AutomationWorkflow
    var packageDirectoryURL: URL
}

struct AutomationWorkflowPackageImportConflictPlan: Equatable {
    let currentWorkflowIDs: Set<UUID>
    let duplicateImportedIDs: Set<UUID>
    let missingMacroIDs: [UUID]

    var requiresResolution: Bool {
        !duplicateImportedIDs.isEmpty
            || !currentWorkflowIDs.isDisjoint(with: importedWorkflowIDs)
    }

    private let importedWorkflowIDs: Set<UUID>

    static func make(
        importItems: [AutomationWorkflowPackageImportItem],
        currentWorkflows: [AutomationWorkflow],
        availableMacroIDs: Set<UUID>
    ) -> AutomationWorkflowPackageImportConflictPlan {
        let importedIDs = importItems.map(\.workflow.id)
        let referencedMacroIDs = importItems.flatMap { item in
            item.workflow.tasks.compactMap { task -> UUID? in
                guard case .macro(let macroID) = task.kind else {
                    return nil
                }
                return macroID
            }
        }
        return AutomationWorkflowPackageImportConflictPlan(
            currentWorkflowIDs: Set(currentWorkflows.map(\.id)),
            duplicateImportedIDs: duplicateValues(importedIDs),
            missingMacroIDs: Set(referencedMacroIDs)
                .subtracting(availableMacroIDs)
                .sorted { $0.uuidString < $1.uuidString },
            importedWorkflowIDs: Set(importedIDs)
        )
    }

    func addingCopies(
        _ importItems: [AutomationWorkflowPackageImportItem],
        now: Date,
        makeID: () -> UUID = UUID.init
    ) -> [AutomationWorkflowPackageImportItem] {
        var seenIDs = currentWorkflowIDs
        return importItems.map { item in
            var workflow = item.workflow
            guard seenIDs.contains(workflow.id) else {
                seenIDs.insert(workflow.id)
                return item
            }

            workflow.id = makeID()
            workflow.name = String(
                format: String(localized: "%@ Copy", table: "Common"),
                workflow.name
            )
            workflow.createdAt = now
            workflow.modifiedAt = now
            seenIDs.insert(workflow.id)
            return AutomationWorkflowPackageImportItem(
                workflow: workflow,
                packageDirectoryURL: item.packageDirectoryURL
            )
        }
    }

    private static func duplicateValues<T: Hashable>(_ values: [T]) -> Set<T> {
        var seen: Set<T> = []
        var duplicates: Set<T> = []
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return duplicates
    }
}

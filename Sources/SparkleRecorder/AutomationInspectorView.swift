import SwiftUI
import SparkleRecorderCore

struct AutomationInspectorView: View {
    let workflow: AutomationWorkflow?
    let selection: AutomationAuthoringSelection
    let pendingDependencySourceID: UUID?
    let macros: [SavedMacro]
    let runs: [AutomationTaskRun]
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAddConditionTask: (AutomationConditionKind) -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: (AutomationWorkflow) -> Void
    let onShareWorkflowPackage: (AutomationWorkflow) -> Void
    let onAction: (AutomationAction) -> Void
    let onCancelLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AutomationSectionHeader(title: NSLocalizedString("INSPECTOR", comment: ""))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if let workflow {
                ScrollView {
                    switch selection {
                    case .workflow:
                        AutomationWorkflowInspectorView(
                            workflow: workflow,
                            pendingDependencySourceID: pendingDependencySourceID,
                            onAddConditionTask: onAddConditionTask,
                            onSelectTask: onSelectTask,
                            onSelectDependency: onSelectDependency,
                            onCancelLink: onCancelLink,
                            onImportWorkflowPackage: onImportWorkflowPackage,
                            onExportWorkflowPackage: onExportWorkflowPackage,
                            onShareWorkflowPackage: onShareWorkflowPackage,
                            onAction: onAction
                        )
                    case .task(let taskID):
                        if let task = workflow.task(id: taskID) {
                            AutomationTaskInspectorView(
                                workflow: workflow,
                                task: task,
                                macros: macros,
                                taskRuns: taskRuns(for: task.id),
                                activeRunID: activeRunID(for: task.id),
                                onAction: onAction
                            )
                        } else {
                            AutomationWorkflowInspectorView(
                                workflow: workflow,
                                pendingDependencySourceID: pendingDependencySourceID,
                                onAddConditionTask: onAddConditionTask,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onCancelLink: onCancelLink,
                                onImportWorkflowPackage: onImportWorkflowPackage,
                                onExportWorkflowPackage: onExportWorkflowPackage,
                                onShareWorkflowPackage: onShareWorkflowPackage,
                                onAction: onAction
                            )
                        }
                    case .dependency(let dependencyID):
                        if let dependency = workflow.dependencies.first(where: { $0.id == dependencyID }) {
                            AutomationDependencyInspectorView(
                                workflow: workflow,
                                dependency: dependency,
                                onSelectTask: onSelectTask,
                                onAction: onAction
                            )
                        } else {
                            AutomationWorkflowInspectorView(
                                workflow: workflow,
                                pendingDependencySourceID: pendingDependencySourceID,
                                onAddConditionTask: onAddConditionTask,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onCancelLink: onCancelLink,
                                onImportWorkflowPackage: onImportWorkflowPackage,
                                onExportWorkflowPackage: onExportWorkflowPackage,
                                onShareWorkflowPackage: onShareWorkflowPackage,
                                onAction: onAction
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                AutomationEmptyState(
                    systemImage: "slider.horizontal.3",
                    title: NSLocalizedString("No workflow selected", comment: ""),
                    subtitle: NSLocalizedString("Create a workflow to edit automation settings.", comment: "")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func activeRunID(for taskID: UUID) -> UUID? {
        guard let workflowID = workflow?.id else {
            return nil
        }

        return runs
            .filter { $0.workflowID == workflowID && $0.taskID == taskID && !$0.isTerminal }
            .max { latestActivityDate(for: $0) < latestActivityDate(for: $1) }?
            .id
    }

    private func taskRuns(for taskID: UUID) -> [AutomationTaskRun] {
        guard let workflowID = workflow?.id else {
            return []
        }

        return runs
            .filter { $0.workflowID == workflowID && $0.taskID == taskID }
            .sorted { latestActivityDate(for: $0) > latestActivityDate(for: $1) }
    }

    private func latestActivityDate(for run: AutomationTaskRun) -> Date {
        run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }
}

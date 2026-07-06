import SwiftUI
import SparkleRecorderCore

struct AutomationInspectorView: View {
    let workflow: AutomationWorkflow?
    let workflowProjection: AutomationWorkflowProjection?
    let selection: AutomationAuthoringSelection
    let selectedTaskPosition: AutomationGraphPoint?
    let selectedTaskProjection: AutomationTaskNodeProjection?
    let pendingDependencySourceID: UUID?
    let macros: [SavedMacro]
    let runs: [AutomationTaskRun]
    var initialSelectedRunID: UUID?
    var taskListPreviewState: AutomationWorkflowTaskListPreviewState?
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAddConditionTask: (AutomationConditionKind) -> Void
    let onInsertMacroTask: (UUID, Int) -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: (AutomationWorkflow) -> Void
    let onExportWorkflowDraft: (AutomationWorkflow) -> Void
    let onShareWorkflowPackage: (AutomationWorkflow) -> Void
    let onDeleteWorkflow: (UUID) -> Void
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
                            status: workflowProjection?.status ?? .scheduled,
                            statusDetail: workflowProjection?.statusDetail ?? NSLocalizedString("No run has started yet", comment: ""),
                            nextScheduledOccurrence: workflowProjection?.nextScheduledOccurrence,
                            nextScheduledTaskName: nextScheduledTaskName,
                            workflowProjection: workflowProjection,
                            pendingDependencySourceID: pendingDependencySourceID,
                            taskListPreviewState: taskListPreviewState,
                            onAddConditionTask: onAddConditionTask,
                            onInsertMacroTask: onInsertMacroTask,
                            onSelectTask: onSelectTask,
                            onSelectDependency: onSelectDependency,
                            onCancelLink: onCancelLink,
                            onImportWorkflowPackage: onImportWorkflowPackage,
                            onExportWorkflowPackage: onExportWorkflowPackage,
                            onExportWorkflowDraft: onExportWorkflowDraft,
                            onShareWorkflowPackage: onShareWorkflowPackage,
                            onDeleteWorkflow: onDeleteWorkflow,
                            onAction: onAction
                        )
                    case .task(let taskID):
                        if let task = workflow.task(id: taskID) {
                            AutomationTaskInspectorView(
                                workflow: workflow,
                                task: task,
                                dependencyEdges: workflowProjection?.edges ?? [],
                                graphPosition: selectedTaskPosition,
                                taskProjection: selectedTaskProjection,
                                macros: macros,
                                taskRuns: taskRuns(for: task.id),
                                activeRunID: activeRunID(for: task.id),
                                initialSelectedRunID: initialSelectedRunID,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onAction: onAction
                            )
                        } else {
                            AutomationWorkflowInspectorView(
                                workflow: workflow,
                                status: workflowProjection?.status ?? .scheduled,
                                statusDetail: workflowProjection?.statusDetail ?? NSLocalizedString("No run has started yet", comment: ""),
                                nextScheduledOccurrence: workflowProjection?.nextScheduledOccurrence,
                                nextScheduledTaskName: nextScheduledTaskName,
                                workflowProjection: workflowProjection,
                                pendingDependencySourceID: pendingDependencySourceID,
                                taskListPreviewState: taskListPreviewState,
                                onAddConditionTask: onAddConditionTask,
                                onInsertMacroTask: onInsertMacroTask,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onCancelLink: onCancelLink,
                                onImportWorkflowPackage: onImportWorkflowPackage,
                                onExportWorkflowPackage: onExportWorkflowPackage,
                                onExportWorkflowDraft: onExportWorkflowDraft,
                                onShareWorkflowPackage: onShareWorkflowPackage,
                                onDeleteWorkflow: onDeleteWorkflow,
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
                                status: workflowProjection?.status ?? .scheduled,
                                statusDetail: workflowProjection?.statusDetail ?? NSLocalizedString("No run has started yet", comment: ""),
                                nextScheduledOccurrence: workflowProjection?.nextScheduledOccurrence,
                                nextScheduledTaskName: nextScheduledTaskName,
                                workflowProjection: workflowProjection,
                                pendingDependencySourceID: pendingDependencySourceID,
                                taskListPreviewState: taskListPreviewState,
                                onAddConditionTask: onAddConditionTask,
                                onInsertMacroTask: onInsertMacroTask,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onCancelLink: onCancelLink,
                                onImportWorkflowPackage: onImportWorkflowPackage,
                                onExportWorkflowPackage: onExportWorkflowPackage,
                                onExportWorkflowDraft: onExportWorkflowDraft,
                                onShareWorkflowPackage: onShareWorkflowPackage,
                                onDeleteWorkflow: onDeleteWorkflow,
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

    private var nextScheduledTaskName: String? {
        guard let taskID = workflowProjection?.nextScheduledTaskID else {
            return nil
        }
        return workflow?.task(id: taskID)?.name
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

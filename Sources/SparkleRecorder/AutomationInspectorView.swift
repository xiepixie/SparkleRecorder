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
    let onImportWorkflowFromDraftPreview: (AutomationWorkflow, URL?) -> Void
    let onAction: (AutomationAction) -> Void
    let onCancelLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AutomationSectionHeader(title: NSLocalizedString("INSPECTOR", comment: ""))
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if let workflow {
                if let pendingDependencySourceID,
                   let source = workflow.task(id: pendingDependencySourceID) {
                    HStack(spacing: 8) {
                        Label(source.name, systemImage: "link")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Cancel", systemImage: "xmark", action: onCancelLink)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(width: 24, height: 24)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.sigAmber.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Brand.sigAmber.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 12)
                }

                ScrollView {
                    switch selection {
                    case .workflow:
                        AutomationWorkflowInspectorSummaryView(
                            workflow: workflow,
                            projection: workflowProjection,
                            nextScheduledTaskName: nextScheduledTaskName
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
                                onImportWorkflowFromDraftPreview: onImportWorkflowFromDraftPreview,
                                onSelectTask: onSelectTask,
                                onSelectDependency: onSelectDependency,
                                onAction: onAction
                            )
                        } else {
                            AutomationEmptyState(
                                systemImage: "cursorarrow.rays",
                                title: NSLocalizedString("No Selection", comment: ""),
                                subtitle: NSLocalizedString("Select a task or dependency to inspect its properties. Use the Workflow tab for workflow configurations.", comment: "")
                            )
                            .padding(.top, 40)
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
                            AutomationEmptyState(
                                systemImage: "cursorarrow.rays",
                                title: NSLocalizedString("No Selection", comment: ""),
                                subtitle: NSLocalizedString("Select a task or dependency to inspect its properties. Use the Workflow tab for workflow configurations.", comment: "")
                            )
                            .padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                AutomationEmptyState(
                    systemImage: "slider.horizontal.3",
                    title: NSLocalizedString("No workflow selected", comment: ""),
                    subtitle: NSLocalizedString("Create a workflow to edit workflow details.", comment: "")
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

private struct AutomationWorkflowInspectorSummaryView: View {
    let workflow: AutomationWorkflow
    let projection: AutomationWorkflowProjection?
    let nextScheduledTaskName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(workflow.name)
                        .font(.headline)
                        .lineLimit(2)
                }

                if let projection {
                    Label(projection.statusDetail, systemImage: projection.status.systemImage)
                        .font(.caption)
                        .foregroundStyle(projection.status.tint)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AutomationWorkflowInspectorSummaryRow(
                    title: NSLocalizedString("Tasks", comment: ""),
                    value: "\(projection?.nodes.count ?? workflow.tasks.count)",
                    systemImage: "circle.grid.cross"
                )

                AutomationWorkflowInspectorSummaryRow(
                    title: NSLocalizedString("Links", comment: ""),
                    value: "\(projection?.edges.count ?? workflow.dependencies.count)",
                    systemImage: "arrow.triangle.branch"
                )

                if let nextScheduledOccurrence = projection?.nextScheduledOccurrence {
                    AutomationWorkflowInspectorSummaryRow(
                        title: NSLocalizedString("Next", comment: ""),
                        value: nextScheduledOccurrence.formatted(date: .omitted, time: .shortened),
                        detail: nextScheduledTaskName,
                        systemImage: "clock"
                    )
                }

                AutomationWorkflowInspectorSummaryRow(
                    title: NSLocalizedString("Modified", comment: ""),
                    value: workflow.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionSurface(cornerRadius: 10)
    }
}

private struct AutomationWorkflowInspectorSummaryRow: View {
    let title: String
    let value: String
    var detail: String?
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationMainContentView: View {
    let state: AutomationRunState
    let projection: AutomationOverviewProjection
    let macros: [SavedMacro]
    let refreshState: AutomationRepositoryRefreshState
    let onRefresh: () -> Void
    let onAction: (AutomationAction) -> Void

    @State private var selectedWorkflowID: UUID?
    @State private var selection: AutomationAuthoringSelection = .workflow
    @State private var pendingDependencySourceID: UUID?

    private var selectedWorkflow: AutomationWorkflowProjection? {
        let selectedID = selectedWorkflowID ?? projection.workflows.first?.id
        return projection.workflows.first { $0.id == selectedID }
    }

    private var selectedRawWorkflow: AutomationWorkflow? {
        let selectedID = selectedWorkflowID ?? projection.workflows.first?.id ?? state.workflows.first?.id
        return state.workflows.first { $0.id == selectedID }
    }

    private var selectedTimelineItems: [AutomationResourceTimelineItem] {
        guard let workflowID = selectedWorkflow?.id else {
            return []
        }
        return projection.timelineItems.filter { $0.workflowID == workflowID }
    }

    var body: some View {
        let workflow = selectedWorkflow
        let timelineItems = selectedTimelineItems

        ZStack {
            VisualEffectBackground(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                AutomationOverviewHeader(
                    projection: projection,
                    refreshState: refreshState,
                    onRefresh: onRefresh
                )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().opacity(0.5)

                HStack(spacing: 0) {
                    AutomationWorkflowListView(
                        projection: projection,
                        macros: macros,
                        selectedWorkflowID: $selectedWorkflowID,
                        selectedWorkflow: selectedRawWorkflow,
                        onSelectWorkflow: selectWorkflow,
                        onCreateWorkflow: createWorkflow,
                        onImportWorkflowPackage: importWorkflowPackage,
                        onExportWorkflowPackage: exportWorkflowPackage,
                        onShareWorkflowPackage: shareWorkflowPackage,
                        onAddMacroTask: addMacroTask
                    )
                    .frame(width: 250)

                    Divider().opacity(0.5)

                    if let workflow {
                        AutomationFlowGraphView(
                            workflow: workflow,
                            selectedTaskID: selectedTaskID,
                            selectedDependencyID: selectedDependencyID,
                            pendingDependencySourceID: pendingDependencySourceID,
                            onSelectTask: selectTask,
                            onSelectDependency: selectDependency,
                            onStartDependency: startDependency,
                            onCompleteDependency: completeDependency,
                            onAction: onAction
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider().opacity(0.5)

                        VStack(spacing: 0) {
                            AutomationInspectorView(
                                workflow: selectedRawWorkflow,
                                selection: selection,
                                pendingDependencySourceID: pendingDependencySourceID,
                                macros: macros,
                                runs: state.runs,
                                onSelectTask: selectTask,
                                onSelectDependency: selectDependency,
                                onAddConditionTask: addConditionTask,
                                onImportWorkflowPackage: importWorkflowPackage,
                                onExportWorkflowPackage: exportWorkflowPackage,
                                onShareWorkflowPackage: shareWorkflowPackage,
                                onAction: onAction,
                                onCancelLink: cancelDependency
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Divider().opacity(0.5)

                            AutomationResourceTimelineView(items: timelineItems)
                                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
                        }
                        .frame(width: 340)
                    } else {
                        AutomationEmptyState(
                            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                            title: NSLocalizedString("No workflows", comment: ""),
                            subtitle: NSLocalizedString("Create a workflow to start arranging macros and conditions.", comment: "")
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .onChange(of: projection.workflows.map(\.id)) {
            repairSelection()
        }
    }

    private var selectedTaskID: UUID? {
        if case .task(let taskID) = selection {
            return taskID
        }
        return nil
    }

    private var selectedDependencyID: UUID? {
        if case .dependency(let dependencyID) = selection {
            return dependencyID
        }
        return nil
    }

    private func selectWorkflow(_ workflowID: UUID?) {
        selectedWorkflowID = workflowID
        selection = .workflow
        pendingDependencySourceID = nil
    }

    private func selectTask(_ taskID: UUID) {
        selection = .task(taskID)
    }

    private func selectDependency(_ dependencyID: UUID) {
        selection = .dependency(dependencyID)
        pendingDependencySourceID = nil
    }

    private func createWorkflow() {
        let date = Date()
        let workflow = AutomationWorkflow(
            name: NSLocalizedString("New Workflow", comment: ""),
            createdAt: date,
            modifiedAt: date
        )
        selectedWorkflowID = workflow.id
        selection = .workflow
        pendingDependencySourceID = nil
        onAction(.upsertWorkflow(workflow, at: date))
    }

    private func importWorkflowPackage() {
        AutomationWorkflowPackagePresenter.importWorkflows(
            currentWorkflows: state.workflows,
            availableMacroIDs: Set(macros.map(\.id))
        ) { workflows in
            guard !workflows.isEmpty else {
                return
            }

            let date = Date()
            selectedWorkflowID = workflows.first?.id
            selection = .workflow
            pendingDependencySourceID = nil
            for workflow in workflows {
                onAction(.upsertWorkflow(workflow, at: date))
            }
        }
    }

    private func exportWorkflowPackage(_ workflow: AutomationWorkflow) {
        AutomationWorkflowPackagePresenter.export(workflow: workflow)
    }

    private func exportWorkflowPackage() {
        AutomationWorkflowPackagePresenter.export(
            workflows: state.workflows,
            defaultName: NSLocalizedString("Workflows", comment: "")
        )
    }

    private func shareWorkflowPackage(_ workflow: AutomationWorkflow) {
        AutomationWorkflowPackagePresenter.share(workflow: workflow)
    }

    private func shareWorkflowPackage() {
        AutomationWorkflowPackagePresenter.share(
            workflows: state.workflows,
            defaultName: NSLocalizedString("Workflows", comment: "")
        )
    }

    private func addMacroTask(_ macro: SavedMacro) {
        let date = Date()
        let task = AutomationTask(
            name: macro.name,
            kind: .macro(macroID: macro.id),
            schedule: .manual,
            resourceRequirement: .foregroundInput
        )

        if let workflow = selectedRawWorkflow {
            selection = .task(task.id)
            onAction(.upsertTask(workflowID: workflow.id, task: task, at: date))
        } else {
            let workflow = AutomationWorkflow(
                name: NSLocalizedString("New Workflow", comment: ""),
                tasks: [task],
                createdAt: date,
                modifiedAt: date
            )
            selectedWorkflowID = workflow.id
            selection = .task(task.id)
            onAction(.upsertWorkflow(workflow, at: date))
        }
    }

    private func addConditionTask(_ kind: AutomationConditionKind) {
        guard let workflow = selectedRawWorkflow else {
            return
        }

        let name: String
        switch kind {
        case .manualApproval:
            name = NSLocalizedString("Manual approval", comment: "")
        case .externalSignal(let signalName):
            name = signalName.isEmpty ? NSLocalizedString("External signal", comment: "") : signalName
        case .ocrText:
            name = NSLocalizedString("Text condition", comment: "")
        case .previousOutcome:
            name = NSLocalizedString("Previous outcome", comment: "")
        }

        let task = AutomationTask(
            name: name,
            kind: .condition(AutomationConditionSpec(name: name, kind: kind)),
            schedule: .manual,
            resourceRequirement: .none
        )
        selection = .task(task.id)
        onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
    }

    private func startDependency(from taskID: UUID) {
        pendingDependencySourceID = taskID
        selection = .task(taskID)
    }

    private func completeDependency(to taskID: UUID) {
        guard let workflow = selectedRawWorkflow,
              let sourceID = pendingDependencySourceID,
              sourceID != taskID else {
            pendingDependencySourceID = nil
            return
        }

        if let existing = workflow.dependencies.first(where: { $0.fromTaskID == sourceID && $0.toTaskID == taskID }) {
            selection = .dependency(existing.id)
            pendingDependencySourceID = nil
            return
        }

        let dependency = AutomationDependency(
            fromTaskID: sourceID,
            toTaskID: taskID,
            trigger: .onSuccess
        )
        pendingDependencySourceID = nil
        selection = .dependency(dependency.id)
        onAction(.upsertDependency(workflowID: workflow.id, dependency: dependency, at: Date()))
    }

    private func cancelDependency() {
        pendingDependencySourceID = nil
    }

    private func repairSelection() {
        if selectedWorkflowID == nil {
            selectedWorkflowID = projection.workflows.first?.id
        }
        guard let workflow = selectedRawWorkflow else {
            selection = .workflow
            pendingDependencySourceID = nil
            return
        }

        switch selection {
        case .workflow:
            return
        case .task(let taskID):
            if !workflow.tasks.contains(where: { $0.id == taskID }) {
                selection = .workflow
            }
        case .dependency(let dependencyID):
            if !workflow.dependencies.contains(where: { $0.id == dependencyID }) {
                selection = .workflow
            }
        }
    }
}

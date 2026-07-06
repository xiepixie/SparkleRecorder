import SwiftUI
import SparkleRecorderCore

struct AutomationMainContentView: View {
    let state: AutomationRunState
    let projection: AutomationOverviewProjection
    let macros: [SavedMacro]
    let refreshState: AutomationRepositoryRefreshState
    let initialSelectedRunID: UUID?
    let initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState?
    let initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState?
    let onRefresh: () -> Void
    let onAction: (AutomationAction) -> Void

    @State private var selectedWorkflowID: UUID?
    @State private var selection: AutomationAuthoringSelection = .workflow
    @State private var pendingDependencySourceID: UUID?
    @State private var pendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess
    @State private var draftPreviewState: AutomationWorkflowDraftPreviewState?
    @State private var importNoticeState: AutomationWorkflowImportNoticeState?

    init(
        state: AutomationRunState,
        projection: AutomationOverviewProjection,
        macros: [SavedMacro],
        refreshState: AutomationRepositoryRefreshState,
        initialSelectedWorkflowID: UUID? = nil,
        initialSelection: AutomationAuthoringSelection = .workflow,
        initialSelectedRunID: UUID? = nil,
        initialPendingDependencySourceID: UUID? = nil,
        initialPendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess,
        initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState? = nil,
        initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState? = nil,
        onRefresh: @escaping () -> Void,
        onAction: @escaping (AutomationAction) -> Void
    ) {
        self.state = state
        self.projection = projection
        self.macros = macros
        self.refreshState = refreshState
        self.initialSelectedRunID = initialSelectedRunID
        self.initialFlowGraphLinkPreview = initialFlowGraphLinkPreview
        self.initialTaskListPreviewState = initialTaskListPreviewState
        self.onRefresh = onRefresh
        self.onAction = onAction
        _selectedWorkflowID = State(initialValue: initialSelectedWorkflowID)
        _selection = State(initialValue: initialSelection)
        _pendingDependencySourceID = State(initialValue: initialPendingDependencySourceID)
        _pendingDependencyTrigger = State(initialValue: initialPendingDependencyTrigger)
    }

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

    private var selectedTaskGraphPosition: AutomationGraphPoint? {
        guard case .task(let taskID) = selection else {
            return nil
        }
        return selectedWorkflow?.nodes.first { $0.taskID == taskID }?.position
    }

    private var selectedTaskProjection: AutomationTaskNodeProjection? {
        guard case .task(let taskID) = selection else {
            return nil
        }
        return selectedWorkflow?.nodes.first { $0.taskID == taskID }
    }

    private var selectedNextScheduledTaskName: String? {
        guard let taskID = selectedWorkflow?.nextScheduledTaskID else {
            return nil
        }
        return selectedWorkflow?.nodes.first { $0.taskID == taskID }?.title
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
                    onOpenAIDraftPreview: openAIDraftPreview,
                    onRefresh: onRefresh
                )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().opacity(0.5)

                if let importNoticeState {
                    AutomationWorkflowImportNoticeView(
                        notice: importNoticeState,
                        onUndo: undoWorkflowDraftImport,
                        onRefresh: onRefresh,
                        onDismiss: dismissImportNotice
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider().opacity(0.5)
                }

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
                        VStack(spacing: 0) {
                            AutomationFlowGraphView(
                                workflow: workflow,
                                selectedTaskID: selectedTaskID,
                                selectedDependencyID: selectedDependencyID,
                                pendingDependencySourceID: pendingDependencySourceID,
                                pendingDependencyTrigger: pendingDependencyTrigger,
                                linkPreview: initialFlowGraphLinkPreview,
                                onSelectTask: selectTask,
                                onSelectDependency: selectDependency,
                                onDeleteDependency: deleteDependencyFromGraph,
                                onStartDependency: startDependency,
                                onCompleteDependency: completeDependency,
                                onSetPendingDependencyTrigger: setPendingDependencyTrigger,
                                onCancelDependency: cancelDependency,
                                onMacroDropped: addMacroTask,
                                onAction: onAction
                            )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Divider().opacity(0.5)

                            AutomationResourceTimelineView(
                                items: timelineItems,
                                nextScheduledOccurrence: workflow.nextScheduledOccurrence,
                                nextScheduledTaskName: selectedNextScheduledTaskName
                            )
                                .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 216)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider().opacity(0.5)

                        AutomationInspectorView(
                            workflow: selectedRawWorkflow,
                            workflowProjection: workflow,
                            selection: selection,
                            selectedTaskPosition: selectedTaskGraphPosition,
                            selectedTaskProjection: selectedTaskProjection,
                            pendingDependencySourceID: pendingDependencySourceID,
                            macros: macros,
                            runs: state.runs,
                            initialSelectedRunID: initialSelectedRunID,
                            taskListPreviewState: initialTaskListPreviewState,
                            onSelectTask: selectTask,
                            onSelectDependency: selectDependency,
                            onAddConditionTask: addConditionTask,
                            onInsertMacroTask: insertMacroTask,
                            onImportWorkflowPackage: importWorkflowPackage,
                            onExportWorkflowPackage: exportWorkflowPackage,
                            onExportWorkflowDraft: exportWorkflowDraft,
                            onShareWorkflowPackage: shareWorkflowPackage,
                            onDeleteWorkflow: deleteWorkflow,
                            onAction: onAction,
                            onCancelLink: cancelDependency
                        )
                        .frame(width: 356)
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
            repairImportNotice()
        }
        .sheet(item: $draftPreviewState) { state in
            AutomationWorkflowDraftPreviewSheet(
                state: state,
                existingWorkflowName: existingWorkflowName(for: state.compiledWorkflow),
                onImportWorkflow: importWorkflowFromDraftPreview
            )
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

    private func deleteWorkflow(_ workflowID: UUID) {
        let date = Date()
        if selectedWorkflowID == workflowID {
            selectedWorkflowID = state.workflows.first { $0.id != workflowID }?.id
            selection = .workflow
        }
        if importNoticeState?.workflowID == workflowID {
            importNoticeState = nil
        }
        pendingDependencySourceID = nil
        pendingDependencyTrigger = .onSuccess
        onAction(.deleteWorkflow(workflowID: workflowID, at: date))
    }

    private func exportWorkflowPackage(_ workflow: AutomationWorkflow) {
        AutomationWorkflowPackagePresenter.export(workflow: workflow)
    }

    private func exportWorkflowDraft(_ workflow: AutomationWorkflow) {
        AutomationWorkflowDraftExportPresenter.export(workflow: workflow, macros: macros)
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

    private func openAIDraftPreview() {
        AutomationWorkflowDraftPreviewPresenter.openDraft(macros: macros) { preview in
            draftPreviewState = preview
        }
    }

    private func existingWorkflowName(for workflow: AutomationWorkflow?) -> String? {
        guard let workflow else {
            return nil
        }
        return state.workflows.first { $0.id == workflow.id }?.name
    }

    private func importWorkflowFromDraftPreview(_ workflow: AutomationWorkflow, sourceDirectory: URL?) {
        let date = Date()
        var workflowToImport = workflow
        let existingWorkflow = state.workflows.first { $0.id == workflow.id }
        if let existingWorkflow {
            workflowToImport.createdAt = existingWorkflow.createdAt
        } else {
            workflowToImport.createdAt = date
        }

        selectedWorkflowID = workflowToImport.id
        selection = .workflow
        pendingDependencySourceID = nil
        pendingDependencyTrigger = .onSuccess
        importNoticeState = AutomationWorkflowImportNoticeState(
            workflowID: workflowToImport.id,
            workflowName: workflowToImport.name,
            taskCount: workflowToImport.tasks.count,
            dependencyCount: workflowToImport.dependencies.count,
            isReplacement: existingWorkflow != nil,
            previousWorkflow: existingWorkflow
        )
        onAction(.upsertWorkflow(workflowToImport, at: date))
        persistVisualAssetPackageRoot(
            for: workflowToImport,
            sourceDirectory: sourceDirectory,
            source: .aiDraftImport,
            associatedAt: date
        )
    }

    private func persistVisualAssetPackageRoot(
        for workflow: AutomationWorkflow,
        sourceDirectory: URL?,
        source: AutomationVisualAssetPackageRootSource,
        associatedAt: Date
    ) {
        let roots: [AutomationVisualAssetPackageRoot]
        if let sourceDirectory {
            roots = AutomationVisualAssetPackageRoot.roots(
                for: [workflow],
                packageDirectoryURL: sourceDirectory,
                source: source,
                associatedAt: associatedAt
            )
        } else {
            roots = []
        }

        let client = AutomationVisualAssetPackageRootClient.fileBacked()
        Task {
            do {
                if roots.isEmpty {
                    try await client.removeRoots(Set([workflow.id]))
                } else {
                    try await client.upsertRoots(roots)
                }
            } catch {
                NSLog("SparkleRecorder: Failed to persist workflow visual asset package root: \(error)")
            }
        }
    }

    private func undoWorkflowDraftImport() {
        guard let notice = importNoticeState else {
            return
        }

        importNoticeState = nil
        let date = Date()
        if let previousWorkflow = notice.previousWorkflow {
            selectedWorkflowID = previousWorkflow.id
            selection = .workflow
            pendingDependencySourceID = nil
            pendingDependencyTrigger = .onSuccess
            onAction(.upsertWorkflow(previousWorkflow, at: date))
        } else {
            deleteWorkflow(notice.workflowID)
        }
    }

    private func dismissImportNotice() {
        importNoticeState = nil
    }

    private func addMacroTask(_ macro: SavedMacro) {
        addMacroTask(macro, position: nil)
    }

    private func addMacroTask(macroID: UUID, position: AutomationGraphPoint) {
        addMacroTask(macroID: macroID, position: Optional(position))
    }

    private func addMacroTask(macroID: UUID) {
        addMacroTask(macroID: macroID, position: nil)
    }

    private func insertMacroTask(macroID: UUID, at insertionIndex: Int) {
        guard let macro = macros.first(where: { $0.id == macroID }) else {
            return
        }

        let position = selectedRawWorkflow.flatMap {
            graphPositionForListInsertion(in: $0, insertionIndex: insertionIndex)
        }
        addMacroTask(macro, position: position, insertionIndex: insertionIndex)
    }

    private func addMacroTask(macroID: UUID, position: AutomationGraphPoint?) {
        guard let macro = macros.first(where: { $0.id == macroID }) else {
            return
        }
        addMacroTask(macro, position: position)
    }

    private func addMacroTask(_ macro: SavedMacro, position: AutomationGraphPoint?) {
        addMacroTask(macro, position: position, insertionIndex: nil)
    }

    private func addMacroTask(
        _ macro: SavedMacro,
        position: AutomationGraphPoint?,
        insertionIndex: Int?
    ) {
        let date = Date()
        let task = AutomationTask(
            name: macro.name,
            kind: .macro(macroID: macro.id),
            schedule: .manual,
            resourceRequirement: .foregroundInput,
            graphPosition: position
        )

        if let workflow = selectedRawWorkflow {
            selection = .task(task.id)
            if let insertionIndex {
                var updatedWorkflow = workflow
                let index = min(max(0, insertionIndex), updatedWorkflow.tasks.count)
                updatedWorkflow.tasks.insert(task, at: index)
                onAction(.upsertWorkflow(updatedWorkflow, at: date))
            } else {
                onAction(.upsertTask(workflowID: workflow.id, task: task, at: date))
            }
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

    private func graphPositionForListInsertion(
        in workflow: AutomationWorkflow,
        insertionIndex: Int
    ) -> AutomationGraphPoint? {
        guard let projection = selectedWorkflow, projection.id == workflow.id else {
            return nil
        }

        let index = min(max(0, insertionIndex), workflow.tasks.count)
        let nodesByTaskID = Dictionary(uniqueKeysWithValues: projection.nodes.map { ($0.taskID, $0) })
        let gap = projection.nodeSize.height + 48

        if index > 0,
           let previousNode = nodesByTaskID[workflow.tasks[index - 1].id] {
            return AutomationGraphPoint(
                x: previousNode.position.x,
                y: previousNode.position.y + gap
            )
        }

        if index < workflow.tasks.count,
           let nextNode = nodesByTaskID[workflow.tasks[index].id] {
            return AutomationGraphPoint(
                x: nextNode.position.x,
                y: max(0, nextNode.position.y - gap)
            )
        }

        return nil
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
        case .visual(let condition):
            name = visualConditionName(for: condition)
        case .previousOutcome:
            name = NSLocalizedString("Previous outcome", comment: "")
        }

        let task = AutomationTask(
            name: name,
            kind: .condition(AutomationConditionSpec(name: name, kind: kind)),
            schedule: .manual,
            resourceRequirement: conditionTaskResourceRequirement(for: kind)
        )
        selection = .task(task.id)
        onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
    }

    private func conditionTaskResourceRequirement(for kind: AutomationConditionKind) -> AutomationResourceRequirement {
        switch kind {
        case .ocrText, .visual:
            return .backgroundReadOnly
        case .manualApproval, .externalSignal, .previousOutcome:
            return .none
        }
    }

    private func visualConditionName(for condition: AutomationVisualCondition) -> String {
        switch condition.type {
        case .regionChanged:
            return NSLocalizedString("Region changed", comment: "")
        case .imageAppeared:
            return NSLocalizedString("Image appeared", comment: "")
        case .imageDisappeared:
            return NSLocalizedString("Image disappeared", comment: "")
        case .pixelMatched:
            return NSLocalizedString("Pixel matched", comment: "")
        }
    }

    private func startDependency(from taskID: UUID) {
        pendingDependencySourceID = taskID
        pendingDependencyTrigger = .onSuccess
        selection = .task(taskID)
    }

    private func setPendingDependencyTrigger(_ trigger: AutomationDependencyTriggerDraft) {
        pendingDependencyTrigger = trigger
    }

    private func completeDependency(to taskID: UUID) {
        guard let workflow = selectedRawWorkflow,
              let sourceID = pendingDependencySourceID,
              sourceID != taskID else {
            pendingDependencySourceID = nil
            pendingDependencyTrigger = .onSuccess
            return
        }

        if let existing = workflow.dependencies.first(where: { $0.fromTaskID == sourceID && $0.toTaskID == taskID }) {
            selection = .dependency(existing.id)
            pendingDependencySourceID = nil
            pendingDependencyTrigger = .onSuccess
            return
        }

        let dependency = AutomationDependency(
            fromTaskID: sourceID,
            toTaskID: taskID,
            trigger: pendingDependencyTrigger.trigger
        )
        pendingDependencySourceID = nil
        pendingDependencyTrigger = .onSuccess
        selection = .dependency(dependency.id)
        onAction(.upsertDependency(workflowID: workflow.id, dependency: dependency, at: Date()))
    }

    private func cancelDependency() {
        pendingDependencySourceID = nil
        pendingDependencyTrigger = .onSuccess
    }

    private func deleteDependencyFromGraph(_ dependencyID: UUID) {
        guard let workflow = selectedRawWorkflow else {
            return
        }
        pendingDependencySourceID = nil
        pendingDependencyTrigger = .onSuccess
        if selectedDependencyID == dependencyID {
            selection = .workflow
        }
        onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependencyID, at: Date()))
    }

    private func repairSelection() {
        if selectedWorkflowID == nil {
            selectedWorkflowID = projection.workflows.first?.id
        }
        guard let workflow = selectedRawWorkflow else {
            selection = .workflow
            pendingDependencySourceID = nil
            pendingDependencyTrigger = .onSuccess
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

    private func repairImportNotice() {
        guard let notice = importNoticeState else {
            return
        }
        if !projection.workflows.contains(where: { $0.id == notice.workflowID }) {
            importNoticeState = nil
        }
    }
}

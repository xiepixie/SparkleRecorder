import SwiftUI
import SparkleRecorderCore

enum AutomationCentralTab: String, CaseIterable {
    case editor
    case settings
}

private struct AutomationWorkflowRecordingIntent: Equatable {
    var targetWorkflowID: UUID?
    var existingMacroIDs: Set<UUID>
    var didStartRecording = false
}

private struct AutomationInsertedMacroTask {
    var workflowID: UUID
    var task: AutomationTask
}

private struct AutomationRecordedTaskReviewDraft: Equatable {
    var workflowID: UUID
    var task: AutomationTask
    var macroID: UUID
    var nameDraft: String
    var loopsDraft: Int
}

struct AutomationMainContentView: View {
    let state: AutomationRunState
    let projection: AutomationOverviewProjection
    let macros: [SavedMacro]
    let currentMacroID: UUID?
    let refreshState: AutomationRepositoryRefreshState
    let isRecordingMacro: Bool
    let recordHotkeyName: String?
    let initialSelectedRunID: UUID?
    let initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState?
    let initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState?
    let onRefresh: () -> Void
    let onAction: (AutomationAction) -> Void
    let onRecordMacro: (() -> Void)?
    let onRenameMacro: ((UUID, String) -> Void)?
    let onSetMacroLoops: ((UUID, Int) -> Void)?

    @State private var selectedWorkflowID: UUID?
    @State private var selection: AutomationAuthoringSelection = .workflow
    @State private var pendingDependencySourceID: UUID?
    @State private var pendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess
    @State private var draftPreviewState: AutomationWorkflowDraftPreviewState?
    @State private var importNoticeState: AutomationWorkflowImportNoticeState?
    @State private var selectedInspectorRunID: UUID?
    @State private var workflowRecordingIntent: AutomationWorkflowRecordingIntent?
    @State private var recordedTaskReviewDraft: AutomationRecordedTaskReviewDraft?

    @State private var centralTab: AutomationCentralTab = .editor
    @State private var isLeftSidebarVisible: Bool = true
    @State private var isRightSidebarVisible: Bool = true

    init(
        state: AutomationRunState,
        projection: AutomationOverviewProjection,
        macros: [SavedMacro],
        currentMacroID: UUID? = nil,
        refreshState: AutomationRepositoryRefreshState,
        isRecordingMacro: Bool = false,
        recordHotkeyName: String? = nil,
        initialSelectedWorkflowID: UUID? = nil,
        initialSelection: AutomationAuthoringSelection = .workflow,
        initialSelectedRunID: UUID? = nil,
        initialPendingDependencySourceID: UUID? = nil,
        initialPendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess,
        initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState? = nil,
        initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState? = nil,
        onRefresh: @escaping () -> Void,
        onAction: @escaping (AutomationAction) -> Void,
        onRecordMacro: (() -> Void)? = nil,
        onRenameMacro: ((UUID, String) -> Void)? = nil,
        onSetMacroLoops: ((UUID, Int) -> Void)? = nil
    ) {
        self.state = state
        self.projection = projection
        self.macros = macros
        self.currentMacroID = currentMacroID
        self.refreshState = refreshState
        self.isRecordingMacro = isRecordingMacro
        self.recordHotkeyName = recordHotkeyName
        self.initialSelectedRunID = initialSelectedRunID
        self.initialFlowGraphLinkPreview = initialFlowGraphLinkPreview
        self.initialTaskListPreviewState = initialTaskListPreviewState
        self.onRefresh = onRefresh
        self.onAction = onAction
        self.onRecordMacro = onRecordMacro
        self.onRenameMacro = onRenameMacro
        self.onSetMacroLoops = onSetMacroLoops
        _selectedWorkflowID = State(initialValue: initialSelectedWorkflowID)
        _selection = State(initialValue: initialSelection)
        _pendingDependencySourceID = State(initialValue: initialPendingDependencySourceID)
        _pendingDependencyTrigger = State(initialValue: initialPendingDependencyTrigger)
        _selectedInspectorRunID = State(initialValue: initialSelectedRunID)
    }

    private var selectedWorkflow: AutomationWorkflowProjection? {
        let selectedID = selectedWorkflowID ?? projection.workflows.first?.id
        return projection.workflows.first { $0.id == selectedID }
    }

    private var selectedRawWorkflow: AutomationWorkflow? {
        let selectedID = selectedWorkflowID ?? projection.workflows.first?.id ?? state.workflows.first?.id
        return state.workflows.first { $0.id == selectedID }
    }

    private var pendingDependencyTriggerOptions: [AutomationDependencyTriggerDraft] {
        let sourceTask = pendingDependencySourceID.flatMap { selectedRawWorkflow?.task(id: $0) }
        return AutomationDependencyTriggerDraft.options(for: sourceTask)
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

    private var selectedNextScheduledTaskID: UUID? {
        selectedWorkflow?.nextScheduledTaskID
            ?? selectedRawWorkflow.flatMap { workflowStartTaskID(in: $0) }
    }

    private var selectedNextScheduledTaskName: String? {
        let taskID = selectedNextScheduledTaskID
        guard let taskID else {
            return nil
        }
        return selectedWorkflow?.nodes.first { $0.taskID == taskID }?.title
            ?? selectedRawWorkflow?.task(id: taskID)?.name
    }

    private var selectedNextSchedule: AutomationSchedule? {
        guard let taskID = selectedNextScheduledTaskID else {
            return nil
        }
        return selectedRawWorkflow?.task(id: taskID)?.schedule
    }

    private var recordsMacroIntoWorkflow: Bool {
        onRecordMacro != nil
    }

    private var isRecordingIntoWorkflow: Bool {
        workflowRecordingIntent?.didStartRecording == true
    }

    private var recordMacroAction: (() -> Void)? {
        guard onRecordMacro != nil else {
            return nil
        }
        return recordMacroFromWorkflow
    }

    private var recordedTaskReviewBinding: Binding<AutomationRecordedTaskReviewDraft> {
        Binding {
            recordedTaskReviewDraft ?? AutomationRecordedTaskReviewDraft(
                workflowID: selectedRawWorkflow?.id ?? UUID(),
                task: AutomationTask(
                    name: NSLocalizedString("Recorded task", comment: ""),
                    kind: .delay(0)
                ),
                macroID: currentMacroID ?? UUID(),
                nameDraft: NSLocalizedString("Recorded task", comment: ""),
                loopsDraft: 1
            )
        } set: { draft in
            recordedTaskReviewDraft = draft
        }
    }

    private var canApplyRecordedTaskReview: Bool {
        guard let draft = recordedTaskReviewDraft else {
            return false
        }
        return !draft.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    if isLeftSidebarVisible {
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
                            onAddMacroTask: addMacroTask,
                            onAddConditionTask: addConditionTask,
                            isRecordingMacro: isRecordingMacro,
                            recordsMacroIntoWorkflow: recordsMacroIntoWorkflow,
                            isRecordingIntoWorkflow: isRecordingIntoWorkflow,
                            recordHotkeyName: recordHotkeyName,
                            onRecordMacro: recordMacroAction
                        )
                        .frame(width: 250)
                        .transition(.move(edge: .leading))

                        Divider().opacity(0.5)
                    }

                    if let workflow {
                        VStack(spacing: 0) {
                            HStack {
                                Button(NSLocalizedString("Toggle Left Sidebar", comment: ""), systemImage: "sidebar.left", action: { withAnimation { isLeftSidebarVisible.toggle() } })
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .opacity(isLeftSidebarVisible ? 1.0 : 0.6)

                                Spacer()

                                Picker("", selection: $centralTab) {
                                    Text(NSLocalizedString("Canvas", comment: "")).tag(AutomationCentralTab.editor)
                                    Text(NSLocalizedString("Workflow", comment: "")).tag(AutomationCentralTab.settings)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 250)

                                Spacer()

                                Button(NSLocalizedString("Toggle Right Sidebar", comment: ""), systemImage: "sidebar.right", action: { withAnimation { isRightSidebarVisible.toggle() } })
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                                .opacity(isRightSidebarVisible ? 1.0 : 0.6)

                                Button(NSLocalizedString("Auto Arrange", comment: ""), systemImage: "wand.and.stars") {
                                    autoArrangeTasks()
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8)
                            }
                            .padding(8)
                            .background(Material.bar)

                            Divider().opacity(0.5)

                            if recordedTaskReviewDraft != nil {
                                AutomationRecordedTaskReviewBar(
                                    draft: recordedTaskReviewBinding,
                                    canApply: canApplyRecordedTaskReview,
                                    onApply: applyRecordedTaskReview,
                                    onDismiss: dismissRecordedTaskReview
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.018))

                                Divider().opacity(0.35)
                            }

                            switch centralTab {
                            case .editor:
                                VSplitView {
                                    AutomationFlowGraphView(
                                        workflow: workflow,
                                        selectedTaskID: selectedTaskID,
                                        selectedDependencyID: selectedDependencyID,
                                        pendingDependencySourceID: pendingDependencySourceID,
                                        pendingDependencyTrigger: pendingDependencyTrigger,
                                        pendingDependencyTriggerOptions: pendingDependencyTriggerOptions,
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
                                    .frame(minHeight: 300)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    AutomationResourceTimelineView(
                                        items: timelineItems,
                                        nextScheduledOccurrence: workflow.nextScheduledOccurrence,
                                        nextSchedule: selectedNextSchedule,
                                        nextScheduledTaskName: selectedNextScheduledTaskName,
                                        selectedRunID: selectedInspectorRunID,
                                        onUpdateNextSchedule: updateNextSchedule,
                                        onSelectItem: selectTimelineItem
                                    )
                                    .frame(minHeight: 188, idealHeight: 232, maxHeight: 286)
                                    .frame(maxWidth: .infinity)
                                }
                            case .settings:
                                if let rawWorkflow = selectedRawWorkflow {
                                    ScrollView {
                                        AutomationWorkflowSettingsView(
                                            workflow: rawWorkflow,
                                            status: workflow.status,
                                            statusDetail: workflow.statusDetail,
                                            nextScheduledOccurrence: workflow.nextScheduledOccurrence,
                                            nextScheduledTaskName: selectedNextScheduledTaskName,
                                            workflowProjection: workflow,
                                            taskListPreviewState: initialTaskListPreviewState,
                                            onInsertMacroTask: insertMacroTask,
                                            onSelectTask: selectTask,
                                            onSelectDependency: selectDependency,
                                            onImportWorkflowPackage: importWorkflowPackage,
                                            onExportWorkflowPackage: exportWorkflowPackage,
                                            onExportWorkflowDraft: exportWorkflowDraft,
                                            onShareWorkflowPackage: shareWorkflowPackage,
                                            onDeleteWorkflow: deleteWorkflow,
                                            onAction: onAction
                                        )
                                        .frame(maxWidth: 800)
                                        .padding()
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    AutomationEmptyState(
                                        systemImage: "gearshape",
                                        title: NSLocalizedString("No workflow selected", comment: ""),
                                        subtitle: NSLocalizedString("Create a workflow to view workflow details.", comment: "")
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isRightSidebarVisible {
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
                                initialSelectedRunID: selectedInspectorRunID,
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
                                onImportWorkflowFromDraftPreview: importWorkflowFromDraftPreview,
                                onAction: onAction,
                                onCancelLink: cancelDependency
                            )
                            .frame(width: 356)
                            .transition(.move(edge: .trailing))
                        }
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
        .onChange(of: isRecordingMacro) {
            handleWorkflowRecordingStateChange()
        }
        .onChange(of: macros.map(\.id)) {
            completeWorkflowRecordingIntent(clearIfMissing: false)
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
        selectedInspectorRunID = nil
    }

    private func selectTask(_ taskID: UUID) {
        selection = .task(taskID)
        selectedInspectorRunID = nil
    }

    private func selectDependency(_ dependencyID: UUID) {
        selection = .dependency(dependencyID)
        pendingDependencySourceID = nil
        selectedInspectorRunID = nil
    }

    private func selectTimelineItem(_ item: AutomationResourceTimelineItem) {
        selectedWorkflowID = item.workflowID
        selection = .task(item.taskID)
        pendingDependencySourceID = nil
        selectedInspectorRunID = item.runID
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
        selectedInspectorRunID = nil
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
            selectedInspectorRunID = nil
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
        selectedInspectorRunID = nil
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
        selectedInspectorRunID = nil
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

    private func updateNextSchedule(to edit: AutomationTimelineScheduleEdit) {
        guard let workflow = selectedRawWorkflow,
              let taskID = selectedWorkflow?.nextScheduledTaskID ?? workflowStartTaskID(in: workflow),
              var task = workflow.tasks.first(where: { $0.id == taskID }) else {
            return
        }

        switch edit.mode {
        case .once:
            task.schedule = .once(edit.startAt)
        case .repeating:
            if case .repeating(var rule) = task.schedule {
                rule.anchor = edit.startAt
                rule.interval = edit.repeatInterval
                task.schedule = .repeating(rule)
            } else {
                task.schedule = .repeating(
                    AutomationRepeatRule(
                        anchor: edit.startAt,
                        interval: edit.repeatInterval
                    )
                )
            }
        }

        onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
    }

    private func workflowStartTaskID(in workflow: AutomationWorkflow) -> UUID? {
        let dependentTaskIDs = Set(workflow.dependencies.filter(\.isEnabled).map(\.toTaskID))
        return workflow.tasks.first { !dependentTaskIDs.contains($0.id) }?.id
            ?? workflow.tasks.first?.id
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
            selectedInspectorRunID = nil
            onAction(.upsertWorkflow(previousWorkflow, at: date))
        } else {
            deleteWorkflow(notice.workflowID)
        }
    }

    private func dismissImportNotice() {
        importNoticeState = nil
    }

    private func recordMacroFromWorkflow() {
        guard let onRecordMacro else {
            return
        }

        if !isRecordingMacro {
            recordedTaskReviewDraft = nil
            workflowRecordingIntent = AutomationWorkflowRecordingIntent(
                targetWorkflowID: selectedRawWorkflow?.id ?? selectedWorkflowID,
                existingMacroIDs: Set(macros.map(\.id))
            )
        }
        onRecordMacro()
    }

    private func handleWorkflowRecordingStateChange() {
        if isRecordingMacro {
            guard var intent = workflowRecordingIntent else {
                return
            }
            intent.didStartRecording = true
            workflowRecordingIntent = intent
        } else {
            scheduleWorkflowRecordingCompletionCheck()
        }
    }

    private func scheduleWorkflowRecordingCompletionCheck() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            completeWorkflowRecordingIntent(clearIfMissing: true)
        }
    }

    private func completeWorkflowRecordingIntent(clearIfMissing: Bool) {
        guard let intent = workflowRecordingIntent,
              intent.didStartRecording,
              !isRecordingMacro else {
            return
        }

        let currentRecordedMacro = currentMacroID.flatMap { macroID in
            macros.first { $0.id == macroID && !intent.existingMacroIDs.contains($0.id) }
        }
        let newestRecordedMacro = macros
            .filter { !intent.existingMacroIDs.contains($0.id) }
            .max { $0.createdAt < $1.createdAt }
        let recordedMacro = currentRecordedMacro ?? newestRecordedMacro

        guard let recordedMacro else {
            if clearIfMissing {
                workflowRecordingIntent = nil
            }
            return
        }

        if let workflowID = intent.targetWorkflowID {
            selectedWorkflowID = workflowID
        }
        workflowRecordingIntent = nil
        if let insertion = commitMacroTask(recordedMacro, position: nil, insertionIndex: nil) {
            recordedTaskReviewDraft = AutomationRecordedTaskReviewDraft(
                workflowID: insertion.workflowID,
                task: insertion.task,
                macroID: recordedMacro.id,
                nameDraft: insertion.task.name,
                loopsDraft: recordedMacro.loops
            )
        }
    }

    private func addMacroTask(_ macro: SavedMacro) {
        _ = commitMacroTask(macro, position: nil, insertionIndex: nil)
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
        _ = commitMacroTask(macro, position: position, insertionIndex: insertionIndex)
    }

    private func addMacroTask(macroID: UUID, position: AutomationGraphPoint?) {
        guard let macro = macros.first(where: { $0.id == macroID }) else {
            return
        }
        addMacroTask(macro, position: position)
    }

    private func addMacroTask(_ macro: SavedMacro, position: AutomationGraphPoint?) {
        _ = commitMacroTask(macro, position: position, insertionIndex: nil)
    }

    private func commitMacroTask(
        _ macro: SavedMacro,
        position: AutomationGraphPoint?,
        insertionIndex: Int?
    ) -> AutomationInsertedMacroTask? {
        let date = Date()
        var finalPosition = position
        if finalPosition == nil && insertionIndex == nil {
            finalPosition = defaultGraphPosition()
        }

        let task = AutomationTask(
            name: macro.name,
            kind: .macro(macroID: macro.id),
            schedule: .manual,
            resourceRequirement: .foregroundInput,
            graphPosition: finalPosition
        )

        if let workflow = selectedRawWorkflow {
            selection = .task(task.id)
            selectedInspectorRunID = nil
            if let insertionIndex {
                var updatedWorkflow = workflow
                let index = min(max(0, insertionIndex), updatedWorkflow.tasks.count)
                updatedWorkflow.tasks.insert(task, at: index)
                onAction(.upsertWorkflow(updatedWorkflow, at: date))
            } else {
                onAction(.upsertTask(workflowID: workflow.id, task: task, at: date))
            }
            return AutomationInsertedMacroTask(workflowID: workflow.id, task: task)
        } else {
            let workflow = AutomationWorkflow(
                name: NSLocalizedString("New Workflow", comment: ""),
                tasks: [task],
                createdAt: date,
                modifiedAt: date
            )
            selectedWorkflowID = workflow.id
            selection = .task(task.id)
            selectedInspectorRunID = nil
            onAction(.upsertWorkflow(workflow, at: date))
            return AutomationInsertedMacroTask(workflowID: workflow.id, task: task)
        }
    }

    private func applyRecordedTaskReview() {
        guard let draft = recordedTaskReviewDraft else {
            return
        }

        let trimmedName = draft.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        var updatedTask = state.workflows
            .first { $0.id == draft.workflowID }?
            .task(id: draft.task.id)
            ?? draft.task
        updatedTask.name = trimmedName

        selection = .task(updatedTask.id)
        selectedWorkflowID = draft.workflowID
        selectedInspectorRunID = nil
        onAction(.upsertTask(workflowID: draft.workflowID, task: updatedTask, at: Date()))
        onRenameMacro?(draft.macroID, trimmedName)
        onSetMacroLoops?(draft.macroID, max(0, draft.loopsDraft))
        recordedTaskReviewDraft = nil
    }

    private func dismissRecordedTaskReview() {
        recordedTaskReviewDraft = nil
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
            resourceRequirement: conditionTaskResourceRequirement(for: kind),
            graphPosition: defaultGraphPosition()
        )
        selection = .task(task.id)
        selectedInspectorRunID = nil
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
        let sourceTask = selectedRawWorkflow?.task(id: taskID)
        pendingDependencyTrigger = AutomationDependencyTriggerDraft.options(for: sourceTask).first ?? .onSuccess
        selection = .task(taskID)
    }

    private func setPendingDependencyTrigger(_ trigger: AutomationDependencyTriggerDraft) {
        pendingDependencyTrigger = pendingDependencyTriggerOptions.contains(trigger)
            ? trigger
            : pendingDependencyTriggerOptions.first ?? .onSuccess
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

        let trigger = pendingDependencyTriggerOptions.contains(pendingDependencyTrigger)
            ? pendingDependencyTrigger
            : pendingDependencyTriggerOptions.first ?? .onSuccess

        let dependency = AutomationDependency(
            fromTaskID: sourceID,
            toTaskID: taskID,
            trigger: trigger.trigger
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

    private func autoArrangeTasks() {
        guard var workflow = selectedRawWorkflow else { return }
        let positions = AutomationGraphAutoLayout.computeLayout(
            for: workflow,
            nodeSize: selectedWorkflow?.nodeSize ?? AutomationGraphSize(width: 250, height: 120)
        )
        for i in workflow.tasks.indices {
            if let pos = positions[workflow.tasks[i].id] {
                workflow.tasks[i].graphPosition = pos
            }
        }
        onAction(.upsertWorkflow(workflow, at: Date()))
    }

    private func defaultGraphPosition() -> AutomationGraphPoint? {
        guard let workflow = selectedWorkflow else {
            return nil
        }

        var targetPosition: AutomationGraphPoint?
        let gap = workflow.nodeSize.height + 48

        if let selectedTaskID = selectedTaskID,
           let selectedNode = workflow.nodes.first(where: { $0.taskID == selectedTaskID }) {
            targetPosition = AutomationGraphPoint(
                x: selectedNode.position.x,
                y: selectedNode.position.y + gap
            )
        }

        if targetPosition == nil {
            let maxY = workflow.nodes.map(\.position.y).max()
            if let maxY {
                targetPosition = AutomationGraphPoint(
                    x: 32,
                    y: maxY + gap
                )
            } else {
                targetPosition = AutomationGraphPoint(x: 32, y: 32)
            }
        }

        guard var pos = targetPosition else { return AutomationGraphPoint(x: 32, y: 32) }

        // Box-based collision avoidance
        var collision = true
        while collision {
            collision = false
            for node in workflow.nodes {
                let overlapX = abs(node.position.x - pos.x) < (workflow.nodeSize.width + 16)
                let overlapY = abs(node.position.y - pos.y) < (workflow.nodeSize.height + 16)
                if overlapX && overlapY {
                    pos = AutomationGraphPoint(
                        x: pos.x + workflow.nodeSize.width + 24,
                        y: pos.y
                    )
                    collision = true
                    break
                }
            }
        }

        return pos
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

private struct AutomationRecordedTaskReviewBar: View {
    @Binding var draft: AutomationRecordedTaskReviewDraft
    let canApply: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    private var nameBinding: Binding<String> {
        Binding {
            draft.nameDraft
        } set: { value in
            draft.nameDraft = value
        }
    }

    private var loopsBinding: Binding<Int> {
        Binding {
            max(0, draft.loopsDraft)
        } set: { value in
            draft.loopsDraft = max(0, value)
        }
    }

    private var loopPresets: [Int] {
        var presets = [1, 2, 5, 10, 0]
        if !presets.contains(max(0, draft.loopsDraft)) {
            presets.insert(max(0, draft.loopsDraft), at: 0)
        }
        return presets
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalContent
            verticalContent
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Brand.libraryGreen.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Brand.libraryGreen.opacity(0.18), lineWidth: 0.7)
        )
    }

    private var horizontalContent: some View {
        HStack(spacing: 10) {
            statusLabel
                .frame(width: 168, alignment: .leading)

            nameField
                .frame(minWidth: 180)

            repeatControls
            actionButtons
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                statusLabel
                Spacer(minLength: 0)
                actionButtons
            }

            HStack(spacing: 8) {
                nameField
                repeatControls
            }
        }
    }

    private var statusLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Recorded task", comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(NSLocalizedString("Saved as source macro", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.libraryGreen)
        }
        .labelStyle(.titleAndIcon)
    }

    private var nameField: some View {
        TextField(NSLocalizedString("Task name", comment: ""), text: nameBinding)
            .textFieldStyle(.roundedBorder)
            .onSubmit(onApply)
    }

    private var repeatControls: some View {
        HStack(spacing: 6) {
            Picker(NSLocalizedString("Source repeat", comment: ""), selection: loopsBinding) {
                ForEach(loopPresets, id: \.self) { loops in
                    Text(loopPresetTitle(loops)).tag(loops)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 112)

            Stepper("", value: loopsBinding, in: 0...100)
                .labelsHidden()
                .frame(width: 52)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                onApply()
            } label: {
                Label(NSLocalizedString("Apply", comment: ""), systemImage: "checkmark")
            }
            .buttonStyle(AutomationQuietButtonStyle())
            .disabled(!canApply)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(NSLocalizedString("Dismiss", comment: ""))
        }
    }

    private func loopPresetTitle(_ loops: Int) -> String {
        switch loops {
        case 0:
            return NSLocalizedString("Continuous", comment: "")
        case 1:
            return NSLocalizedString("Once", comment: "")
        default:
            return String(format: NSLocalizedString("%d×", comment: ""), loops)
        }
    }
}

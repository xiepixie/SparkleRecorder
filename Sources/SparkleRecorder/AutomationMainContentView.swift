import SparkleRecorderCore
import SwiftUI

enum AutomationCentralTab: String, CaseIterable {
  case editor
  case settings
}

private enum AutomationWorkspaceSurface {
  case catalog
  case editor
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
  let catalogProjection: AutomationCatalogProjection
  let runCenterProjection: AutomationRunCenterProjection
  let macros: [SavedMacro]
  let currentMacroID: UUID?
  let refreshState: AutomationRepositoryRefreshState
  let isRecordingMacro: Bool
  let recordingFlowActive: Bool
  let recordHotkeyName: String?
  let requestedWorkspaceDestination: AutomationWorkspaceDestination?
  let onConsumeWorkspaceDestination: () -> Void
  let initialSelectedRunID: UUID?
  let initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState?
  let initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState?
  let onRefresh: () -> Void
  let onAction: (AutomationAction) -> Void
  let onCommitAction: @MainActor (AutomationAction) async throws -> Void
  let onRecordMacro: (() -> Void)?
  let onPreviewScheduledMacro: @MainActor (UUID, AutomationTask?) async throws -> Void
  let onRenameMacro: ((UUID, String) -> Void)?
  let onSetMacroLoops: ((UUID, Int) -> Void)?
  let visualAssetPackageRootAssociation: AutomationVisualAssetPackageRootAssociation
  let onShowLibrary: () -> Void

  @State private var authoringState: AutomationWorkflowAuthoringState
  @State private var draftPreviewState: AutomationWorkflowDraftPreviewState?
  @State private var importNoticeState: AutomationWorkflowImportNoticeState?
  @State private var workflowRecordingHandoff = AutomationWorkflowRecordingHandoff()
  @State private var recordedTaskReviewDraft: AutomationRecordedTaskReviewDraft?
  @State private var editingQuickScheduleWorkflow: AutomationWorkflow?
  @State private var editingSequenceWorkflow: AutomationWorkflow?

  @State private var centralTab: AutomationCentralTab = .editor
  @State private var isLeftSidebarVisible: Bool = true
  @State private var isRightSidebarVisible: Bool = true
  @State private var workspaceSurface: AutomationWorkspaceSurface

  init(
    state: AutomationRunState,
    projection: AutomationOverviewProjection,
    catalogProjection: AutomationCatalogProjection? = nil,
    runCenterProjection: AutomationRunCenterProjection? = nil,
    macros: [SavedMacro],
    currentMacroID: UUID? = nil,
    refreshState: AutomationRepositoryRefreshState,
    isRecordingMacro: Bool = false,
    recordingFlowActive: Bool = false,
    recordHotkeyName: String? = nil,
    requestedWorkspaceDestination: AutomationWorkspaceDestination? = nil,
    onConsumeWorkspaceDestination: @escaping () -> Void = {},
    initialSelectedWorkflowID: UUID? = nil,
    initialSelection: AutomationAuthoringSelection = .workflow,
    initialSelectedRunID: UUID? = nil,
    initialPendingDependencySourceID: UUID? = nil,
    initialPendingDependencyTrigger: AutomationDependencyTriggerDraft = .onSuccess,
    initialFlowGraphLinkPreview: AutomationFlowGraphLinkPreviewState? = nil,
    initialTaskListPreviewState: AutomationWorkflowTaskListPreviewState? = nil,
    onRefresh: @escaping () -> Void,
    onAction: @escaping (AutomationAction) -> Void,
    onCommitAction: @escaping @MainActor (AutomationAction) async throws -> Void = { _ in },
    onRecordMacro: (() -> Void)? = nil,
    onPreviewScheduledMacro: @escaping @MainActor (UUID, AutomationTask?) async throws -> Void = { _, _ in },
    onRenameMacro: ((UUID, String) -> Void)? = nil,
    onSetMacroLoops: ((UUID, Int) -> Void)? = nil,
    visualAssetPackageRootAssociation: AutomationVisualAssetPackageRootAssociation = .inMemory(),
    onShowLibrary: @escaping () -> Void = {}
  ) {
    self.state = state
    self.projection = projection
    self.catalogProjection =
      catalogProjection
      ?? AutomationCatalogProjection.make(state: state, overview: projection)
    self.runCenterProjection =
      runCenterProjection ?? AutomationRunCenterProjection.make(state: state)
    self.macros = macros
    self.currentMacroID = currentMacroID
    self.refreshState = refreshState
    self.isRecordingMacro = isRecordingMacro
    self.recordingFlowActive = recordingFlowActive
    self.recordHotkeyName = recordHotkeyName
    self.requestedWorkspaceDestination = requestedWorkspaceDestination
    self.onConsumeWorkspaceDestination = onConsumeWorkspaceDestination
    self.initialSelectedRunID = initialSelectedRunID
    self.initialFlowGraphLinkPreview = initialFlowGraphLinkPreview
    self.initialTaskListPreviewState = initialTaskListPreviewState
    self.onRefresh = onRefresh
    self.onAction = onAction
    self.onCommitAction = onCommitAction
    self.onRecordMacro = onRecordMacro
    self.onPreviewScheduledMacro = onPreviewScheduledMacro
    self.onRenameMacro = onRenameMacro
    self.onSetMacroLoops = onSetMacroLoops
    self.visualAssetPackageRootAssociation = visualAssetPackageRootAssociation
    self.onShowLibrary = onShowLibrary
    _authoringState = State(
      initialValue: AutomationWorkflowAuthoringState(
        selectedWorkflowID: initialSelectedWorkflowID,
        selection: initialSelection,
        pendingDependencySourceID: initialPendingDependencySourceID,
        pendingDependencyTrigger: initialPendingDependencyTrigger,
        selectedInspectorRunID: initialSelectedRunID
      )
    )
    _workspaceSurface = State(
      initialValue: initialSelectedWorkflowID == nil ? .catalog : .editor
    )
  }

  private var selectedWorkflowID: UUID? {
    authoringState.selectedWorkflowID
  }

  private var selection: AutomationAuthoringSelection {
    authoringState.selection
  }

  private var pendingDependencySourceID: UUID? {
    authoringState.pendingDependencySourceID
  }

  private var pendingDependencyTrigger: AutomationDependencyTriggerDraft {
    authoringState.pendingDependencyTrigger
  }

  private var selectedInspectorRunID: UUID? {
    authoringState.selectedInspectorRunID
  }

  private var authoringRepairSignature: AutomationWorkflowAuthoringRepairSignature {
    AutomationWorkflowAuthoringRepairSignature(workflows: state.workflows)
  }

  private var selectedWorkflow: AutomationWorkflowProjection? {
    let selectedID = selectedWorkflowID ?? projection.workflows.first?.id
    return projection.workflows.first { $0.id == selectedID }
  }

  private var selectedRawWorkflow: AutomationWorkflow? {
    let selectedID =
      selectedWorkflowID ?? projection.workflows.first?.id ?? state.workflows.first?.id
    return state.workflows.first { $0.id == selectedID }
  }

  private var pendingDependencyTriggerOptions: [AutomationDependencyTriggerDraft] {
    authoringState.dependencyTriggerOptions(in: selectedRawWorkflow)
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
      ?? selectedRawWorkflow?.tasks.first(where: { task in
        guard let schedule = task.schedule else { return false }
        return schedule != .manual
      })?.id
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

  private var isSelectedNextScheduledTaskEnabled: Bool {
    guard let taskID = selectedNextScheduledTaskID else {
      return false
    }
    return selectedRawWorkflow?.task(id: taskID)?.isEnabled ?? false
  }

  private var selectedNextScheduledTaskTargetApplicationPolicy: AutomationTargetApplicationPolicy {
    guard let taskID = selectedNextScheduledTaskID else {
      return .activateIfRunning
    }
    return selectedRawWorkflow?.task(id: taskID)?.targetApplicationPolicy ?? .activateIfRunning
  }

  private var hasSelectedNextScheduledTaskBoundTargetApplication: Bool {
    guard let taskID = selectedNextScheduledTaskID,
      let task = selectedRawWorkflow?.task(id: taskID),
      case .macro(let macroID) = task.kind,
      let macro = macros.first(where: { $0.id == macroID })
    else {
      return false
    }
    return !macro.surfaces.isEmpty
  }

  private var recordsMacroIntoWorkflow: Bool {
    onRecordMacro != nil
  }

  private var isRecordingIntoWorkflow: Bool {
    workflowRecordingHandoff.isRecordingIntoWorkflow
  }

  private var recordMacroAction: (() -> Void)? {
    guard onRecordMacro != nil else {
      return nil
    }
    return recordMacroFromWorkflow
  }

  private var recordedTaskReviewBinding: Binding<AutomationRecordedTaskReviewDraft> {
    Binding {
      recordedTaskReviewDraft
        ?? AutomationRecordedTaskReviewDraft(
          workflowID: selectedRawWorkflow?.id ?? UUID(),
          task: AutomationTask(
            name: String(localized: "Recorded task", table: "Automation"),
            kind: .delay(0)
          ),
          macroID: currentMacroID ?? UUID(),
          nameDraft: String(localized: "Recorded task", table: "Automation"),
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

      if workspaceSurface == .catalog {
        AutomationCatalogView(
          catalog: catalogProjection,
          runs: runCenterProjection,
          refreshState: refreshState,
          onOpen: openAutomation,
          onRun: runAutomation,
          onSetEnabled: setAutomationEnabled,
          onDelete: deleteWorkflow,
          onCreateFromLibrary: onShowLibrary,
          onCreateAdvanced: createWorkflow,
          onRefresh: onRefresh
        )
      } else {
        VStack(spacing: 0) {
          AutomationOverviewHeader(
            projection: projection,
            refreshState: refreshState,
            onBack: { workspaceSurface = .catalog },
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
                selectedWorkflowID: selectedWorkflowID,
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
                workflowEditorToolbar

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
                      isNextScheduledTaskEnabled: isSelectedNextScheduledTaskEnabled,
                      hasNextScheduledTaskBoundTargetApplication:
                        hasSelectedNextScheduledTaskBoundTargetApplication,
                      nextScheduledTaskTargetApplicationPolicy:
                        selectedNextScheduledTaskTargetApplicationPolicy,
                      selectedRunID: selectedInspectorRunID,
                      onUpdateNextSchedule: updateNextSchedule,
                      onSetNextScheduledTaskEnabled: setNextScheduledTaskEnabled,
                      onSetNextScheduledTaskTargetApplicationPolicy:
                        setNextScheduledTaskTargetApplicationPolicy,
                      onSelectItem: selectTimelineItem
                    )
                    .frame(minHeight: 188, idealHeight: 232, maxHeight: 286)
                    .frame(maxWidth: .infinity)
                  }
                case .settings:
                  workflowSettingsContent(workflowProjection: workflow)
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
                  onCommitAction: onCommitAction,
                  onCancelLink: cancelDependency
                )
                .frame(width: 356)
                .transition(.move(edge: .trailing))
              }
            } else {
              AutomationEmptyState(
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                title: String(localized: "No workflows", table: "Automation"),
                subtitle: String(
                  localized: "Create a workflow to start arranging macros and conditions.",
                  table: "Automation")
              )
              .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
      }
    }
    .onAppear {
      if !applyRequestedWorkspaceDestination() {
        repairSelection()
      }
    }
    .onChange(of: projection.workflows.map(\.id)) { old, new in
      if !applyRequestedWorkspaceDestination(), new.count > old.count {
        let addedIDs = Set(new).subtracting(old)
        if let newID = addedIDs.first {
          authoringState.selectWorkflow(newID)
        }
      }
      repairSelection()
      repairImportNotice()
    }
    .onChange(of: authoringRepairSignature) {
      repairSelection()
    }
    .onChange(of: requestedWorkspaceDestination) {
      _ = applyRequestedWorkspaceDestination()
    }
    .onChange(of: isRecordingMacro) {
      handleWorkflowRecordingStateChange()
    }
    .onChange(of: recordingFlowActive) { _, active in
      guard !active else { return }
      handleWorkflowRecordingFlowEnded()
    }
    .onChange(of: macros.map(\.id)) {
      guard let intentID = workflowRecordingHandoff.completionCheckID() else {
        return
      }
      completeWorkflowRecordingIntent(expectedIntentID: intentID, clearIfMissing: false)
    }
    .sheet(item: $draftPreviewState) { state in
      AutomationWorkflowDraftPreviewSheet(
        state: state,
        existingWorkflowName: existingWorkflowName(for: state.compiledWorkflow),
        onImportWorkflow: importWorkflowFromDraftPreview
      )
    }
    .sheet(item: $editingQuickScheduleWorkflow) { workflow in
      quickScheduleEditor(for: workflow)
    }
    .sheet(item: $editingSequenceWorkflow) { workflow in
      sequenceEditor(for: workflow)
    }
  }

  @ViewBuilder
  private func workflowSettingsContent(
    workflowProjection: AutomationWorkflowProjection
  ) -> some View {
    if let rawWorkflow = selectedRawWorkflow {
      ScrollView {
        AutomationWorkflowSettingsView(
          workflow: rawWorkflow,
          status: workflowProjection.status,
          statusDetail: workflowProjection.statusDetail,
          nextScheduledOccurrence: workflowProjection.nextScheduledOccurrence,
          nextScheduledTaskName: selectedNextScheduledTaskName,
          workflowProjection: workflowProjection,
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
        title: String(localized: "No workflow selected", table: "Automation"),
        subtitle: String(
          localized: "Create a workflow to view workflow details.",
          table: "Automation")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var workflowEditorToolbar: some View {
    HStack {
      Button(
        String(localized: "Toggle Left Sidebar", table: "Common"),
        systemImage: "sidebar.left",
        action: { withAnimation { isLeftSidebarVisible.toggle() } }
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .padding(.horizontal, 8)
      .opacity(isLeftSidebarVisible ? 1.0 : 0.6)

      Spacer()

      Picker("", selection: $centralTab) {
        Text("Canvas", tableName: "Common").tag(AutomationCentralTab.editor)
        Text("Workflow", tableName: "Automation").tag(AutomationCentralTab.settings)
      }
      .pickerStyle(.segmented)
      .frame(width: 250)

      Spacer()

      Button(
        String(localized: "Toggle Right Sidebar", table: "Common"),
        systemImage: "sidebar.right",
        action: { withAnimation { isRightSidebarVisible.toggle() } }
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .padding(.horizontal, 8)
      .opacity(isRightSidebarVisible ? 1.0 : 0.6)

      Button(
        String(localized: "Auto Arrange", table: "Common"),
        systemImage: "wand.and.stars",
        action: autoArrangeTasks
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .padding(.horizontal, 8)
    }
    .padding(8)
    .background(Material.bar)
  }

  private var selectedTaskID: UUID? {
    authoringState.selectedTaskID
  }

  private var selectedDependencyID: UUID? {
    authoringState.selectedDependencyID
  }

  private func selectWorkflow(_ workflowID: UUID?) {
    authoringState.selectWorkflow(workflowID)
  }

  private func openAutomation(_ workflowID: UUID) {
    guard
      let item = catalogProjection.items.first(where: { $0.workflowID == workflowID }),
      let workflow = state.workflows.first(where: { $0.id == workflowID })
    else {
      return
    }
    switch item.tier {
    case .singleMacro:
      editingQuickScheduleWorkflow = workflow
    case .linearSequence:
      if AutomationLinearSequenceDraft(workflow: workflow, macros: macros) != nil {
        editingSequenceWorkflow = workflow
      } else {
        openWorkflowEditor(workflowID)
      }
    case .advancedWorkflow:
      openWorkflowEditor(workflowID)
    }
  }

  private func openWorkflowEditor(_ workflowID: UUID) {
    selectWorkflow(workflowID)
    workspaceSurface = .editor
  }

  private func runAutomation(_ workflowID: UUID) {
    onAction(.manualStartWorkflow(workflowID: workflowID, requestedAt: Date()))
  }

  private func setAutomationEnabled(_ workflowID: UUID, _ isEnabled: Bool) {
    guard let workflow = state.workflows.first(where: { $0.id == workflowID }) else { return }
    let entryTaskIDs = Set(AutomationCatalogProjection.entryTaskIDs(for: workflow))
    let changedAt = Date()
    for var task in workflow.tasks
    where entryTaskIDs.contains(task.id) && task.isEnabled != isEnabled {
      task.isEnabled = isEnabled
      onAction(.upsertTask(workflowID: workflowID, task: task, at: changedAt))
    }
  }

  @ViewBuilder
  private func quickScheduleEditor(for workflow: AutomationWorkflow) -> some View {
    if let task = workflow.tasks.first,
      let macroID = task.kind.macroID,
      let macro = macros.first(where: { $0.id == macroID })
    {
      AutomationQuickScheduleSheet(
        macro: macro,
        existingSummary: quickScheduleSummary(workflow: workflow, task: task),
        onPreview: { replacement in
          try await onPreviewScheduledMacro(macroID, replacement.tasks.first)
        },
        onDisable: {
          var pausedTask = task
          pausedTask.isEnabled = false
          try await onCommitAction(
            .upsertTask(workflowID: workflow.id, task: pausedTask, at: Date())
          )
        },
        onCreate: { replacement, _ in
          var updated = replacement
          updated.id = workflow.id
          updated.createdAt = workflow.createdAt
          updated.modifiedAt = Date()
          if !updated.tasks.isEmpty {
            updated.tasks[0].id = task.id
          }
          try await onCommitAction(.upsertWorkflow(updated, at: updated.modifiedAt))
        }
      )
    } else {
      AutomationEmptyState(
        systemImage: "exclamationmark.triangle",
        title: String(localized: "Macro is missing", table: "EditorUX"),
        subtitle: String(
          localized: "Open the workflow editor to repair this automation.", table: "Automation")
      )
      .frame(width: 480, height: 280)
    }
  }

  private func quickScheduleSummary(
    workflow: AutomationWorkflow,
    task: AutomationTask
  ) -> AutomationMacroScheduleSummary {
    let nextRun =
      task.isEnabled
      ? task.schedule?.nextOccurrence(onOrAfter: Date())?.scheduledAt
      : nil
    let statusText: String
    if !task.isEnabled {
      statusText = String(localized: "Automatic run paused", table: "Automation")
    } else if let nextRun {
      statusText = String(
        format: String(localized: "Next: %@", table: "Automation"),
        nextRun.formatted(date: .abbreviated, time: .shortened)
      )
    } else {
      statusText = String(localized: "No upcoming run", table: "Automation")
    }
    return AutomationMacroScheduleSummary(
      workflowID: workflow.id,
      task: task,
      nextRun: nextRun,
      matchingWorkflowIDs: [workflow.id],
      statusText: statusText
    )
  }

  @ViewBuilder
  private func sequenceEditor(for workflow: AutomationWorkflow) -> some View {
    if let draft = AutomationLinearSequenceDraft(workflow: workflow, macros: macros) {
      AutomationSequentialBuilderSheet(
        initialMacros: [],
        availableMacros: macros,
        initialDraft: draft
      ) { document, openInWorkflow, runAfterSaving in
        try await replaceLinearAutomation(
          workflow,
          with: document,
          openInWorkflow: openInWorkflow,
          runAfterSaving: runAfterSaving
        )
      }
    } else {
      AutomationEmptyState(
        systemImage: "exclamationmark.triangle",
        title: String(localized: "Sequence could not be opened", table: "Automation"),
        subtitle: String(
          localized: "Open the workflow editor to preserve its advanced settings.",
          table: "Automation")
      )
      .frame(width: 480, height: 280)
    }
  }

  @MainActor
  private func replaceLinearAutomation(
    _ existing: AutomationWorkflow,
    with document: AutomationWorkflowDraftDocument,
    openInWorkflow: Bool,
    runAfterSaving: Bool
  ) async throws {
    var options = AutomationWorkflowDraftImportOptions(mode: .confirm)
    options.stableIDNamespace = existing.id.uuidString
    let catalog = macros.map {
      AutomationWorkflowDraftMacroCatalogEntry(id: $0.id, name: $0.name)
    }
    let result = AutomationWorkflowDraftImporter.compile(
      document,
      context: AutomationWorkflowDraftValidationContext(macroCatalog: catalog),
      options: options
    )
    guard var updated = result.workflow else {
      throw AutomationTargetApplicationPreparationFailure(
        message: String(localized: "Could not save the sequence.", table: "Automation")
      )
    }
    updated.id = existing.id
    updated.createdAt = existing.createdAt
    updated.modifiedAt = Date()
    try await onCommitAction(.upsertWorkflow(updated, at: updated.modifiedAt))

    if openInWorkflow {
      openWorkflowEditor(updated.id)
    } else if runAfterSaving {
      // The workflow is already durably saved. Runtime start is a secondary
      // action, so a start failure must not keep a save sheet open and invite a
      // duplicate save attempt.
      onAction(.manualStartWorkflow(workflowID: updated.id, requestedAt: Date()))
    }
  }

  private func selectTask(_ taskID: UUID) {
    authoringState.selectTask(taskID)
  }

  private func selectDependency(_ dependencyID: UUID) {
    authoringState.selectDependency(dependencyID)
  }

  private func selectTimelineItem(_ item: AutomationResourceTimelineItem) {
    authoringState.selectTimelineItem(item)
  }

  private func createWorkflow() {
    let date = Date()
    let workflow = AutomationWorkflow(
      name: String(localized: "New Workflow", table: "Automation"),
      createdAt: date,
      modifiedAt: date
    )
    authoringState.selectWorkflow(workflow.id)
    workspaceSurface = .editor
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
      try await AutomationWorkflowImportTransaction.commit(
        workflows,
        replacing: state.workflows,
        perform: onCommitAction,
        at: date
      )
      authoringState.selectWorkflow(workflows.first?.id)
    }
  }

  private func deleteWorkflow(_ workflowID: UUID) {
    let date = Date()
    authoringState.didDeleteWorkflow(
      workflowID,
      remainingWorkflows: state.workflows.filter { $0.id != workflowID }
    )
    if importNoticeState?.workflowID == workflowID {
      importNoticeState = nil
    }
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
      defaultName: String(localized: "Workflows", table: "Automation")
    )
  }

  private func shareWorkflowPackage(_ workflow: AutomationWorkflow) {
    AutomationWorkflowPackagePresenter.share(workflow: workflow)
  }

  private func shareWorkflowPackage() {
    AutomationWorkflowPackagePresenter.share(
      workflows: state.workflows,
      defaultName: String(localized: "Workflows", table: "Automation")
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

  @MainActor
  private func importWorkflowFromDraftPreview(
    _ workflow: AutomationWorkflow,
    sourceDirectory: URL?
  ) async throws {
    let date = Date()
    var workflowToImport = workflow
    let existingWorkflow = state.workflows.first { $0.id == workflow.id }
    if let existingWorkflow {
      workflowToImport.createdAt = existingWorkflow.createdAt
    } else {
      workflowToImport.createdAt = date
    }

    try await onCommitAction(.upsertWorkflow(workflowToImport, at: date))
    do {
      try await visualAssetPackageRootAssociation.persist(
        [
          AutomationVisualAssetPackageRootAssociation.Request(
            workflow: workflowToImport,
            packageDirectoryURL: sourceDirectory,
            source: .aiDraftImport
          )
        ],
        associatedAt: date
      )
    } catch {
      throw AutomationTargetApplicationPreparationFailure(
        message: String(
          localized: "The workflow was saved, but its visual assets could not be linked. Try importing again.",
          table: "Automation"
        )
      )
    }

    authoringState.selectWorkflow(workflowToImport.id)
    importNoticeState = AutomationWorkflowImportNoticeState(
      workflowID: workflowToImport.id,
      workflowName: workflowToImport.name,
      taskCount: workflowToImport.tasks.count,
      dependencyCount: workflowToImport.dependencies.count,
      isReplacement: existingWorkflow != nil,
      previousWorkflow: existingWorkflow
    )
  }

  private func updateNextSchedule(to edit: AutomationTimelineScheduleEdit) {
    guard let workflow = selectedRawWorkflow,
      let taskID = selectedWorkflow?.nextScheduledTaskID ?? workflowStartTaskID(in: workflow),
      var task = workflow.tasks.first(where: { $0.id == taskID })
    else {
      return
    }

    switch edit.mode {
    case .manual:
      task.schedule = .manual
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

  private func setNextScheduledTaskEnabled(_ isEnabled: Bool) {
    guard let workflow = selectedRawWorkflow,
      let taskID = selectedNextScheduledTaskID,
      var task = workflow.task(id: taskID)
    else {
      return
    }
    task.isEnabled = isEnabled
    onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
  }

  private func setNextScheduledTaskTargetApplicationPolicy(
    _ policy: AutomationTargetApplicationPolicy
  ) {
    guard let workflow = selectedRawWorkflow,
      let taskID = selectedNextScheduledTaskID,
      var task = workflow.task(id: taskID)
    else {
      return
    }
    task.targetApplicationPolicy = policy
    onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
  }

  private func workflowStartTaskID(in workflow: AutomationWorkflow) -> UUID? {
    AutomationCatalogProjection.entryTaskIDs(for: workflow).first
      ?? workflow.tasks.first?.id
  }

  private func undoWorkflowDraftImport() {
    guard let notice = importNoticeState else {
      return
    }

    importNoticeState = nil
    let date = Date()
    if let previousWorkflow = notice.previousWorkflow {
      authoringState.selectWorkflow(previousWorkflow.id)
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

    if !isRecordingMacro && !recordingFlowActive {
      recordedTaskReviewDraft = nil
      workflowRecordingHandoff.begin(
        targetWorkflowID: selectedRawWorkflow?.id ?? selectedWorkflowID,
        existingMacroIDs: Set(macros.map(\.id))
      )
    }
    onRecordMacro()
  }

  private func handleWorkflowRecordingStateChange() {
    if isRecordingMacro {
      workflowRecordingHandoff.recordingStarted()
    } else if let intentID = workflowRecordingHandoff.completionCheckID() {
      scheduleWorkflowRecordingCompletionCheck(expectedIntentID: intentID)
    }
  }

  private func handleWorkflowRecordingFlowEnded() {
    guard let intentID = workflowRecordingHandoff.recordingFlowEnded() else {
      return
    }
    scheduleWorkflowRecordingCompletionCheck(expectedIntentID: intentID)
  }

  private func scheduleWorkflowRecordingCompletionCheck(expectedIntentID: UUID) {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 250_000_000)
      completeWorkflowRecordingIntent(
        expectedIntentID: expectedIntentID,
        clearIfMissing: true
      )
    }
  }

  private func completeWorkflowRecordingIntent(
    expectedIntentID: UUID,
    clearIfMissing: Bool
  ) {
    let completion = workflowRecordingHandoff.resolveCompletion(
      expectedIntentID: expectedIntentID,
      isRecordingMacro: isRecordingMacro,
      currentMacroID: currentMacroID,
      macros: macros,
      clearIfMissing: clearIfMissing
    )

    guard case .recorded(let targetWorkflowID, let macroID) = completion,
      let recordedMacro = macros.first(where: { $0.id == macroID })
    else {
      return
    }

    if let targetWorkflowID {
      authoringState.selectWorkflow(targetWorkflowID)
    }
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
      authoringState.selectCreatedTask(task.id, workflowID: workflow.id)
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
        name: String(localized: "New Workflow", table: "Automation"),
        tasks: [task],
        createdAt: date,
        modifiedAt: date
      )
      authoringState.selectCreatedTask(task.id, workflowID: workflow.id)
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

    var updatedTask =
      state.workflows
      .first { $0.id == draft.workflowID }?
      .task(id: draft.task.id)
      ?? draft.task
    updatedTask.name = trimmedName

    authoringState.selectCreatedTask(updatedTask.id, workflowID: draft.workflowID)
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
      let previousNode = nodesByTaskID[workflow.tasks[index - 1].id]
    {
      return AutomationGraphPoint(
        x: previousNode.position.x,
        y: previousNode.position.y + gap
      )
    }

    if index < workflow.tasks.count,
      let nextNode = nodesByTaskID[workflow.tasks[index].id]
    {
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
      name = String(localized: "Manual approval", table: "Common")
    case .externalSignal(let signalName):
      name = signalName.isEmpty ? String(localized: "External signal", table: "Common") : signalName
    case .ocrText:
      name = String(localized: "Text condition", table: "Automation")
    case .visual(let condition):
      name = AutomationVisualConditionPresentation.title(for: condition.type)
    case .previousOutcome:
      name = String(localized: "Previous outcome", table: "Common")
    }

    let task = AutomationTask(
      name: name,
      kind: .condition(AutomationConditionSpec(name: name, kind: kind)),
      schedule: .manual,
      resourceRequirement: conditionTaskResourceRequirement(for: kind),
      graphPosition: defaultGraphPosition()
    )
    authoringState.selectCreatedTask(task.id, workflowID: workflow.id)
    onAction(.upsertTask(workflowID: workflow.id, task: task, at: Date()))
  }

  private func conditionTaskResourceRequirement(for kind: AutomationConditionKind)
    -> AutomationResourceRequirement
  {
    switch kind {
    case .ocrText, .visual:
      return .backgroundReadOnly
    case .manualApproval, .externalSignal, .previousOutcome:
      return .none
    }
  }

  private func startDependency(from taskID: UUID) {
    guard let workflow = selectedRawWorkflow else {
      authoringState.cancelDependency()
      return
    }
    _ = authoringState.beginDependency(from: taskID, in: workflow)
  }

  private func setPendingDependencyTrigger(_ trigger: AutomationDependencyTriggerDraft) {
    authoringState.setPendingDependencyTrigger(trigger, in: selectedRawWorkflow)
  }

  private func completeDependency(to taskID: UUID) {
    guard let workflow = selectedRawWorkflow else {
      authoringState.cancelDependency()
      return
    }

    switch authoringState.completeDependency(to: taskID, in: workflow) {
    case .invalid, .existing:
      return
    case .create(let dependency):
      onAction(.upsertDependency(workflowID: workflow.id, dependency: dependency, at: Date()))
    }
  }

  private func cancelDependency() {
    authoringState.cancelDependency()
  }

  private func deleteDependencyFromGraph(_ dependencyID: UUID) {
    guard let workflow = selectedRawWorkflow else {
      return
    }
    authoringState.didDeleteDependency(dependencyID)
    onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependencyID, at: Date()))
  }

  @discardableResult
  private func applyRequestedWorkspaceDestination() -> Bool {
    guard let requestedWorkspaceDestination,
      let resolution = AutomationWorkspaceNavigation.resolve(
        requestedWorkspaceDestination,
        workflows: state.workflows
      )
    else {
      return false
    }

    authoringState.applyNavigation(resolution)
    workspaceSurface = .editor
    onConsumeWorkspaceDestination()
    return true
  }

  private func repairSelection() {
    authoringState.repair(workflows: state.workflows)
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
      let selectedNode = workflow.nodes.first(where: { $0.taskID == selectedTaskID })
    {
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
        Text("Recorded task", tableName: "Automation")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(1)

        Text("Saved as source macro", tableName: "EditorUX")
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
    TextField(String(localized: "Task name", table: "Automation"), text: nameBinding)
      .textFieldStyle(.roundedBorder)
      .onSubmit(onApply)
  }

  private var repeatControls: some View {
    HStack(spacing: 6) {
      Picker(String(localized: "Source repeat", table: "Common"), selection: loopsBinding) {
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
        Label(String(localized: "Apply", table: "Common"), systemImage: "checkmark")
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
      .accessibilityLabel(String(localized: "Dismiss", table: "Common"))
    }
  }

  private func loopPresetTitle(_ loops: Int) -> String {
    switch loops {
    case 0:
      return String(localized: "Continuous", table: "Common")
    case 1:
      return String(localized: "Once", table: "Common")
    default:
      return String(format: String(localized: "%d×", table: "Common"), loops)
    }
  }
}

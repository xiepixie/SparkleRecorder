import SparkleRecorderCore
import SwiftUI

struct AutomationMainView: View {
  @EnvironmentObject private var library: MacroLibrary
  @EnvironmentObject private var appState: AppState

  @State private var model: AutomationOverviewModel
  private let onAction: (AutomationAction) -> Void
  private let onRecordMacro: (() -> Void)?
  private let onPreviewScheduledMacro: @MainActor (UUID, AutomationTask?) async throws -> Void
  private let onRenameMacro: (UUID, String) -> Void
  private let onSetMacroLoops: (UUID, Int) -> Void

  init(
    projection: AutomationOverviewProjection = .ownerCFixture(),
    onAction: @escaping (AutomationAction) -> Void = { _ in },
    onRecordMacro: (() -> Void)? = nil,
    onPreviewScheduledMacro: @escaping @MainActor (UUID, AutomationTask?) async throws -> Void = { _, _ in },
    onRenameMacro: @escaping (UUID, String) -> Void = { _, _ in },
    onSetMacroLoops: @escaping (UUID, Int) -> Void = { _, _ in }
  ) {
    _model = State(initialValue: AutomationOverviewModel(projection: projection))
    self.onAction = onAction
    self.onRecordMacro = onRecordMacro
    self.onPreviewScheduledMacro = onPreviewScheduledMacro
    self.onRenameMacro = onRenameMacro
    self.onSetMacroLoops = onSetMacroLoops
  }

  init(
    snapshotClient: AutomationRepositorySnapshotClient,
    initialProjection: AutomationOverviewProjection = .ownerCFixture(),
    onAction: @escaping (AutomationAction) -> Void = { _ in },
    onRecordMacro: (() -> Void)? = nil,
    onPreviewScheduledMacro: @escaping @MainActor (UUID, AutomationTask?) async throws -> Void = { _, _ in },
    onRenameMacro: @escaping (UUID, String) -> Void = { _, _ in },
    onSetMacroLoops: @escaping (UUID, Int) -> Void = { _, _ in }
  ) {
    _model = State(
      initialValue: AutomationOverviewModel(
        snapshotClient: snapshotClient,
        initialProjection: initialProjection
      ))
    self.onAction = onAction
    self.onRecordMacro = onRecordMacro
    self.onPreviewScheduledMacro = onPreviewScheduledMacro
    self.onRenameMacro = onRenameMacro
    self.onSetMacroLoops = onSetMacroLoops
  }

  init(
    runtimeHost: LiveAutomationRuntimeHost,
    initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(
      from: AutomationRunState()),
    onAction: @escaping (AutomationAction) -> Void = { _ in },
    onRecordMacro: (() -> Void)? = nil,
    onPreviewScheduledMacro: @escaping @MainActor (UUID, AutomationTask?) async throws -> Void = { _, _ in },
    onRenameMacro: @escaping (UUID, String) -> Void = { _, _ in },
    onSetMacroLoops: @escaping (UUID, Int) -> Void = { _, _ in }
  ) {
    _model = State(
      initialValue: AutomationOverviewModel(
        runtimeHost: runtimeHost,
        initialProjection: initialProjection
      ))
    self.onAction = onAction
    self.onRecordMacro = onRecordMacro
    self.onPreviewScheduledMacro = onPreviewScheduledMacro
    self.onRenameMacro = onRenameMacro
    self.onSetMacroLoops = onSetMacroLoops
  }

  var body: some View {
    let destination = appState.automationWorkspaceDestination
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 12) {
          AutomationMainContentView(
            state: model.state,
            projection: model.projection,
            catalogProjection: model.catalogProjection,
            runCenterProjection: model.runCenterProjection,
            macros: library.macros,
            currentMacroID: library.currentMacroID,
            refreshState: model.refreshState,
            isRecordingMacro: appState.isRecording,
            recordingFlowActive: appState.recordingFlowActive,
            recordHotkeyName: appState.recordHotkey.name,
            requestedWorkspaceDestination: destination,
            onConsumeWorkspaceDestination: { appState.automationWorkspaceDestination = nil },
            initialSelectedWorkflowID: destination?.workflowID,
            initialSelection: destination?.taskID.map(AutomationAuthoringSelection.task)
              ?? .workflow,
            onRefresh: refresh,
            onAction: handleAction,
            onCommitAction: performAction,
            onRecordMacro: onRecordMacro,
            onPreviewScheduledMacro: onPreviewScheduledMacro,
            onRenameMacro: renameMacro,
            onSetMacroLoops: setMacroLoops,
            onShowLibrary: { appState.workspace = .library }
          )
        }
      } else {
        AutomationMainContentView(
          state: model.state,
          projection: model.projection,
          catalogProjection: model.catalogProjection,
          runCenterProjection: model.runCenterProjection,
          macros: library.macros,
          currentMacroID: library.currentMacroID,
          refreshState: model.refreshState,
          isRecordingMacro: appState.isRecording,
          recordingFlowActive: appState.recordingFlowActive,
          recordHotkeyName: appState.recordHotkey.name,
          requestedWorkspaceDestination: destination,
          onConsumeWorkspaceDestination: { appState.automationWorkspaceDestination = nil },
          initialSelectedWorkflowID: destination?.workflowID,
          initialSelection: destination?.taskID.map(AutomationAuthoringSelection.task) ?? .workflow,
          onRefresh: refresh,
          onAction: handleAction,
          onCommitAction: performAction,
          onRecordMacro: onRecordMacro,
          onPreviewScheduledMacro: onPreviewScheduledMacro,
          onRenameMacro: renameMacro,
          onSetMacroLoops: setMacroLoops,
          onShowLibrary: { appState.workspace = .library }
        )
      }
    }
    .task {
      model.startAutoRefresh()
    }
    .onDisappear {
      model.stopAutoRefresh()
    }
  }

  private func refresh() {
    Task {
      await model.refresh()
    }
  }

  private func handleAction(_ action: AutomationAction) {
    onAction(action)
    Task {
      await model.dispatch(action)
    }
  }

  @MainActor
  private func performAction(_ action: AutomationAction) async throws {
    onAction(action)
    try await model.perform(action)
  }

  private func renameMacro(_ macroID: UUID, to name: String) {
    onRenameMacro(macroID, name)
  }

  private func setMacroLoops(_ macroID: UUID, to loops: Int) {
    onSetMacroLoops(macroID, loops)
  }
}

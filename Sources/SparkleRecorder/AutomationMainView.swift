import SwiftUI
import SparkleRecorderCore

struct AutomationMainView: View {
    @EnvironmentObject private var library: MacroLibrary
    @EnvironmentObject private var appState: AppState

    @State private var model: AutomationOverviewModel
    private let onAction: (AutomationAction) -> Void
    private let onRecordMacro: (() -> Void)?

    init(
        projection: AutomationOverviewProjection = .ownerCFixture(),
        onAction: @escaping (AutomationAction) -> Void = { _ in },
        onRecordMacro: (() -> Void)? = nil
    ) {
        _model = State(initialValue: AutomationOverviewModel(projection: projection))
        self.onAction = onAction
        self.onRecordMacro = onRecordMacro
    }

    init(
        snapshotClient: AutomationRepositorySnapshotClient,
        initialProjection: AutomationOverviewProjection = .ownerCFixture(),
        onAction: @escaping (AutomationAction) -> Void = { _ in },
        onRecordMacro: (() -> Void)? = nil
    ) {
        _model = State(initialValue: AutomationOverviewModel(
            snapshotClient: snapshotClient,
            initialProjection: initialProjection
        ))
        self.onAction = onAction
        self.onRecordMacro = onRecordMacro
    }

    init(
        runtimeHost: LiveAutomationRuntimeHost,
        initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(from: AutomationRunState()),
        onAction: @escaping (AutomationAction) -> Void = { _ in },
        onRecordMacro: (() -> Void)? = nil
    ) {
        _model = State(initialValue: AutomationOverviewModel(
            runtimeHost: runtimeHost,
            initialProjection: initialProjection
        ))
        self.onAction = onAction
        self.onRecordMacro = onRecordMacro
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    AutomationMainContentView(
                        state: model.state,
                        projection: model.projection,
                        macros: library.macros,
                        currentMacroID: library.currentMacroID,
                        refreshState: model.refreshState,
                        isRecordingMacro: appState.isRecording,
                        recordHotkeyName: appState.recordHotkey.name,
                        onRefresh: refresh,
                        onAction: handleAction,
                        onRecordMacro: onRecordMacro,
                        onRenameMacro: renameMacro,
                        onSetMacroLoops: setMacroLoops
                    )
                }
            } else {
                AutomationMainContentView(
                    state: model.state,
                    projection: model.projection,
                    macros: library.macros,
                    currentMacroID: library.currentMacroID,
                    refreshState: model.refreshState,
                    isRecordingMacro: appState.isRecording,
                    recordHotkeyName: appState.recordHotkey.name,
                    onRefresh: refresh,
                    onAction: handleAction,
                    onRecordMacro: onRecordMacro,
                    onRenameMacro: renameMacro,
                    onSetMacroLoops: setMacroLoops
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

    private func renameMacro(_ macroID: UUID, to name: String) {
        library.rename(id: macroID, to: name)
    }

    private func setMacroLoops(_ macroID: UUID, to loops: Int) {
        library.setLoops(id: macroID, loops: loops)
    }
}

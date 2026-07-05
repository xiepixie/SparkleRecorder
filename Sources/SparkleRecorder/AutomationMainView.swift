import SwiftUI
import SparkleRecorderCore

struct AutomationMainView: View {
    @EnvironmentObject private var library: MacroLibrary

    @State private var model: AutomationOverviewModel
    private let onAction: (AutomationAction) -> Void

    init(
        projection: AutomationOverviewProjection = .ownerCFixture(),
        onAction: @escaping (AutomationAction) -> Void = { _ in }
    ) {
        _model = State(initialValue: AutomationOverviewModel(projection: projection))
        self.onAction = onAction
    }

    init(
        snapshotClient: AutomationRepositorySnapshotClient,
        initialProjection: AutomationOverviewProjection = .ownerCFixture(),
        onAction: @escaping (AutomationAction) -> Void = { _ in }
    ) {
        _model = State(initialValue: AutomationOverviewModel(
            snapshotClient: snapshotClient,
            initialProjection: initialProjection
        ))
        self.onAction = onAction
    }

    init(
        runtimeHost: LiveAutomationRuntimeHost,
        initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(from: AutomationRunState()),
        onAction: @escaping (AutomationAction) -> Void = { _ in }
    ) {
        _model = State(initialValue: AutomationOverviewModel(
            runtimeHost: runtimeHost,
            initialProjection: initialProjection
        ))
        self.onAction = onAction
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    AutomationMainContentView(
                        state: model.state,
                        projection: model.projection,
                        macros: library.macros,
                        refreshState: model.refreshState,
                        onRefresh: refresh,
                        onAction: handleAction
                    )
                }
            } else {
                AutomationMainContentView(
                    state: model.state,
                    projection: model.projection,
                    macros: library.macros,
                    refreshState: model.refreshState,
                    onRefresh: refresh,
                    onAction: handleAction
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
}

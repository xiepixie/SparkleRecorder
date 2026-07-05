import Foundation
import Observation
import SparkleRecorderCore

@MainActor
@Observable
final class AutomationOverviewModel {
    @ObservationIgnored
    private let snapshotClient: AutomationRepositorySnapshotClient?
    @ObservationIgnored
    private let runtimeHost: LiveAutomationRuntimeHost?
    @ObservationIgnored
    private let now: () -> Date
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    private(set) var state: AutomationRunState
    private(set) var projection: AutomationOverviewProjection
    private(set) var refreshState: AutomationRepositoryRefreshState

    init(
        state: AutomationRunState = AutomationRunState(),
        projection: AutomationOverviewProjection = .ownerCFixture(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.state = state
        self.projection = projection
        self.refreshState = .idle
        self.snapshotClient = nil
        self.runtimeHost = nil
        self.now = now
    }

    init(
        snapshotClient: AutomationRepositorySnapshotClient,
        initialState: AutomationRunState = AutomationRunState(),
        initialProjection: AutomationOverviewProjection = .ownerCFixture(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.state = initialState
        self.projection = initialProjection
        self.refreshState = .idle
        self.snapshotClient = snapshotClient
        self.runtimeHost = nil
        self.now = now
    }

    init(
        runtimeHost: LiveAutomationRuntimeHost,
        initialState: AutomationRunState = AutomationRunState(),
        initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(from: AutomationRunState()),
        now: @escaping () -> Date = { Date() }
    ) {
        self.state = initialState
        self.projection = initialProjection
        self.refreshState = .idle
        self.snapshotClient = nil
        self.runtimeHost = runtimeHost
        self.now = now
    }

    func startAutoRefresh() {
        pollingTask?.cancel()

        guard runtimeHost != nil else {
            pollingTask = Task { [weak self] in
                await self?.refresh()
            }
            return
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refreshRuntimeState()
            }
        }
    }

    func stopAutoRefresh() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        if let runtimeHost {
            refreshState = await runtimeHost.refreshRepositoryState()
            await refreshRuntimeState()
            return
        }

        guard let snapshotClient, !refreshState.isLoading else {
            return
        }

        let previousSnapshot = refreshState.snapshot
        refreshState = .loading(startedAt: now(), previousSnapshot: previousSnapshot)

        switch await snapshotClient.refresh() {
        case .loaded(let snapshot):
            state = snapshot.state
            projection = AutomationViewProjection.overview(from: state)
            refreshState = .loaded(snapshot)
        case .failed(let failure):
            refreshState = .failed(failure, previousSnapshot: previousSnapshot)
        }
    }

    func dispatch(_ action: AutomationAction) async {
        guard let runtimeHost else {
            let result = AutomationReducer.reduce(state: state, action: action)
            state = result.state
            projection = AutomationViewProjection.overview(from: state)
            return
        }

        do {
            state = try await runtimeHost.dispatch(action)
            projection = AutomationViewProjection.overview(from: state)
        } catch {
            refreshState = .failed(
                AutomationRepositoryRefreshFailure(
                    message: String(describing: error),
                    failedAt: now()
                ),
                previousSnapshot: refreshState.snapshot
            )
        }
    }

    private func refreshRuntimeState() async {
        guard let runtimeHost else {
            return
        }

        if let state = await runtimeHost.currentState() {
            self.state = state
            projection = AutomationViewProjection.overview(from: state)
        } else if let snapshot = refreshState.snapshot {
            state = snapshot.state
            projection = AutomationViewProjection.overview(from: state)
        }
    }
}

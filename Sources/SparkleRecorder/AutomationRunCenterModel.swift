import Foundation
import Observation
import SparkleRecorderCore

enum AutomationRunCenterLoadResult: Equatable, Sendable {
    case loaded(AutomationRunState)
    case loadedVersioned(AutomationRuntimeSnapshot)
    case failed(String)
}

enum AutomationRunCenterLoadState: Equatable, Sendable {
    case idle
    case loading(lastLoadedAt: Date?)
    case loaded(at: Date)
    case failed(message: String, lastLoadedAt: Date?)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var lastLoadedAt: Date? {
        switch self {
        case .idle:
            return nil
        case .loading(let lastLoadedAt), .failed(_, let lastLoadedAt):
            return lastLoadedAt
        case .loaded(let date):
            return date
        }
    }

    var failureMessage: String? {
        guard case .failed(let message, _) = self else { return nil }
        return message
    }
}

@MainActor
@Observable
final class AutomationRunCenterModel {
    typealias Loader = @MainActor () async -> AutomationRunCenterLoadResult

    @ObservationIgnored
    private let loader: Loader
    @ObservationIgnored
    private let now: () -> Date
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastRuntimeRevision: UInt64?

    private(set) var projection: AutomationRunCenterProjection
    private(set) var loadState: AutomationRunCenterLoadState = .idle

    init(
        initialState: AutomationRunState = AutomationRunState(),
        now: @escaping () -> Date = { Date() },
        loader: @escaping Loader
    ) {
        self.now = now
        self.loader = loader
        self.projection = AutomationRunCenterProjection.make(
            state: initialState,
            generatedAt: now()
        )
    }

    convenience init(
        runtimeHost: LiveAutomationRuntimeHost,
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(now: now) {
            if let snapshot = await runtimeHost.currentSnapshot() {
                return .loadedVersioned(snapshot)
            }
            switch await runtimeHost.refreshRepositorySnapshot() {
            case .loaded(let snapshot):
                return .loaded(snapshot.state)
            case .failed(let failure):
                return .failed(failure.message)
            }
        }
    }

    func startAutoRefresh(interval: Duration = .seconds(2)) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                await self.refresh(showsLoading: false)
            }
        }
    }

    func stopAutoRefresh() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh(
        showsLoading: Bool = true,
        forceProjection: Bool = false
    ) async {
        guard !loadState.isLoading else { return }
        let lastLoadedAt = loadState.lastLoadedAt
        if showsLoading {
            loadState = .loading(lastLoadedAt: lastLoadedAt)
        }

        switch await loader() {
        case .loaded(let state):
            await applyLoadedState(
                state,
                revision: nil,
                showsLoading: showsLoading,
                lastLoadedAt: lastLoadedAt
            )
        case .loadedVersioned(let snapshot):
            if !forceProjection, lastRuntimeRevision == snapshot.revision {
                if showsLoading {
                    loadState = .loaded(at: now())
                }
                return
            }
            await applyLoadedState(
                snapshot.state,
                revision: snapshot.revision,
                showsLoading: showsLoading,
                lastLoadedAt: lastLoadedAt
            )
        case .failed(let message):
            loadState = .failed(message: message, lastLoadedAt: lastLoadedAt)
        }
    }

    private func applyLoadedState(
        _ state: AutomationRunState,
        revision: UInt64?,
        showsLoading: Bool,
        lastLoadedAt: Date?
    ) async {
        let loadedAt = now()
        let refreshedProjection = await Task.detached(priority: .userInitiated) {
            AutomationRunCenterProjection.make(
                state: state,
                generatedAt: loadedAt
            )
        }.value
        let projectionChanged = projection.summary != refreshedProjection.summary
            || projection.executions != refreshedProjection.executions
            || projection.persistenceIssue != refreshedProjection.persistenceIssue
        if projectionChanged {
            projection = refreshedProjection
        }
        lastRuntimeRevision = revision
        if showsLoading || projectionChanged || loadState.failureMessage != nil || lastLoadedAt == nil {
            loadState = .loaded(at: loadedAt)
        }
    }
}

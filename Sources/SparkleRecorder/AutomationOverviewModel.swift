import Foundation
import Observation
import SparkleRecorderCore

@MainActor
@Observable
final class AutomationOverviewModel {
  @ObservationIgnored
  private let snapshotClient: AutomationRepositorySnapshotClient?
  typealias RuntimeSnapshotLoader = @MainActor () async -> AutomationRuntimeSnapshot?

  @ObservationIgnored
  private let runtimeHost: LiveAutomationRuntimeHost?
  @ObservationIgnored
  private let runtimeSnapshotLoader: RuntimeSnapshotLoader?
  @ObservationIgnored
  private let now: () -> Date
  @ObservationIgnored
  private var pollingTask: Task<Void, Never>?
  @ObservationIgnored
  private var lastRuntimeRevision: UInt64?

  private(set) var state: AutomationRunState
  private(set) var projection: AutomationOverviewProjection
  private(set) var catalogProjection: AutomationCatalogProjection
  private(set) var runCenterProjection: AutomationRunCenterProjection
  private(set) var refreshState: AutomationRepositoryRefreshState

  init(
    state: AutomationRunState = AutomationRunState(),
    projection: AutomationOverviewProjection = .ownerCFixture(),
    now: @escaping () -> Date = { Date() }
  ) {
    self.state = state
    self.projection = projection
    self.catalogProjection = AutomationCatalogProjection.make(state: state, overview: projection)
    self.runCenterProjection = AutomationRunCenterProjection.make(state: state)
    self.refreshState = .idle
    self.snapshotClient = nil
    self.runtimeHost = nil
    self.runtimeSnapshotLoader = nil
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
    self.catalogProjection = AutomationCatalogProjection.make(
      state: initialState,
      overview: initialProjection
    )
    self.runCenterProjection = AutomationRunCenterProjection.make(state: initialState)
    self.refreshState = .idle
    self.snapshotClient = snapshotClient
    self.runtimeHost = nil
    self.runtimeSnapshotLoader = nil
    self.now = now
  }

  init(
    runtimeHost: LiveAutomationRuntimeHost,
    initialState: AutomationRunState = AutomationRunState(),
    initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(
      from: AutomationRunState()),
    now: @escaping () -> Date = { Date() }
  ) {
    self.state = initialState
    self.projection = initialProjection
    self.catalogProjection = AutomationCatalogProjection.make(
      state: initialState,
      overview: initialProjection
    )
    self.runCenterProjection = AutomationRunCenterProjection.make(state: initialState)
    self.refreshState = .idle
    self.snapshotClient = nil
    self.runtimeHost = runtimeHost
    self.runtimeSnapshotLoader = { await runtimeHost.currentSnapshot() }
    self.now = now
  }

  init(
    runtimeSnapshotLoader: @escaping RuntimeSnapshotLoader,
    initialState: AutomationRunState = AutomationRunState(),
    initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(
      from: AutomationRunState()),
    now: @escaping () -> Date = { Date() }
  ) {
    self.state = initialState
    self.projection = initialProjection
    self.catalogProjection = AutomationCatalogProjection.make(
      state: initialState,
      overview: initialProjection
    )
    self.runCenterProjection = AutomationRunCenterProjection.make(state: initialState)
    self.refreshState = .idle
    self.snapshotClient = nil
    self.runtimeHost = nil
    self.runtimeSnapshotLoader = runtimeSnapshotLoader
    self.now = now
  }

  func startAutoRefresh() {
    pollingTask?.cancel()

    guard runtimeSnapshotLoader != nil else {
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
      publish(snapshot.state)
      refreshState = .loaded(snapshot)
    case .failed(let failure):
      refreshState = .failed(failure, previousSnapshot: previousSnapshot)
    }
  }

  func perform(_ action: AutomationAction) async throws {
    guard let runtimeHost else {
      let result = AutomationReducer.reduce(state: state, action: action)
      publish(result.state)
      return
    }

    publish(try await runtimeHost.dispatch(action))
    if let snapshot = await runtimeHost.currentSnapshot() {
      lastRuntimeRevision = snapshot.revision
    }
  }

  func dispatch(_ action: AutomationAction) async {
    do {
      try await perform(action)
    } catch {
      recordDispatchFailure(error)
    }
  }

  private func recordDispatchFailure(_ error: Error) {
    refreshState = .failed(
      AutomationRepositoryRefreshFailure(
        message: String(describing: error),
        failedAt: now()
      ),
      previousSnapshot: refreshState.snapshot
    )
  }

  func refreshRuntimeState() async {
    guard let runtimeSnapshotLoader else {
      return
    }

    if let snapshot = await runtimeSnapshotLoader() {
      guard lastRuntimeRevision != snapshot.revision else { return }
      lastRuntimeRevision = snapshot.revision
      publish(snapshot.state)
    } else if let snapshot = refreshState.snapshot {
      publish(snapshot.state)
    }
  }

  private func publish(_ state: AutomationRunState) {
    let projection = AutomationViewProjection.overview(from: state)
    self.state = state
    self.projection = projection
    catalogProjection = AutomationCatalogProjection.make(state: state, overview: projection)
    runCenterProjection = AutomationRunCenterProjection.make(state: state)
  }
}

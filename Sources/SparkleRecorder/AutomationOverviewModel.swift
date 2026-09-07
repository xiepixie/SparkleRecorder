import Foundation
import Observation
import SparkleRecorderCore

struct AutomationOverviewProjectionSet: Equatable, Sendable {
  var overview: AutomationOverviewProjection
  var catalog: AutomationCatalogProjection
  var runCenter: AutomationRunCenterProjection

  static func make(state: AutomationRunState) -> AutomationOverviewProjectionSet {
    let overview = AutomationViewProjection.overview(from: state)
    return AutomationOverviewProjectionSet(
      overview: overview,
      catalog: AutomationCatalogProjection.make(state: state, overview: overview),
      runCenter: AutomationRunCenterProjection.make(state: state)
    )
  }

  static func makeDetached(state: AutomationRunState) async -> AutomationOverviewProjectionSet {
    await Task.detached(priority: .userInitiated) {
      make(state: state)
    }.value
  }
}

@MainActor
@Observable
final class AutomationOverviewModel {
  typealias RuntimeSnapshotLoader = @MainActor () async -> AutomationRuntimeSnapshot?
  typealias ProjectionBuilder = @Sendable (AutomationRunState) async -> AutomationOverviewProjectionSet

  @ObservationIgnored
  private let snapshotClient: AutomationRepositorySnapshotClient?
  @ObservationIgnored
  private let runtimeHost: LiveAutomationRuntimeHost?
  @ObservationIgnored
  private let runtimeSnapshotLoader: RuntimeSnapshotLoader?
  @ObservationIgnored
  private let now: () -> Date
  @ObservationIgnored
  private let projectionBuilder: ProjectionBuilder
  @ObservationIgnored
  private var pollingTask: Task<Void, Never>?
  @ObservationIgnored
  private var lastRuntimeRevision: UInt64?
  @ObservationIgnored
  private var workingState: AutomationRunState
  @ObservationIgnored
  private var publishGeneration: UInt64 = 0

  private(set) var state: AutomationRunState
  private(set) var projection: AutomationOverviewProjection
  private(set) var catalogProjection: AutomationCatalogProjection
  private(set) var runCenterProjection: AutomationRunCenterProjection
  private(set) var refreshState: AutomationRepositoryRefreshState

  init(
    state: AutomationRunState = AutomationRunState(),
    projection: AutomationOverviewProjection = .ownerCFixture(),
    now: @escaping () -> Date = { Date() },
    projectionBuilder: @escaping ProjectionBuilder = { state in
      await AutomationOverviewProjectionSet.makeDetached(state: state)
    }
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
    self.projectionBuilder = projectionBuilder
    self.workingState = state
  }

  init(
    snapshotClient: AutomationRepositorySnapshotClient,
    initialState: AutomationRunState = AutomationRunState(),
    initialProjection: AutomationOverviewProjection = .ownerCFixture(),
    now: @escaping () -> Date = { Date() },
    projectionBuilder: @escaping ProjectionBuilder = { state in
      await AutomationOverviewProjectionSet.makeDetached(state: state)
    }
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
    self.projectionBuilder = projectionBuilder
    self.workingState = initialState
  }

  init(
    runtimeHost: LiveAutomationRuntimeHost,
    initialState: AutomationRunState = AutomationRunState(),
    initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(
      from: AutomationRunState()),
    now: @escaping () -> Date = { Date() },
    projectionBuilder: @escaping ProjectionBuilder = { state in
      await AutomationOverviewProjectionSet.makeDetached(state: state)
    }
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
    self.projectionBuilder = projectionBuilder
    self.workingState = initialState
  }

  init(
    runtimeSnapshotLoader: @escaping RuntimeSnapshotLoader,
    initialState: AutomationRunState = AutomationRunState(),
    initialProjection: AutomationOverviewProjection = AutomationViewProjection.overview(
      from: AutomationRunState()),
    now: @escaping () -> Date = { Date() },
    projectionBuilder: @escaping ProjectionBuilder = { state in
      await AutomationOverviewProjectionSet.makeDetached(state: state)
    }
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
    self.projectionBuilder = projectionBuilder
    self.workingState = initialState
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
    let refreshGeneration = publishGeneration
    refreshState = .loading(startedAt: now(), previousSnapshot: previousSnapshot)

    switch await snapshotClient.refresh() {
    case .loaded(let snapshot):
      guard refreshGeneration == publishGeneration else {
        refreshState = previousSnapshot.map(AutomationRepositoryRefreshState.loaded) ?? .idle
        return
      }
      await publish(snapshot.state)
      refreshState = .loaded(snapshot)
    case .failed(let failure):
      refreshState = .failed(failure, previousSnapshot: previousSnapshot)
    }
  }

  func perform(_ action: AutomationAction) async throws {
    guard let runtimeHost else {
      let result = AutomationReducer.reduce(state: workingState, action: action)
      await publish(result.state)
      return
    }

    let dispatchedState = try await runtimeHost.dispatch(action)
    await publish(dispatchedState)
    if let snapshot = await runtimeHost.currentSnapshot() {
      recordRuntimeRevision(snapshot.revision)
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
      if let lastRuntimeRevision, snapshot.revision <= lastRuntimeRevision {
        return
      }
      recordRuntimeRevision(snapshot.revision)
      await publish(snapshot.state)
    } else if let snapshot = refreshState.snapshot {
      await publish(snapshot.state)
    }
  }

  private func recordRuntimeRevision(_ revision: UInt64) {
    lastRuntimeRevision = max(lastRuntimeRevision ?? 0, revision)
  }

  private func publish(_ newState: AutomationRunState) async {
    workingState = newState
    publishGeneration &+= 1
    let generation = publishGeneration
    let refreshed = await projectionBuilder(newState)

    guard generation == publishGeneration else {
      return
    }

    if state != newState {
      state = newState
    }
    if projection != refreshed.overview {
      projection = refreshed.overview
    }
    if catalogProjection != refreshed.catalog {
      catalogProjection = refreshed.catalog
    }
    if runCenterProjection != refreshed.runCenter {
      runCenterProjection = refreshed.runCenter
    }
  }
}

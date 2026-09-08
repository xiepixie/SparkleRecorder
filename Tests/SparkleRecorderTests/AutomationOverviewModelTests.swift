import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Overview Model Tests")
@MainActor
struct AutomationOverviewModelTests {
    @Test("Runtime polling ignores snapshots whose revision has not changed")
    func runtimePollingSkipsUnchangedRevision() async {
        let firstTask = AutomationTask(name: "First", kind: .delay(1))
        let firstWorkflow = AutomationWorkflow(name: "First workflow", tasks: [firstTask])
        let firstState = AutomationRunState(workflows: [firstWorkflow])

        let secondTask = AutomationTask(name: "Second", kind: .delay(2))
        let secondWorkflow = AutomationWorkflow(name: "Second workflow", tasks: [secondTask])
        let secondState = AutomationRunState(workflows: [secondWorkflow])

        var snapshot = AutomationRuntimeSnapshot(state: firstState, revision: 7)
        let model = AutomationOverviewModel(runtimeSnapshotLoader: { snapshot })

        await model.refreshRuntimeState()
        #expect(model.state == firstState)
        let firstProjection = model.projection
        let firstCatalog = model.catalogProjection
        let firstRunCenter = model.runCenterProjection

        snapshot = AutomationRuntimeSnapshot(state: secondState, revision: 7)
        await model.refreshRuntimeState()

        #expect(model.state == firstState)
        #expect(model.projection == firstProjection)
        #expect(model.catalogProjection == firstCatalog)
        #expect(model.runCenterProjection == firstRunCenter)
    }

    @Test("A newer runtime revision with identical state skips projection work")
    func newerRevisionWithIdenticalStateSkipsProjectionWork() async {
        let state = AutomationRunState(
            workflows: [AutomationWorkflow(name: "Stable", tasks: [])]
        )
        var snapshot = AutomationRuntimeSnapshot(state: state, revision: 1)
        let counter = AutomationProjectionBuildCounter()
        let model = AutomationOverviewModel(
            runtimeSnapshotLoader: { snapshot },
            projectionBuilder: { state in
                await counter.recordBuild()
                return AutomationOverviewProjectionSet.make(state: state)
            }
        )

        await model.refreshRuntimeState()
        #expect(await counter.buildCount() == 1)

        snapshot = AutomationRuntimeSnapshot(state: state, revision: 2)
        await model.refreshRuntimeState()

        #expect(await counter.buildCount() == 1)
        #expect(model.state == state)
    }

    @Test("Runtime polling publishes a new revision")
    func runtimePollingPublishesChangedRevision() async {
        let firstState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "First", tasks: [])]
        )
        let secondState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "Second", tasks: [])]
        )

        var snapshot = AutomationRuntimeSnapshot(state: firstState, revision: 1)
        let model = AutomationOverviewModel(runtimeSnapshotLoader: { snapshot })
        await model.refreshRuntimeState()

        snapshot = AutomationRuntimeSnapshot(state: secondState, revision: 2)
        await model.refreshRuntimeState()

        #expect(model.state == secondState)
    }

    @Test("A slower old projection cannot overwrite a newer runtime revision")
    func staleProjectionCannotOverwriteNewerRevision() async {
        let firstState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "First", tasks: [])]
        )
        let secondState = AutomationRunState(
            workflows: [AutomationWorkflow(name: "Second", tasks: [])]
        )
        let gate = AutomationOverviewProjectionBuildGate(blockedWorkflowName: "First")

        var snapshot = AutomationRuntimeSnapshot(state: firstState, revision: 1)
        let model = AutomationOverviewModel(
            runtimeSnapshotLoader: { snapshot },
            projectionBuilder: { state in
                await gate.build(state)
            }
        )

        let firstRefresh = Task { @MainActor in
            await model.refreshRuntimeState()
        }
        await gate.waitUntilBlockedBuildStarts()

        snapshot = AutomationRuntimeSnapshot(state: secondState, revision: 2)
        await model.refreshRuntimeState()
        #expect(model.state == secondState)

        await gate.releaseBlockedBuild()
        await firstRefresh.value

        #expect(model.state == secondState)
        #expect(model.projection.workflows.first?.name == "Second")
    }

    @Test("A stale repository refresh cannot overwrite a newer local edit")
    func staleRepositoryRefreshCannotOverwriteLocalEdit() async {
        let staleWorkflow = AutomationWorkflow(name: "Stale", tasks: [])
        let freshWorkflow = AutomationWorkflow(name: "Fresh", tasks: [])
        let gate = AutomationOverviewRepositoryRefreshGate(
            result: .loaded(
                AutomationRepositorySnapshot(
                    workflows: [staleWorkflow],
                    runHistory: [],
                    refreshedAt: Date(timeIntervalSince1970: 10)
                )
            )
        )
        let model = AutomationOverviewModel(
            snapshotClient: AutomationRepositorySnapshotClient {
                await gate.refresh()
            },
            initialState: AutomationRunState(),
            initialProjection: AutomationViewProjection.overview(from: AutomationRunState())
        )

        let refreshTask = Task { @MainActor in
            await model.refresh()
        }
        await gate.waitUntilRefreshStarts()

        try? await model.perform(.upsertWorkflow(freshWorkflow, at: Date(timeIntervalSince1970: 20)))
        await gate.releaseRefresh()
        await refreshTask.value

        #expect(model.state.workflow(id: freshWorkflow.id) != nil)
        #expect(model.state.workflow(id: staleWorkflow.id) == nil)
    }

    @Test("Concurrent local edits reduce from the latest working state while projections build")
    func concurrentLocalEditsUseLatestWorkingState() async {
        let firstWorkflow = AutomationWorkflow(name: "First", tasks: [])
        let secondWorkflow = AutomationWorkflow(name: "Second", tasks: [])
        let gate = AutomationOverviewProjectionBuildGate(blockedWorkflowName: "First")
        let model = AutomationOverviewModel(
            state: AutomationRunState(),
            projection: AutomationViewProjection.overview(from: AutomationRunState()),
            projectionBuilder: { state in
                await gate.build(state)
            }
        )

        let firstEdit = Task { @MainActor in
            try await model.perform(.upsertWorkflow(firstWorkflow, at: Date(timeIntervalSince1970: 1)))
        }
        await gate.waitUntilBlockedBuildStarts()

        try? await model.perform(.upsertWorkflow(secondWorkflow, at: Date(timeIntervalSince1970: 2)))
        #expect(Set(model.state.workflows.map(\.id)) == Set([firstWorkflow.id, secondWorkflow.id]))

        await gate.releaseBlockedBuild()
        try? await firstEdit.value

        #expect(Set(model.state.workflows.map(\.id)) == Set([firstWorkflow.id, secondWorkflow.id]))
    }
}

private actor AutomationProjectionBuildCounter {
    private var count = 0

    func recordBuild() {
        count += 1
    }

    func buildCount() -> Int {
        count
    }
}

private actor AutomationOverviewRepositoryRefreshGate {
    private let result: AutomationRepositoryRefreshResult
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(result: AutomationRepositoryRefreshResult) {
        self.result = result
    }

    func refresh() async -> AutomationRepositoryRefreshResult {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return result
    }

    func waitUntilRefreshStarts() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseRefresh() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor AutomationOverviewProjectionBuildGate {
    private let blockedWorkflowName: String
    private var didStartBlockedBuild = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(blockedWorkflowName: String) {
        self.blockedWorkflowName = blockedWorkflowName
    }

    func build(_ state: AutomationRunState) async -> AutomationOverviewProjectionSet {
        if state.workflows.contains(where: { $0.name == blockedWorkflowName }) && !didStartBlockedBuild {
            didStartBlockedBuild = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            if !isReleased {
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
            }
        }
        return AutomationOverviewProjectionSet.make(state: state)
    }

    func waitUntilBlockedBuildStarts() async {
        if didStartBlockedBuild {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseBlockedBuild() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

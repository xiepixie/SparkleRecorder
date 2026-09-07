import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Center Model Tests")
@MainActor
struct AutomationRunCenterModelTests {
    @Test("Refresh projects loaded runtime state")
    func refreshProjectsLoadedState() async throws {
        let loadedAt = Date(timeIntervalSince1970: 500)
        let fixture = stateFixture()
        let model = AutomationRunCenterModel(now: { loadedAt }) {
            .loaded(fixture.state)
        }

        await model.refresh()

        #expect(model.loadState == .loaded(at: loadedAt))
        #expect(model.projection.generatedAt == loadedAt)
        #expect(model.projection.executions.count == 1)
        #expect(model.projection.executions.first?.workflowName == "Morning report")
    }

    @Test("Refresh failure preserves the last successful projection as stale data")
    func refreshFailurePreservesProjection() async throws {
        let firstLoadedAt = Date(timeIntervalSince1970: 500)
        let secondLoadedAt = Date(timeIntervalSince1970: 600)
        var currentDate = firstLoadedAt
        var result = AutomationRunCenterLoadResult.loaded(stateFixture().state)
        let model = AutomationRunCenterModel(now: { currentDate }) {
            result
        }

        await model.refresh()
        let loadedProjection = model.projection
        currentDate = secondLoadedAt
        result = .failed("Disk unavailable")
        await model.refresh()

        #expect(model.projection == loadedProjection)
        #expect(model.loadState == .failed(
            message: "Disk unavailable",
            lastLoadedAt: firstLoadedAt
        ))
        #expect(model.loadState.failureMessage == "Disk unavailable")
    }

    @Test("Empty successful refresh is distinct from a load failure")
    func emptyRefreshIsLoaded() async {
        let loadedAt = Date(timeIntervalSince1970: 700)
        let model = AutomationRunCenterModel(now: { loadedAt }) {
            .loaded(AutomationRunState())
        }

        await model.refresh()

        #expect(model.projection.executions.isEmpty)
        #expect(model.loadState == .loaded(at: loadedAt))
        #expect(model.loadState.failureMessage == nil)
    }

    @Test("Silent polling does not publish unchanged projections or refresh timestamps")
    func silentPollingIgnoresUnchangedState() async {
        let firstLoadedAt = Date(timeIntervalSince1970: 700)
        let secondLoadedAt = Date(timeIntervalSince1970: 800)
        var currentDate = firstLoadedAt
        let fixture = stateFixture().state
        let model = AutomationRunCenterModel(now: { currentDate }) {
            .loaded(fixture)
        }

        await model.refresh()
        let firstProjection = model.projection
        currentDate = secondLoadedAt
        await model.refresh(showsLoading: false)

        #expect(model.projection == firstProjection)
        #expect(model.loadState == .loaded(at: firstLoadedAt))
    }

    @Test("A slower silent refresh cannot overwrite a newer runtime snapshot")
    func staleSilentRefreshCannotOverwriteNewerSnapshot() async {
        let oldState = refreshStateFixture(workflowName: "Old")
        let newState = refreshStateFixture(workflowName: "New")
        let gate = AutomationRunCenterRefreshGate(
            oldResult: .loadedVersioned(
                AutomationRuntimeSnapshot(state: oldState, revision: 1)
            ),
            newResult: .loadedVersioned(
                AutomationRuntimeSnapshot(state: newState, revision: 2)
            )
        )
        let model = AutomationRunCenterModel {
            await gate.load()
        }

        let staleRefresh = Task { @MainActor in
            await model.refresh(showsLoading: false)
        }
        await gate.waitUntilOldRefreshStarts()

        await model.refresh(showsLoading: false)
        #expect(model.projection.executions.first?.workflowName == "New")

        await gate.releaseOldRefresh()
        await staleRefresh.value

        #expect(model.projection.executions.first?.workflowName == "New")
    }

    @Test("Versioned polling skips projection work when runtime revision is unchanged")
    func versionedPollingSkipsUnchangedRevision() async {
        let firstLoadedAt = Date(timeIntervalSince1970: 900)
        let secondLoadedAt = Date(timeIntervalSince1970: 1_000)
        var currentDate = firstLoadedAt
        var nowCallCount = 0
        let fixture = stateFixture().state
        let snapshot = AutomationRuntimeSnapshot(state: fixture, revision: 7)
        let model = AutomationRunCenterModel(now: {
            nowCallCount += 1
            return currentDate
        }) {
            .loadedVersioned(snapshot)
        }

        await model.refresh()
        let firstProjection = model.projection
        let callsAfterFirstRefresh = nowCallCount
        currentDate = secondLoadedAt
        await model.refresh(showsLoading: false)

        #expect(model.projection == firstProjection)
        #expect(model.loadState == .loaded(at: firstLoadedAt))
        #expect(nowCallCount == callsAfterFirstRefresh)
    }

    private func refreshStateFixture(workflowName: String) -> AutomationRunState {
        let task = AutomationTask(name: "Step", kind: .delay(1))
        let workflow = AutomationWorkflow(name: workflowName, tasks: [task])
        let createdAt = Date(timeIntervalSince1970: 100)
        let run = AutomationTaskRun(
            workflowID: workflow.id,
            taskID: task.id,
            completedAt: Date(timeIntervalSince1970: 101),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: createdAt
        )
        return AutomationRunState(workflows: [workflow], runs: [run], now: createdAt)
    }

    private func stateFixture() -> (state: AutomationRunState, workflow: AutomationWorkflow) {
        let task = AutomationTask(name: "Export", kind: .delay(1))
        let workflow = AutomationWorkflow(name: "Morning report", tasks: [task])
        let startedAt = Date(timeIntervalSince1970: 100)
        let run = AutomationTaskRun(
            workflowID: workflow.id,
            taskID: task.id,
            actualStartTime: startedAt,
            completedAt: Date(timeIntervalSince1970: 105),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: startedAt
        )
        return (
            AutomationRunState(workflows: [workflow], runs: [run], now: startedAt),
            workflow
        )
    }
}

private actor AutomationRunCenterRefreshGate {
    private let oldResult: AutomationRunCenterLoadResult
    private let newResult: AutomationRunCenterLoadResult
    private var loadCount = 0
    private var oldRefreshStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var oldReleaseContinuation: CheckedContinuation<Void, Never>?
    private var oldRefreshReleased = false

    init(
        oldResult: AutomationRunCenterLoadResult,
        newResult: AutomationRunCenterLoadResult
    ) {
        self.oldResult = oldResult
        self.newResult = newResult
    }

    func load() async -> AutomationRunCenterLoadResult {
        loadCount += 1
        if loadCount == 1 {
            oldRefreshStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            if !oldRefreshReleased {
                await withCheckedContinuation { continuation in
                    oldReleaseContinuation = continuation
                }
            }
            return oldResult
        }
        return newResult
    }

    func waitUntilOldRefreshStarts() async {
        if oldRefreshStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseOldRefresh() {
        oldRefreshReleased = true
        oldReleaseContinuation?.resume()
        oldReleaseContinuation = nil
    }
}

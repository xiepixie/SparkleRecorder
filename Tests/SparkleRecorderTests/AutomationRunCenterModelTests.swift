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

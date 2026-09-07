import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Resource Timeline Run Selection Tests")
struct AutomationResourceTimelineRunSelectionTests {
    @Test("Active execution keeps its completed upstream context and hides old history")
    func activeExecutionKeepsContext() {
        let workflowID = UUID()
        let taskID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let historicalExecutionID = UUID()
        let activeExecutionID = UUID()

        let historical = AutomationTaskRun(
            executionID: historicalExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base,
            completedAt: base.addingTimeInterval(1),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base
        )
        let completedUpstream = AutomationTaskRun(
            executionID: activeExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base.addingTimeInterval(10),
            completedAt: base.addingTimeInterval(11),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base.addingTimeInterval(10)
        )
        let running = AutomationTaskRun(
            executionID: activeExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base.addingTimeInterval(12),
            status: .running,
            createdAt: base.addingTimeInterval(12),
            upstreamRunIDs: [completedUpstream.id]
        )

        let selected = AutomationResourceTimelineRunSelection.currentContextRuns(
            from: [historical, completedUpstream, running]
        )

        #expect(selected.map(\.id) == [completedUpstream.id, running.id])
    }

    @Test("All simultaneous active executions remain visible")
    func simultaneousActiveExecutionsRemainVisible() {
        let workflowID = UUID()
        let taskID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let firstExecutionID = UUID()
        let secondExecutionID = UUID()
        let oldExecutionID = UUID()

        let old = AutomationTaskRun(
            executionID: oldExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            completedAt: base,
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base
        )
        let firstActive = AutomationTaskRun(
            executionID: firstExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            status: .waitingForResource,
            createdAt: base.addingTimeInterval(10)
        )
        let secondActive = AutomationTaskRun(
            executionID: secondExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            status: .planned,
            createdAt: base.addingTimeInterval(20)
        )

        let selected = AutomationResourceTimelineRunSelection.currentContextRuns(
            from: [old, firstActive, secondActive]
        )

        #expect(Set(selected.map(\.executionID)) == [firstExecutionID, secondExecutionID])
        #expect(selected.count == 2)
    }

    @Test("Without active work the latest completed execution is the timeline context")
    func latestCompletedExecutionIsFallback() {
        let workflowID = UUID()
        let taskID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let olderExecutionID = UUID()
        let latestExecutionID = UUID()

        let older = AutomationTaskRun(
            executionID: olderExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            completedAt: base.addingTimeInterval(10),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base
        )
        let latestFirstAttempt = AutomationTaskRun(
            executionID: latestExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            completedAt: base.addingTimeInterval(20),
            status: .completed,
            outcome: .timedOut(deadline: nil),
            createdAt: base.addingTimeInterval(19)
        )
        let latestRetry = AutomationTaskRun(
            executionID: latestExecutionID,
            workflowID: workflowID,
            taskID: taskID,
            completedAt: base.addingTimeInterval(30),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base.addingTimeInterval(29),
            attempt: 2
        )

        let selected = AutomationResourceTimelineRunSelection.currentContextRuns(
            from: [older, latestFirstAttempt, latestRetry]
        )

        #expect(selected.map(\.id) == [latestFirstAttempt.id, latestRetry.id])
    }

    @Test("Each workflow chooses its own current execution context")
    func selectionIsIndependentPerWorkflow() {
        let firstWorkflowID = UUID()
        let secondWorkflowID = UUID()
        let taskID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let firstOld = AutomationTaskRun(
            executionID: UUID(),
            workflowID: firstWorkflowID,
            taskID: taskID,
            completedAt: base,
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base
        )
        let firstActive = AutomationTaskRun(
            executionID: UUID(),
            workflowID: firstWorkflowID,
            taskID: taskID,
            status: .queued,
            createdAt: base.addingTimeInterval(10)
        )
        let secondOlder = AutomationTaskRun(
            executionID: UUID(),
            workflowID: secondWorkflowID,
            taskID: taskID,
            completedAt: base.addingTimeInterval(5),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base.addingTimeInterval(5)
        )
        let secondLatest = AutomationTaskRun(
            executionID: UUID(),
            workflowID: secondWorkflowID,
            taskID: taskID,
            completedAt: base.addingTimeInterval(15),
            status: .completed,
            outcome: .cancelled(reason: nil),
            createdAt: base.addingTimeInterval(15)
        )

        let selected = AutomationResourceTimelineRunSelection.currentContextRuns(
            from: [firstOld, firstActive, secondOlder, secondLatest]
        )

        #expect(Set(selected.map(\.id)) == [firstActive.id, secondLatest.id])
    }
}

import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Task Run History Presentation Tests")
struct AutomationTaskRunHistoryPresentationTests {
    @Test("Large task history keeps only recent presentation rows and selected evidence")
    func largeHistoryKeepsBoundedRecentRows() throws {
        let workflowID = UUID()
        let taskID = UUID()
        let executionID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var runs: [AutomationTaskRun] = []
        runs.reserveCapacity(10_002)

        var selectedOldRunID: UUID?
        for index in 0..<10_000 {
            let run = AutomationTaskRun(
                executionID: UUID(),
                workflowID: workflowID,
                taskID: taskID,
                actualStartTime: base.addingTimeInterval(TimeInterval(index)),
                completedAt: base.addingTimeInterval(TimeInterval(index) + 0.5),
                status: .completed,
                outcome: .succeeded(report: nil),
                createdAt: base.addingTimeInterval(TimeInterval(index))
            )
            if index == 42 {
                selectedOldRunID = run.id
            }
            runs.append(run)
        }

        let earlierAttempt = AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base.addingTimeInterval(20_000),
            completedAt: base.addingTimeInterval(20_001),
            status: .completed,
            outcome: .failed(report: nil),
            createdAt: base.addingTimeInterval(20_000),
            attempt: 1
        )
        let activeRetry = AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base.addingTimeInterval(20_002),
            status: .running,
            createdAt: base.addingTimeInterval(20_002),
            attempt: 2
        )
        runs.append(earlierAttempt)
        runs.append(activeRetry)

        let resolvedSelectedOldRunID = try #require(selectedOldRunID)
        let presentation = AutomationTaskRunHistoryPresentation.make(
            runs: runs,
            workflowID: workflowID,
            taskID: taskID,
            initialSelectedRunID: resolvedSelectedOldRunID
        )

        #expect(presentation.totalCount == 10_002)
        #expect(presentation.recentRuns.count == 5)
        #expect(presentation.recentRuns.first?.id == activeRetry.id)
        #expect(presentation.activeRunID == activeRetry.id)
        #expect(presentation.initialSelectedRun?.id == resolvedSelectedOldRunID)
        #expect(presentation.run(id: resolvedSelectedOldRunID)?.id == resolvedSelectedOldRunID)
        #expect(presentation.hasLaterAttempt(after: earlierAttempt))
        #expect(!presentation.hasLaterAttempt(after: activeRetry))
    }

    @Test("History selection stays isolated to one workflow task")
    func selectionIsIsolatedByWorkflowTask() {
        let workflowID = UUID()
        let taskID = UUID()
        let otherWorkflowID = UUID()
        let otherTaskID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_100_000)

        let matching = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            actualStartTime: base,
            status: .running,
            createdAt: base
        )
        let otherTask = AutomationTaskRun(
            workflowID: workflowID,
            taskID: otherTaskID,
            actualStartTime: base.addingTimeInterval(10),
            status: .running,
            createdAt: base.addingTimeInterval(10)
        )
        let otherWorkflow = AutomationTaskRun(
            workflowID: otherWorkflowID,
            taskID: taskID,
            actualStartTime: base.addingTimeInterval(20),
            status: .running,
            createdAt: base.addingTimeInterval(20)
        )

        let presentation = AutomationTaskRunHistoryPresentation.make(
            runs: [otherTask, matching, otherWorkflow],
            workflowID: workflowID,
            taskID: taskID
        )

        #expect(presentation.totalCount == 1)
        #expect(presentation.recentRuns.map(\.id) == [matching.id])
        #expect(presentation.activeRunID == matching.id)
    }
}

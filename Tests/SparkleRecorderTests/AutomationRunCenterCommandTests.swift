import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Center Command Tests")
struct AutomationRunCenterCommandTests {
    @Test("Running execution command cancels every active run")
    func runningExecutionCancelsAllActiveRuns() throws {
        let fixture = execution(
            status: .running,
            recommendedAction: .waitOrCancel,
            runs: [activeRun(), activeRun(), completedRun()]
        )

        let command = try #require(AutomationRunCenterCommandResolver.primaryCommand(for: fixture))
        guard case .cancelExecution(let runIDs) = command else {
            Issue.record("Expected cancellation command")
            return
        }

        #expect(runIDs == fixture.runs.prefix(2).map(\.id))
    }

    @Test("Semantic recovery actions map to concrete app-edge commands")
    func semanticActionsMapToCommands() {
        let workflowID = UUID()
        let taskID = UUID()
        let run = completedRun(workflowID: workflowID, taskID: taskID)
        let failure = AutomationRunFailureFocus(
            runID: run.id,
            taskID: taskID,
            taskName: "Failed step",
            macroID: nil,
            attempt: 1,
            failedEventIndex: nil,
            evidenceID: nil,
            outcome: .failed(report: nil)
        )

        #expect(AutomationRunCenterCommandResolver.primaryCommand(for: execution(
            workflowID: workflowID,
            status: .needsAttention,
            recommendedAction: .grantPermission(.screenRecording),
            runs: [run],
            failureFocus: failure
        )) == .openPermission(.screenRecording))
        #expect(AutomationRunCenterCommandResolver.primaryCommand(for: execution(
            workflowID: workflowID,
            status: .needsAttention,
            recommendedAction: .retryExecution,
            runs: [run],
            failureFocus: failure
        )) == .retryWorkflow(workflowID: workflowID))
        #expect(AutomationRunCenterCommandResolver.primaryCommand(for: execution(
            workflowID: workflowID,
            status: .needsAttention,
            recommendedAction: .repairStorage,
            runs: [run],
            failureFocus: failure
        )) == .openRunHistorySettings)
        #expect(AutomationRunCenterCommandResolver.primaryCommand(for: execution(
            workflowID: workflowID,
            status: .needsAttention,
            recommendedAction: .adjustTimeout,
            runs: [run],
            failureFocus: failure
        )) == .openWorkflow(workflowID: workflowID, taskID: taskID))
    }

    private func execution(
        workflowID: UUID = UUID(),
        status: AutomationExecutionDisplayStatus,
        recommendedAction: AutomationRunRecommendedAction,
        runs: [AutomationTaskRun],
        failureFocus: AutomationRunFailureFocus? = nil
    ) -> AutomationExecutionProjection {
        AutomationExecutionProjection(
            executionID: UUID(),
            workflowID: workflowID,
            workflowName: "Workflow",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1),
            latestActivityAt: Date(timeIntervalSince1970: 2),
            taskRunCount: runs.count,
            completedRunCount: runs.count(where: \.isTerminal),
            attemptCount: runs.count,
            hasEvidence: false,
            hasActiveRun: runs.contains { !$0.isTerminal },
            failureFocus: failureFocus,
            recommendedAction: recommendedAction,
            runs: runs
        )
    }

    private func activeRun() -> AutomationTaskRun {
        AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func completedRun(
        workflowID: UUID = UUID(),
        taskID: UUID = UUID()
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            completedAt: Date(timeIntervalSince1970: 2),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}

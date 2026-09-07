import Foundation
import Testing

@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Center Deletion Confirmation Tests")
struct AutomationRunCenterDeletionConfirmationTests {
  @Test("Deletion confirmation resolves its execution from command run IDs and freezes storage context")
  func resolvesCommandExecutionAndFreezesContext() throws {
    let workflowID = UUID()
    let taskID = UUID()
    let executionAID = UUID()
    let executionBID = UUID()
    let runA1 = AutomationTaskRun(
      id: UUID(),
      executionID: executionAID,
      workflowID: workflowID,
      taskID: taskID
    )
    let runA2 = AutomationTaskRun(
      id: UUID(),
      executionID: executionAID,
      workflowID: workflowID,
      taskID: taskID
    )
    let runB = AutomationTaskRun(
      id: UUID(),
      executionID: executionBID,
      workflowID: workflowID,
      taskID: taskID
    )
    let executionA = execution(
      id: executionAID,
      workflowID: workflowID,
      runs: [runA1, runA2]
    )
    let executionB = execution(
      id: executionBID,
      workflowID: workflowID,
      runs: [runB]
    )
    let projection = AutomationRunCenterProjection(
      generatedAt: Date(timeIntervalSince1970: 10),
      summary: AutomationRunCenterSummary(totalCount: 2),
      executions: [executionB, executionA]
    )
    let originalBreakdown = AutomationRunStorageBreakdown(
      reportByteCount: 40,
      screenshotByteCount: 120,
      conditionEvidenceByteCount: 30,
      otherEvidenceByteCount: 10
    )
    var storageUsage = AutomationRunStorageUsage(
      breakdown: originalBreakdown,
      historyByteCount: 50,
      runCount: 3,
      executionBreakdowns: [executionAID: originalBreakdown]
    )
    let command = AutomationRunCenterCommand.deleteExecution(
      runIDs: Set([runA1.id, runA2.id]),
      scope: .history
    )

    let confirmation = try #require(
      AutomationRunCenterDeletionConfirmation.make(
        command: command,
        projection: projection,
        storageUsage: storageUsage
      )
    )

    #expect(confirmation.executionID == executionAID)
    #expect(confirmation.runCount == 2)
    #expect(confirmation.scope == .history)
    #expect(confirmation.command == command)
    #expect(confirmation.storage == originalBreakdown)

    storageUsage.executionBreakdowns[executionAID] = AutomationRunStorageBreakdown(
      screenshotByteCount: 999
    )
    #expect(confirmation.storage == originalBreakdown)
  }

  @Test("Deletion confirmation rejects stale or non-deletion commands")
  func rejectsCommandsWithoutExactExecution() {
    let workflowID = UUID()
    let taskID = UUID()
    let executionID = UUID()
    let run = AutomationTaskRun(
      id: UUID(),
      executionID: executionID,
      workflowID: workflowID,
      taskID: taskID
    )
    let projection = AutomationRunCenterProjection(
      generatedAt: Date(timeIntervalSince1970: 20),
      summary: AutomationRunCenterSummary(totalCount: 1),
      executions: [execution(id: executionID, workflowID: workflowID, runs: [run])]
    )

    #expect(
      AutomationRunCenterDeletionConfirmation.make(
        command: .deleteExecution(runIDs: Set([UUID()]), scope: .history),
        projection: projection,
        storageUsage: nil
      ) == nil
    )
    #expect(
      AutomationRunCenterDeletionConfirmation.make(
        command: .retryWorkflow(workflowID: workflowID),
        projection: projection,
        storageUsage: nil
      ) == nil
    )
  }

  private func execution(
    id: UUID,
    workflowID: UUID,
    runs: [AutomationTaskRun]
  ) -> AutomationExecutionProjection {
    AutomationExecutionProjection(
      executionID: id,
      workflowID: workflowID,
      workflowName: "Workflow",
      status: .succeeded,
      createdAt: Date(timeIntervalSince1970: 0),
      latestActivityAt: Date(timeIntervalSince1970: 1),
      taskRunCount: runs.count,
      completedRunCount: runs.count,
      attemptCount: runs.count,
      hasEvidence: true,
      hasActiveRun: false,
      failureFocus: nil,
      recommendedAction: .none,
      runs: runs
    )
  }
}

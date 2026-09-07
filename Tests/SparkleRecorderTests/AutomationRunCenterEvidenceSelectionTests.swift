import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Center Evidence Selection Tests")
struct AutomationRunCenterEvidenceSelectionTests {
  @Test("Evidence selection resolves the run from command identity instead of live selection")
  func resolvesExactRunFromCommandIdentity() throws {
    let workflowAID = UUID()
    let workflowBID = UUID()
    let taskAID = UUID()
    let taskBID = UUID()
    let runA = AutomationTaskRun(
      workflowID: workflowAID,
      taskID: taskAID,
      status: .completed,
      outcome: .failed(report: nil)
    )
    let runB = AutomationTaskRun(
      workflowID: workflowBID,
      taskID: taskBID,
      status: .completed,
      outcome: .failed(report: nil)
    )
    let projection = AutomationRunCenterProjection(
      generatedAt: Date(timeIntervalSince1970: 1),
      summary: AutomationRunCenterSummary(totalCount: 2),
      executions: [
        execution(run: runA, workflowName: "A", taskName: "Task A"),
        execution(run: runB, workflowName: "B", taskName: "Task B")
      ]
    )

    let selection = try #require(
      AutomationRunCenterEvidenceSelection.make(
        command: .inspectEvidence(runID: runB.id, failedEventIndex: 4),
        projection: projection
      )
    )

    #expect(selection.run.id == runB.id)
    #expect(selection.taskName == "Task B")
    #expect(selection.failedEventIndex == 4)
  }

  @Test("Evidence selection only uses failure task name when the failure focus belongs to that run")
  func ignoresUnrelatedFailureTaskName() throws {
    let workflowID = UUID()
    let failureRun = AutomationTaskRun(
      workflowID: workflowID,
      taskID: UUID(),
      status: .completed,
      outcome: .failed(report: nil)
    )
    let evidenceRun = AutomationTaskRun(
      workflowID: workflowID,
      taskID: UUID(),
      status: .completed,
      outcome: .succeeded(report: nil)
    )
    let execution = AutomationExecutionProjection(
      executionID: failureRun.executionID,
      workflowID: workflowID,
      workflowName: "Flow",
      status: .needsAttention,
      createdAt: Date(timeIntervalSince1970: 1),
      latestActivityAt: Date(timeIntervalSince1970: 2),
      taskRunCount: 2,
      completedRunCount: 2,
      attemptCount: 1,
      hasEvidence: true,
      hasActiveRun: false,
      failureFocus: AutomationRunFailureFocus(
        runID: failureRun.id,
        taskID: failureRun.taskID,
        taskName: "Failed task",
        macroID: nil,
        attempt: 1,
        failedEventIndex: 2,
        evidenceID: failureRun.evidenceID,
        outcome: .failed(report: nil)
      ),
      recommendedAction: .none,
      runs: [failureRun, evidenceRun]
    )
    let projection = AutomationRunCenterProjection(
      generatedAt: Date(timeIntervalSince1970: 3),
      summary: AutomationRunCenterSummary(totalCount: 1),
      executions: [execution]
    )

    let selection = try #require(
      AutomationRunCenterEvidenceSelection.make(
        command: .inspectEvidence(runID: evidenceRun.id, failedEventIndex: nil),
        projection: projection
      )
    )

    #expect(selection.run.id == evidenceRun.id)
    #expect(selection.taskName == nil)
  }

  @Test("Evidence selection rejects stale run identities and unrelated commands")
  func rejectsStaleAndUnrelatedCommands() {
    let projection = AutomationRunCenterProjection(
      generatedAt: Date(timeIntervalSince1970: 1),
      summary: AutomationRunCenterSummary(),
      executions: []
    )

    #expect(
      AutomationRunCenterEvidenceSelection.make(
        command: .inspectEvidence(runID: UUID(), failedEventIndex: nil),
        projection: projection
      ) == nil
    )
    #expect(
      AutomationRunCenterEvidenceSelection.make(
        command: .openRunHistorySettings,
        projection: projection
      ) == nil
    )
  }

  private func execution(
    run: AutomationTaskRun,
    workflowName: String,
    taskName: String
  ) -> AutomationExecutionProjection {
    AutomationExecutionProjection(
      executionID: run.executionID,
      workflowID: run.workflowID,
      workflowName: workflowName,
      status: .needsAttention,
      createdAt: run.createdAt,
      latestActivityAt: run.completedAt ?? run.createdAt,
      taskRunCount: 1,
      completedRunCount: 1,
      attemptCount: 1,
      hasEvidence: true,
      hasActiveRun: false,
      failureFocus: AutomationRunFailureFocus(
        runID: run.id,
        taskID: run.taskID,
        taskName: taskName,
        macroID: run.macroID,
        attempt: run.attempt,
        failedEventIndex: nil,
        evidenceID: run.evidenceID,
        outcome: run.outcome ?? .failed(report: nil)
      ),
      recommendedAction: .none,
      runs: [run]
    )
  }
}

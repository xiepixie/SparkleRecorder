import Foundation
import SparkleRecorderCore

struct AutomationRunCenterEvidenceSelection: Identifiable, Equatable, Sendable {
  let run: AutomationTaskRun
  let taskName: String?
  let failedEventIndex: Int?

  var id: UUID { run.id }

  static func make(
    command: AutomationRunCenterCommand,
    projection: AutomationRunCenterProjection
  ) -> AutomationRunCenterEvidenceSelection? {
    guard case .inspectEvidence(let runID, let failedEventIndex) = command else {
      return nil
    }

    for execution in projection.executions {
      guard let run = execution.runs.first(where: { $0.id == runID }) else {
        continue
      }
      let taskName = execution.failureFocus.flatMap { failure in
        failure.runID == runID ? failure.taskName : nil
      }
      return AutomationRunCenterEvidenceSelection(
        run: run,
        taskName: taskName,
        failedEventIndex: failedEventIndex
      )
    }

    return nil
  }
}

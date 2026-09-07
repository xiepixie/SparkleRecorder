import Foundation
import SparkleRecorderCore

struct AutomationRunCenterDeletionConfirmation: Equatable, Sendable {
  var command: AutomationRunCenterCommand
  var executionID: UUID
  var runCount: Int
  var scope: AutomationRunManualDeletionScope
  var storage: AutomationRunStorageBreakdown?

  static func make(
    command: AutomationRunCenterCommand,
    projection: AutomationRunCenterProjection,
    storageUsage: AutomationRunStorageUsage?
  ) -> AutomationRunCenterDeletionConfirmation? {
    guard case .deleteExecution(let runIDs, let scope) = command,
      !runIDs.isEmpty,
      let execution = projection.executions.first(where: { execution in
        Set(execution.runs.map(\.id)) == runIDs
      })
    else {
      return nil
    }

    return AutomationRunCenterDeletionConfirmation(
      command: command,
      executionID: execution.executionID,
      runCount: execution.runs.count,
      scope: scope,
      storage: storageUsage.map { $0.breakdown(for: execution.executionID) }
    )
  }
}

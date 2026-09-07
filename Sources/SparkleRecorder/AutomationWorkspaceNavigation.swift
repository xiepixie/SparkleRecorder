import Foundation
import SparkleRecorderCore

struct AutomationWorkspaceNavigationResolution: Equatable {
  var workflowID: UUID
  var selection: AutomationAuthoringSelection
}

enum AutomationWorkspaceNavigation {
  static func resolve(
    _ destination: AutomationWorkspaceDestination,
    workflows: [AutomationWorkflow]
  ) -> AutomationWorkspaceNavigationResolution? {
    guard let workflow = workflows.first(where: { $0.id == destination.workflowID }) else {
      return nil
    }

    let selection: AutomationAuthoringSelection
    if let taskID = destination.taskID,
      workflow.tasks.contains(where: { $0.id == taskID })
    {
      selection = .task(taskID)
    } else {
      selection = .workflow
    }

    return AutomationWorkspaceNavigationResolution(
      workflowID: workflow.id,
      selection: selection
    )
  }
}

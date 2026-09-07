import SparkleRecorderCore
import SwiftUI

struct AutomationTaskFlowEditorView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let graphPosition: AutomationGraphPoint?
    let taskProjection: AutomationTaskNodeProjection?
    @Binding var executionDraft: AutomationTaskExecutionDraft
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void
    let onMoveTask: (AutomationGraphPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isConditionTask {
                AutomationTaskBranchPanelView(
                    workflow: workflow,
                    task: task,
                    dependencyEdges: dependencyEdges,
                    onSelectTask: onSelectTask,
                    onSelectDependency: onSelectDependency,
                    onAction: onAction
                )
            }

            AutomationTaskDependencyAuthoringView(
                workflow: workflow,
                task: task,
                onSelectTask: onSelectTask,
                onSelectDependency: onSelectDependency,
                onAction: onAction
            )

            AutomationTaskJoinPolicyEditorView(
                selection: $executionDraft.joinPolicy,
                incomingDependencyCount: taskProjection?.incomingDependencyCount
                    ?? workflow.dependencies(to: task.id).count
            )
            .padding(.vertical, 8)

            if let graphPosition {
                AutomationTaskPositionControlView(
                    position: graphPosition,
                    onMove: onMoveTask
                )
            }
        }
    }

    private var isConditionTask: Bool {
        if case .condition = task.kind {
            return true
        }
        return false
    }
}

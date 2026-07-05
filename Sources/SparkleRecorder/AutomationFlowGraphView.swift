import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphView: View {
    let workflow: AutomationWorkflowProjection
    let selectedTaskID: UUID?
    let selectedDependencyID: UUID?
    let pendingDependencySourceID: UUID?
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onStartDependency: (UUID) -> Void
    let onCompleteDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void
    var now: () -> Date = { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        AutomationSectionHeader(
                            title: NSLocalizedString("FLOWGRAPH", comment: ""),
                            count: workflow.edges.count
                        )

                        if pendingDependencySourceID != nil {
                            Label(NSLocalizedString("Linking", comment: ""), systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(Brand.sigAmber)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .glassSurface(cornerRadius: 7, tint: Brand.sigAmber, interactive: false)
                        }
                    }
                    Text(workflow.name)
                        .font(.headline)
                    Text(String(format: NSLocalizedString("%d tasks", comment: ""), workflow.nodes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    AutomationFlowGraphEdgeCanvas(edges: workflow.edges)
                        .frame(
                            width: CGFloat(workflow.graphSize.width),
                            height: CGFloat(workflow.graphSize.height)
                        )

                    AutomationFlowGraphEdgeListView(
                        edges: workflow.edges,
                        selectedDependencyID: selectedDependencyID,
                        onSelectDependency: onSelectDependency
                    )

                    ForEach(workflow.nodes) { node in
                        AutomationFlowGraphNodeView(
                            node: node,
                            size: workflow.nodeSize,
                            isSelected: selectedTaskID == node.taskID,
                            isConnectionSource: pendingDependencySourceID == node.taskID,
                            canCompleteConnection: pendingDependencySourceID != nil && pendingDependencySourceID != node.taskID,
                            onSelect: {
                                onSelectTask(node.taskID)
                            },
                            onRun: {
                                let intent = AutomationViewIntent.startTask(
                                    workflowID: workflow.id,
                                    taskID: node.taskID
                                )
                                onAction(intent.reducerAction(at: now()))
                            },
                            onCancelRun: { runID in
                                onAction(.cancelRun(runID: runID, at: now()))
                            },
                            onConnect: {
                                if pendingDependencySourceID != nil && pendingDependencySourceID != node.taskID {
                                    onCompleteDependency(node.taskID)
                                } else {
                                    onStartDependency(node.taskID)
                                }
                            },
                            onMoveEnded: { position in
                                let intent = AutomationViewIntent.moveTask(
                                    workflowID: workflow.id,
                                    taskID: node.taskID,
                                    position: position
                                )
                                onAction(intent.reducerAction(at: now()))
                            }
                        )
                            .offset(x: CGFloat(node.position.x), y: CGFloat(node.position.y))
                    }
                }
                .frame(
                    width: CGFloat(workflow.graphSize.width),
                    height: CGFloat(workflow.graphSize.height),
                    alignment: .topLeading
                )
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
    }
}

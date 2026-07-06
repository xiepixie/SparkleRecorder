import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphView: View {
    let workflow: AutomationWorkflowProjection
    let selectedTaskID: UUID?
    let selectedDependencyID: UUID?
    let pendingDependencySourceID: UUID?
    let pendingDependencyTrigger: AutomationDependencyTriggerDraft
    let linkPreview: AutomationFlowGraphLinkPreviewState?
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onDeleteDependency: (UUID) -> Void
    let onStartDependency: (UUID) -> Void
    let onCompleteDependency: (UUID) -> Void
    let onSetPendingDependencyTrigger: (AutomationDependencyTriggerDraft) -> Void
    let onCancelDependency: () -> Void
    let onMacroDropped: (SavedMacro) -> Void
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
                            AutomationFlowGraphLinkingToolbar(
                                trigger: pendingDependencyTrigger,
                                onSetTrigger: onSetPendingDependencyTrigger,
                                onCancel: onCancelDependency
                            )
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

                    if let linkPreview,
                       let start = linkPreviewStart(for: linkPreview) {
                        AutomationFlowGraphLinkPreview(
                            start: start,
                            end: linkPreview.end
                        )
                            .frame(
                                width: CGFloat(workflow.graphSize.width),
                                height: CGFloat(workflow.graphSize.height)
                            )
                    }

                    AutomationFlowGraphEdgeListView(
                        edges: workflow.edges,
                        selectedDependencyID: selectedDependencyID,
                        onSelectDependency: onSelectDependency,
                        onDeleteDependency: onDeleteDependency
                    )

                    ForEach(workflow.nodes) { node in
                        nodeView(for: node)
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

    private func nodeView(for node: AutomationTaskNodeProjection) -> some View {
        AutomationFlowGraphNodeView(
            node: node,
            size: workflow.nodeSize,
            isSelected: selectedTaskID == node.taskID,
            isConnectionSource: pendingDependencySourceID == node.taskID,
            canCompleteConnection: canCompleteConnection(to: node.taskID),
            connectionTriggerTitle: pendingDependencyTrigger.title,
            onSelect: {
                onSelectTask(node.taskID)
            },
            onRun: {
                startTask(node.taskID)
            },
            onCancelRun: { runID in
                cancelRun(runID)
            },
            onConnect: {
                connect(to: node.taskID)
            },
            isDragging: false
        )
        .offset(x: CGFloat(node.position.x), y: CGFloat(node.position.y))
    }

    private func linkPreviewStart(for preview: AutomationFlowGraphLinkPreviewState) -> AutomationGraphPoint? {
        guard let node = workflow.nodes.first(where: { $0.taskID == preview.sourceTaskID }) else {
            return nil
        }

        return AutomationGraphPoint(
            x: node.position.x + workflow.nodeSize.width,
            y: node.position.y + (workflow.nodeSize.height / 2)
        )
    }

    private func canCompleteConnection(to taskID: UUID) -> Bool {
        pendingDependencySourceID != nil && pendingDependencySourceID != taskID
    }

    private func connect(to taskID: UUID) {
        if canCompleteConnection(to: taskID) {
            onCompleteDependency(taskID)
        } else {
            onStartDependency(taskID)
        }
    }

    private func startTask(_ taskID: UUID) {
        let intent = AutomationViewIntent.startTask(
            workflowID: workflow.id,
            taskID: taskID
        )
        onAction(intent.reducerAction(at: now()))
    }

    private func cancelRun(_ runID: UUID) {
        onAction(.cancelRun(runID: runID, at: now()))
    }

}

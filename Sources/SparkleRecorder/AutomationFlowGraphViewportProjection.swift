import Foundation
import SparkleRecorderCore

struct AutomationFlowGraphViewportProjection {
    static let cullingThreshold = 80
    static let prefetchMargin: CGFloat = 320

    static func shouldCull(nodeCount: Int, voiceOverEnabled: Bool) -> Bool {
        nodeCount >= cullingThreshold && !voiceOverEnabled
    }

    static func visibleNodes(
        workflow: AutomationWorkflowProjection,
        visibleRect: CGRect?,
        retainedTaskIDs: Set<UUID>,
        cullingEnabled: Bool
    ) -> [AutomationTaskNodeProjection] {
        guard cullingEnabled, let visibleRect else {
            return workflow.nodes
        }

        let expanded = visibleRect.insetBy(dx: -prefetchMargin, dy: -prefetchMargin)
        return workflow.nodes.filter { node in
            if retainedTaskIDs.contains(node.taskID) {
                return true
            }
            let frame = CGRect(
                x: node.position.x,
                y: node.position.y,
                width: workflow.nodeSize.width,
                height: workflow.nodeSize.height
            )
            return frame.intersects(expanded)
        }
    }

    static func visibleEdges(
        _ edges: [AutomationDependencyEdgeProjection],
        visibleNodes: [AutomationTaskNodeProjection],
        visibleRect: CGRect?,
        retainedDependencyIDs: Set<UUID>,
        cullingEnabled: Bool
    ) -> [AutomationDependencyEdgeProjection] {
        guard cullingEnabled, let visibleRect else {
            return edges
        }

        let visibleTaskIDs = Set(visibleNodes.map(\.taskID))
        let expanded = visibleRect.insetBy(dx: -prefetchMargin, dy: -prefetchMargin)
        return edges.filter { edge in
            if retainedDependencyIDs.contains(edge.id)
                || visibleTaskIDs.contains(edge.fromTaskID)
                || visibleTaskIDs.contains(edge.toTaskID)
            {
                return true
            }

            let controlDistance = max(42, abs(edge.end.x - edge.start.x) * 0.45)
            let firstControlX = edge.start.x + controlDistance
            let secondControlX = edge.end.x - controlDistance
            let minX = min(min(edge.start.x, edge.end.x), min(firstControlX, secondControlX))
            let maxX = max(max(edge.start.x, edge.end.x), max(firstControlX, secondControlX))
            let minY = min(edge.start.y, edge.end.y)
            let maxY = max(edge.start.y, edge.end.y)
            return CGRect(
                x: minX,
                y: minY,
                width: max(1, maxX - minX),
                height: max(1, maxY - minY)
            ).intersects(expanded)
        }
    }
}

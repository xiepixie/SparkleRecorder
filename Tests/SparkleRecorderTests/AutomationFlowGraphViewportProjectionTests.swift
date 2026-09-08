import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Flow Graph Viewport Projection Tests")
struct AutomationFlowGraphViewportProjectionTests {
    @Test("Small graphs stay fully materialized")
    func smallGraphsDoNotCull() {
        #expect(
            AutomationFlowGraphViewportProjection.shouldCull(
                nodeCount: 10,
                voiceOverEnabled: false
            ) == false
        )
    }

    @Test("Large graphs cull outside the viewport while retaining selected tasks")
    func largeGraphsCullOutsideViewport() throws {
        let workflow = makeWorkflowProjection(nodeCount: 100)
        let retainedID = try #require(workflow.nodes.last?.taskID)
        let visibleRect = CGRect(x: 0, y: 0, width: 620, height: 420)

        let visibleNodes = AutomationFlowGraphViewportProjection.visibleNodes(
            workflow: workflow,
            visibleRect: visibleRect,
            retainedTaskIDs: [retainedID],
            cullingEnabled: true
        )
        let visibleEdges = AutomationFlowGraphViewportProjection.visibleEdges(
            workflow.edges,
            visibleNodes: visibleNodes,
            visibleRect: visibleRect,
            retainedDependencyIDs: [],
            cullingEnabled: true
        )

        #expect(visibleNodes.count < workflow.nodes.count)
        #expect(visibleNodes.contains { $0.taskID == retainedID })
        #expect(visibleEdges.count < workflow.edges.count)
    }

    @Test("Five hundred node graph keeps a bounded viewport working set")
    func fiveHundredNodeGraphKeepsBoundedWorkingSet() {
        let workflow = makeWorkflowProjection(nodeCount: 500)
        let visibleNodes = AutomationFlowGraphViewportProjection.visibleNodes(
            workflow: workflow,
            visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            retainedTaskIDs: [],
            cullingEnabled: true
        )

        #expect(visibleNodes.count < 20)
    }

    @Test("VoiceOver disables graph culling")
    func voiceOverDisablesCulling() {
        #expect(
            AutomationFlowGraphViewportProjection.shouldCull(
                nodeCount: 500,
                voiceOverEnabled: true
            ) == false
        )
    }

    private func makeWorkflowProjection(nodeCount: Int) -> AutomationWorkflowProjection {
        let workflowID = UUID()
        let nodeSize = AutomationGraphSize(width: 204, height: 124)
        let nodes = (0..<nodeCount).map { index in
            AutomationTaskNodeProjection(
                workflowID: workflowID,
                taskID: UUID(),
                title: "Task \(index)",
                kindLabel: "Delay",
                scheduleLabel: "Manual",
                resourceLabel: "None",
                status: .scheduled,
                statusDetail: "",
                hasEvidence: false,
                position: AutomationGraphPoint(x: Double(index) * 300, y: 32)
            )
        }
        let edges = zip(nodes, nodes.dropFirst()).map { left, right in
            AutomationDependencyEdgeProjection(
                id: UUID(),
                fromTaskID: left.taskID,
                toTaskID: right.taskID,
                triggerLabel: "Success",
                delayLabel: "No delay",
                status: .pending,
                start: AutomationGraphPoint(
                    x: left.position.x + nodeSize.width,
                    y: left.position.y + nodeSize.height / 2
                ),
                end: AutomationGraphPoint(
                    x: right.position.x,
                    y: right.position.y + nodeSize.height / 2
                )
            )
        }

        return AutomationWorkflowProjection(
            id: workflowID,
            name: "Large graph",
            status: .scheduled,
            statusDetail: "",
            nodes: nodes,
            edges: edges,
            graphSize: AutomationGraphSize(
                width: Double(max(1, nodeCount)) * 300 + nodeSize.width,
                height: 480
            ),
            nodeSize: nodeSize
        )
    }
}

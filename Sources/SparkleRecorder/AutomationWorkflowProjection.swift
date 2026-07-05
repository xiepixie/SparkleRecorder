import Foundation

public struct AutomationWorkflowProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nodes: [AutomationTaskNodeProjection]
    public var edges: [AutomationDependencyEdgeProjection]
    public var graphSize: AutomationGraphSize
    public var nodeSize: AutomationGraphSize

    public init(
        id: UUID,
        name: String,
        nodes: [AutomationTaskNodeProjection],
        edges: [AutomationDependencyEdgeProjection],
        graphSize: AutomationGraphSize,
        nodeSize: AutomationGraphSize
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.edges = edges
        self.graphSize = graphSize
        self.nodeSize = nodeSize
    }
}

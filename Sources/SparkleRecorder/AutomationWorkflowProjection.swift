import Foundation

public struct AutomationWorkflowProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var status: AutomationDisplayStatus
    public var statusDetail: String
    public var nextScheduledOccurrence: Date?
    public var nextScheduledTaskID: UUID?
    public var nodes: [AutomationTaskNodeProjection]
    public var edges: [AutomationDependencyEdgeProjection]
    public var graphSize: AutomationGraphSize
    public var nodeSize: AutomationGraphSize

    public init(
        id: UUID,
        name: String,
        status: AutomationDisplayStatus,
        statusDetail: String,
        nextScheduledOccurrence: Date? = nil,
        nextScheduledTaskID: UUID? = nil,
        nodes: [AutomationTaskNodeProjection],
        edges: [AutomationDependencyEdgeProjection],
        graphSize: AutomationGraphSize,
        nodeSize: AutomationGraphSize
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.statusDetail = statusDetail
        self.nextScheduledOccurrence = nextScheduledOccurrence
        self.nextScheduledTaskID = nextScheduledTaskID
        self.nodes = nodes
        self.edges = edges
        self.graphSize = graphSize
        self.nodeSize = nodeSize
    }
}

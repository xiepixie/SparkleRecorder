import Foundation

public struct AutomationTaskNodeProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { taskID }

    public var workflowID: UUID
    public var taskID: UUID
    public var runID: UUID?
    public var title: String
    public var kindLabel: String
    public var scheduleLabel: String
    public var resourceLabel: String
    public var status: AutomationDisplayStatus
    public var statusDetail: String
    public var hasEvidence: Bool
    public var position: AutomationGraphPoint

    public init(
        workflowID: UUID,
        taskID: UUID,
        runID: UUID? = nil,
        title: String,
        kindLabel: String,
        scheduleLabel: String,
        resourceLabel: String,
        status: AutomationDisplayStatus,
        statusDetail: String,
        hasEvidence: Bool,
        position: AutomationGraphPoint
    ) {
        self.workflowID = workflowID
        self.taskID = taskID
        self.runID = runID
        self.title = title
        self.kindLabel = kindLabel
        self.scheduleLabel = scheduleLabel
        self.resourceLabel = resourceLabel
        self.status = status
        self.statusDetail = statusDetail
        self.hasEvidence = hasEvidence
        self.position = position
    }
}

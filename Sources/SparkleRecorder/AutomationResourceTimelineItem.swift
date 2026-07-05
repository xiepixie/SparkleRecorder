import Foundation

public struct AutomationResourceTimelineItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var runID: UUID
    public var title: String
    public var lane: AutomationResourceTimelineLane
    public var status: AutomationDisplayStatus
    public var resourceLabel: String
    public var startedAt: Date?
    public var completedAt: Date?
    public var hasEvidence: Bool

    public init(
        id: UUID = UUID(),
        workflowID: UUID,
        taskID: UUID,
        runID: UUID,
        title: String,
        lane: AutomationResourceTimelineLane,
        status: AutomationDisplayStatus,
        resourceLabel: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        hasEvidence: Bool
    ) {
        self.id = id
        self.workflowID = workflowID
        self.taskID = taskID
        self.runID = runID
        self.title = title
        self.lane = lane
        self.status = status
        self.resourceLabel = resourceLabel
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.hasEvidence = hasEvidence
    }
}

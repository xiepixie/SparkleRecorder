import Foundation

public struct AutomationOverviewProjection: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var workflows: [AutomationWorkflowProjection]
    public var timelineItems: [AutomationResourceTimelineItem]
    public var statusCounts: [AutomationStatusCount]

    public init(
        generatedAt: Date,
        workflows: [AutomationWorkflowProjection],
        timelineItems: [AutomationResourceTimelineItem],
        statusCounts: [AutomationStatusCount]
    ) {
        self.generatedAt = generatedAt
        self.workflows = workflows
        self.timelineItems = timelineItems
        self.statusCounts = statusCounts
    }
}

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
    public var resourceKeys: [String]?
    public var kindLabel: String?
    public var statusDetail: String?
    public var scheduledAt: Date?
    public var earliestStartAt: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var createdAt: Date?
    public var resourceWaiting: AutomationResourceWaitingProjection?
    public var timeoutCountdown: AutomationTimeoutCountdownProjection?
    public var retryAttemptSummary: AutomationRetryAttemptSummary?
    public var conditionProgress: AutomationConditionProgressProjection?
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
        resourceKeys: [String]? = nil,
        kindLabel: String? = nil,
        statusDetail: String? = nil,
        scheduledAt: Date? = nil,
        earliestStartAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        createdAt: Date? = nil,
        resourceWaiting: AutomationResourceWaitingProjection? = nil,
        timeoutCountdown: AutomationTimeoutCountdownProjection? = nil,
        retryAttemptSummary: AutomationRetryAttemptSummary? = nil,
        conditionProgress: AutomationConditionProgressProjection? = nil,
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
        self.resourceKeys = resourceKeys?.isEmpty == true ? nil : resourceKeys
        self.kindLabel = kindLabel
        self.statusDetail = statusDetail
        self.scheduledAt = scheduledAt
        self.earliestStartAt = earliestStartAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.resourceWaiting = resourceWaiting
        self.timeoutCountdown = timeoutCountdown
        self.retryAttemptSummary = retryAttemptSummary
        self.conditionProgress = conditionProgress
        self.hasEvidence = hasEvidence
    }
}

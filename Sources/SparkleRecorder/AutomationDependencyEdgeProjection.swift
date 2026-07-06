import Foundation

public struct AutomationBranchDecisionProjection: Codable, Equatable, Sendable {
    public var sourceRunID: UUID
    public var targetRunID: UUID?
    public var executionID: UUID
    public var decidedAt: Date?
    public var status: AutomationBranchDecisionStatus
    public var outcomeLabel: String
    public var detail: String

    public init(
        sourceRunID: UUID,
        targetRunID: UUID? = nil,
        executionID: UUID,
        decidedAt: Date? = nil,
        status: AutomationBranchDecisionStatus,
        outcomeLabel: String,
        detail: String
    ) {
        self.sourceRunID = sourceRunID
        self.targetRunID = targetRunID
        self.executionID = executionID
        self.decidedAt = decidedAt
        self.status = status
        self.outcomeLabel = outcomeLabel
        self.detail = detail
    }
}

public struct AutomationDependencyEdgeProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var triggerLabel: String
    public var delayLabel: String
    public var status: AutomationDependencyDisplayStatus
    public var branchDecision: AutomationBranchDecisionProjection?
    public var start: AutomationGraphPoint
    public var end: AutomationGraphPoint

    public init(
        id: UUID,
        fromTaskID: UUID,
        toTaskID: UUID,
        triggerLabel: String,
        delayLabel: String,
        status: AutomationDependencyDisplayStatus,
        branchDecision: AutomationBranchDecisionProjection? = nil,
        start: AutomationGraphPoint,
        end: AutomationGraphPoint
    ) {
        self.id = id
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.triggerLabel = triggerLabel
        self.delayLabel = delayLabel
        self.status = status
        self.branchDecision = branchDecision
        self.start = start
        self.end = end
    }
}

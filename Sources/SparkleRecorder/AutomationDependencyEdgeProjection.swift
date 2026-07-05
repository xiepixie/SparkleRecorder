import Foundation

public struct AutomationDependencyEdgeProjection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var triggerLabel: String
    public var delayLabel: String
    public var status: AutomationDependencyDisplayStatus
    public var start: AutomationGraphPoint
    public var end: AutomationGraphPoint

    public init(
        id: UUID,
        fromTaskID: UUID,
        toTaskID: UUID,
        triggerLabel: String,
        delayLabel: String,
        status: AutomationDependencyDisplayStatus,
        start: AutomationGraphPoint,
        end: AutomationGraphPoint
    ) {
        self.id = id
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.triggerLabel = triggerLabel
        self.delayLabel = delayLabel
        self.status = status
        self.start = start
        self.end = end
    }
}

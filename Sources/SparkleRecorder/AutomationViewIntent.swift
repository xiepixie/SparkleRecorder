import Foundation

public enum AutomationViewIntent: Codable, Equatable, Sendable {
    case startTask(workflowID: UUID, taskID: UUID)
    case moveTask(workflowID: UUID, taskID: UUID, position: AutomationGraphPoint)

    public func reducerAction(at date: Date) -> AutomationAction {
        switch self {
        case .startTask(let workflowID, let taskID):
            return .manualStart(workflowID: workflowID, taskID: taskID, requestedAt: date)
        case .moveTask(let workflowID, let taskID, let position):
            return .moveTask(workflowID: workflowID, taskID: taskID, position: position, at: date)
        }
    }
}

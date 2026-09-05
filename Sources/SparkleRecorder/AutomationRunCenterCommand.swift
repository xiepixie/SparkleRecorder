import Foundation
import SparkleRecorderCore

enum AutomationRunCenterCommand: Equatable, Sendable {
    case inspectEvidence(runID: UUID, failedEventIndex: Int?)
    case cancelExecution(runIDs: [UUID])
    case retryWorkflow(workflowID: UUID)
    case openPermission(AutomationPermission)
    case openWorkflow(workflowID: UUID, taskID: UUID?)
    case openRunHistorySettings
    case deleteExecution(runIDs: Set<UUID>, scope: AutomationRunManualDeletionScope)
}

struct AutomationRunCenterCommandFeedback: Equatable, Sendable {
    var message: String
    var isError: Bool
    var dismissesRunCenter: Bool

    init(message: String, isError: Bool = false, dismissesRunCenter: Bool = false) {
        self.message = message
        self.isError = isError
        self.dismissesRunCenter = dismissesRunCenter
    }
}

enum AutomationRunCenterCommandResolver {
    static func primaryCommand(
        for execution: AutomationExecutionProjection
    ) -> AutomationRunCenterCommand? {
        switch execution.recommendedAction {
        case .waitOrCancel:
            let activeRunIDs = execution.runs.filter { !$0.isTerminal }.map(\.id)
            return activeRunIDs.isEmpty ? nil : .cancelExecution(runIDs: activeRunIDs)

        case .grantPermission(let permission):
            return .openPermission(permission)

        case .inspectFailedEvent(_, let eventIndex, _):
            guard let runID = execution.failureFocus?.runID else { return nil }
            return .inspectEvidence(runID: runID, failedEventIndex: eventIndex)

        case .inspectEvidence(let evidenceID):
            guard let runID = execution.runs.first(where: { $0.evidenceID == evidenceID })?.id else {
                return nil
            }
            return .inspectEvidence(runID: runID, failedEventIndex: nil)

        case .retryExecution:
            return .retryWorkflow(workflowID: execution.workflowID)

        case .repairStorage:
            return .openRunHistorySettings

        case .restoreMacro, .inspectTargetApplication, .adjustTimeout,
             .adjustResourcePolicy, .reviewCancellation:
            return .openWorkflow(
                workflowID: execution.workflowID,
                taskID: execution.failureFocus?.taskID
            )

        case .none:
            return nil
        }
    }

    static func title(for command: AutomationRunCenterCommand) -> String {
        switch command {
        case .inspectEvidence(_, let failedEventIndex):
            return failedEventIndex == nil
                ? String(localized: "Review Evidence", table: "Automation")
                : String(localized: "Review Failure", table: "Automation")
        case .cancelExecution:
            return String(localized: "Cancel Run", table: "Automation")
        case .retryWorkflow:
            return String(localized: "Run Again", table: "Automation")
        case .openPermission:
            return String(localized: "Open System Settings", table: "Common")
        case .openWorkflow:
            return String(localized: "Open Workflow", table: "Automation")
        case .openRunHistorySettings:
            return String(localized: "Open Run History Settings", table: "Automation")
        case .deleteExecution(_, let scope):
            switch scope {
            case .screenshots: return String(localized: "Delete Screenshots", table: "Automation")
            case .evidence: return String(localized: "Delete Evidence", table: "Automation")
            case .history: return String(localized: "Delete Run History", table: "Automation")
            }
        }
    }

    static func systemImage(for command: AutomationRunCenterCommand) -> String {
        switch command {
        case .inspectEvidence: return "doc.text.magnifyingglass"
        case .cancelExecution: return "stop.circle"
        case .retryWorkflow: return "arrow.clockwise"
        case .openPermission: return "gear"
        case .openWorkflow: return "arrow.up.right.square"
        case .openRunHistorySettings: return "externaldrive.badge.exclamationmark"
        case .deleteExecution(_, let scope):
            return scope == .screenshots ? "photo.badge.minus" : "trash"
        }
    }
}

import Foundation
import SparkleRecorderCore

enum AutomationWorkflowDraftIssuePresentation {
    static func message(for issue: AutomationWorkflowDraftIssue) -> String {
        message(code: issue.code.rawValue, rawMessage: issue.message)
    }

    static func message(for row: AutomationWorkflowDraftPreviewProjection.IssueRow) -> String {
        message(code: row.code, rawMessage: row.message)
    }

    static func message(code: String, rawMessage: String) -> String {
        guard let code = AutomationWorkflowDraftIssueCode(rawValue: code) else {
            return rawMessage
        }

        switch code {
        case .unsupportedSchema:
            return String(localized: "This draft uses an unsupported workflow format.", table: "Automation")
        case .emptyWorkflowName:
            return String(localized: "Give the workflow a name.", table: "Automation")
        case .emptyTaskKey:
            return String(localized: "A task is missing its key.", table: "Automation")
        case .duplicateTaskKey:
            return String(localized: "A task key is used more than once.", table: "Automation")
        case .unsupportedTaskType:
            return String(localized: "This task type is not supported.", table: "Automation")
        case .missingMacroRef:
            return String(localized: "Choose a macro for this task.", table: "Automation")
        case .ambiguousMacroRef:
            return String(localized: "This macro reference matches more than one macro.", table: "Automation")
        case .missingDelayDuration:
            return String(localized: "Set a delay duration.", table: "Automation")
        case .invalidDuration:
            return String(localized: "Enter a valid duration greater than zero.", table: "Automation")
        case .missingCondition:
            return String(localized: "Configure a condition for this task.", table: "Automation")
        case .unsupportedConditionType:
            return String(localized: "This condition type is not supported.", table: "Automation")
        case .missingConditionText:
            return String(localized: "Enter the screen text to wait for.", table: "Automation")
        case .missingNotificationTitle:
            return String(localized: "Enter a notification title.", table: "Automation")
        case .missingDependencyEndpoint:
            return String(localized: "Choose both ends of this dependency.", table: "Automation")
        case .selfDependency:
            return String(localized: "A task cannot depend on itself.", table: "Automation")
        case .unsupportedTrigger:
            return String(localized: "This dependency trigger is not supported.", table: "Automation")
        case .duplicateDependency:
            return String(localized: "This dependency is already defined.", table: "Automation")
        case .cycleDetected:
            return String(localized: "This dependency would create a cycle.", table: "Automation")
        case .missingTimeoutBranch:
            return String(localized: "Add a timeout branch for this condition.", table: "Automation")
        case .invalidSchedule:
            return String(localized: "Review this task's schedule settings.", table: "Automation")
        case .invalidRetry:
            return String(localized: "Review this task's retry settings.", table: "Automation")
        case .invalidJoinPolicy:
            return String(localized: "Review this task's join policy.", table: "Automation")
        case .invalidTargetApplicationPolicy:
            return String(localized: "Review the target application policy.", table: "Automation")
        case .invalidTargetApplicationCleanupPolicy:
            return String(localized: "Review the target application cleanup policy.", table: "Automation")
        case .invalidMissedRunPolicy:
            return String(localized: "Review the missed-run policy.", table: "Automation")
        case .invalidLoop:
            return String(localized: "Review the loop settings.", table: "Automation")
        case .missingVisualReference:
            return String(localized: "Choose the visual reference required by this condition.", table: "Automation")
        case .missingPixel:
            return String(localized: "Pick a target pixel.", table: "Automation")
        case .invalidThreshold:
            return String(localized: "Enter a threshold between 0 and 1.", table: "Automation")
        case .invalidPixelSampleRadius:
            return String(localized: "Enter a valid pixel sample radius.", table: "Automation")
        case .invalidColor:
            return String(localized: "Choose a valid target color.", table: "Automation")
        case .unresolvedRegionRef:
            return String(localized: "This region reference could not be resolved.", table: "Automation")
        case .duplicateVisualAssetKey:
            return String(localized: "A visual asset key is used more than once.", table: "Automation")
        case .invalidVisualAsset:
            return String(localized: "Review this visual asset.", table: "Automation")
        case .missingVisualAsset:
            return String(localized: "A referenced visual asset is missing.", table: "Automation")
        case .lossyWorkflowExport:
            return String(localized: "Some workflow settings cannot be represented in this draft format.", table: "Automation")
        case .unsupportedNotificationSeverity:
            return String(localized: "This notification severity is not supported.", table: "Automation")
        case .internalWorkflowValidationFailed:
            return String(localized: "The compiled workflow did not pass validation.", table: "Automation")
        }
    }
}

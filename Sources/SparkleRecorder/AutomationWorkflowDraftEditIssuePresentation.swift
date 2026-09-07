import Foundation
import SparkleRecorderCore

enum AutomationWorkflowDraftEditIssuePresentation {
    static func message(for error: Error) -> String {
        guard let editError = error as? AutomationWorkflowDraftEditError else {
            return String(
                localized: "The draft could not be updated. Review the edit and try again.",
                table: "Automation"
            )
        }
        return message(for: editError)
    }

    static func message(for error: AutomationWorkflowDraftEditError) -> String {
        switch error.code {
        case AutomationWorkflowDraftIssueCode.missingDependencyEndpoint.rawValue:
            return String(localized: "Choose valid tasks for both ends of this dependency.", table: "Automation")
        case AutomationWorkflowDraftIssueCode.duplicateDependency.rawValue:
            return String(localized: "This dependency is already defined.", table: "Automation")
        case AutomationWorkflowDraftIssueCode.unsupportedTrigger.rawValue:
            return String(localized: "Choose a valid trigger for this dependency.", table: "Automation")
        case "missingTask":
            return String(localized: "The selected task is no longer in this draft.", table: "Automation")
        case "missingDependencySelector":
            return String(localized: "Choose a dependency before editing it.", table: "Automation")
        case "missingDependency":
            return String(localized: "The selected dependency is no longer in this draft.", table: "Automation")
        case "ambiguousDependency":
            return String(localized: "More than one dependency matches this edit. Choose one specific dependency.", table: "Automation")
        case "unsupportedPatchOperation":
            return String(localized: "This draft patch contains an unsupported change.", table: "Automation")
        case "missingPatchField":
            return String(localized: "This draft patch is missing information required for the change.", table: "Automation")
        default:
            if AutomationWorkflowDraftIssueCode(rawValue: error.code) != nil {
                return AutomationWorkflowDraftIssuePresentation.message(
                    code: error.code,
                    rawMessage: error.message
                )
            }
            return String(
                localized: "The draft could not be updated. Review the edit and try again.",
                table: "Automation"
            )
        }
    }
}

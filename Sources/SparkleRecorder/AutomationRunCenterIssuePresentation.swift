import Foundation
import SparkleRecorderCore

struct AutomationRunCenterIssuePresentation: Equatable {
    let detail: String
}

enum AutomationRunCenterIssuePresenter {
    static func persistenceIssue(
        _ issue: AutomationPersistenceIssue
    ) -> AutomationRunCenterIssuePresentation {
        let detail: String
        switch issue.operation {
        case .workflows:
            detail = String(
                localized: "Workflow changes could not be saved. Check available disk space and file permissions, then try again.",
                table: "Automation"
            )
        case .runCheckpoint:
            detail = String(
                localized: "Run progress could not be saved. Check available disk space and file permissions before running again.",
                table: "Automation"
            )
        }
        return AutomationRunCenterIssuePresentation(detail: detail)
    }

    static func loadFailure(
        _ diagnosticMessage: String
    ) -> AutomationRunCenterIssuePresentation {
        _ = diagnosticMessage
        return AutomationRunCenterIssuePresentation(
            detail: String(
                localized: "Run history could not be refreshed. Try again in a moment.",
                table: "Automation"
            )
        )
    }
}

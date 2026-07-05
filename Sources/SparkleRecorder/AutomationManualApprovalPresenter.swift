import AppKit
import Foundation
import SparkleRecorderCore

enum AutomationManualApprovalPresenter {
    static func client() -> AutomationManualApprovalClient {
        AutomationManualApprovalClient { request in
            await MainActor.run {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = request.condition.name
                alert.informativeText = String(
                    format: NSLocalizedString("Approve automation task \"%@\"?", comment: ""),
                    taskName(for: request)
                )
                alert.addButton(withTitle: NSLocalizedString("Approve", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Reject", comment: ""))
                return alert.runModal() == .alertFirstButtonReturn
            }
        }
    }

    private static func taskName(for request: AutomationConditionEvaluationRequest) -> String {
        request.condition.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
                    format: String(localized: "Approve automation task \"%@\"?", table: "Common"),
                    taskName(for: request)
                )
                alert.addButton(withTitle: String(localized: "Approve", table: "Common"))
                alert.addButton(withTitle: String(localized: "Reject", table: "Common"))
                return alert.runModal() == .alertFirstButtonReturn
            }
        }
    }

    private static func taskName(for request: AutomationConditionEvaluationRequest) -> String {
        request.condition.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

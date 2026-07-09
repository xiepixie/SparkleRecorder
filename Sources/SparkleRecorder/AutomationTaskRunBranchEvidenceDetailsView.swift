import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunBranchEvidenceDetailsView: View {
    let evidence: AutomationBranchDecisionEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AutomationTaskRunDetailRowView(
                title: String(localized: "Dependency", table: "Automation"),
                value: shortID(evidence.dependencyID)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Trigger", table: "Automation"),
                value: triggerLabel
            )
            if evidence.delay > 0 {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Delay", table: "EditorUX"),
                    value: durationLabel(evidence.delay)
                )
            }
            if let targetJoinPolicy = evidence.targetJoinPolicy {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Target join", table: "Common"),
                    value: joinPolicyLabel(for: targetJoinPolicy)
                )
            }
            if let targetRunID = evidence.targetRunID {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Target run", table: "Common"),
                    value: shortID(targetRunID)
                )
            } else if evidence.status == .triggered {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Target run", table: "Common"),
                    value: String(localized: "Waiting for join policy", table: "Common")
                )
            }
        }
        .padding(.top, 2)
    }

    private var triggerLabel: String {
        switch evidence.trigger {
        case .onSuccess:
            return String(localized: "On success", table: "Common")
        case .onFailure:
            return String(localized: "On failure", table: "Common")
        case .onTimeout:
            return String(localized: "On timeout", table: "Common")
        case .onCancelled:
            return String(localized: "On cancel", table: "Common")
        case .onConditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .onConditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .onOutcome(let predicate):
            return predicateLabel(for: predicate)
        case .always:
            return String(localized: "Always", table: "Common")
        }
    }

    private func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            return String(localized: "Success", table: "Common")
        case .failure:
            return String(localized: "Failure", table: "Common")
        case .timeout:
            return String(localized: "Timeout", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .anyTerminal:
            return String(localized: "Any terminal outcome", table: "Common")
        }
    }

    private func joinPolicyLabel(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return String(localized: "All incoming branches", table: "Common")
        case .any:
            return String(localized: "Any incoming branch", table: "Common")
        case .firstMatched:
            return String(localized: "First matching branch", table: "Common")
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        if duration < 10 {
            return String(format: String(localized: "%.1fs", table: "Common"), duration)
        }
        return String(format: String(localized: "%.0fs", table: "Common"), duration.rounded())
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

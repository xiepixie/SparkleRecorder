import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunBranchEvidenceDetailsView: View {
    let evidence: AutomationBranchDecisionEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Dependency", comment: ""),
                value: shortID(evidence.dependencyID)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Trigger", comment: ""),
                value: triggerLabel
            )
            if evidence.delay > 0 {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Delay", comment: ""),
                    value: durationLabel(evidence.delay)
                )
            }
            if let targetJoinPolicy = evidence.targetJoinPolicy {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Target join", comment: ""),
                    value: joinPolicyLabel(for: targetJoinPolicy)
                )
            }
            if let targetRunID = evidence.targetRunID {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Target run", comment: ""),
                    value: shortID(targetRunID)
                )
            } else if evidence.status == .triggered {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Target run", comment: ""),
                    value: NSLocalizedString("Waiting for join policy", comment: "")
                )
            }
        }
        .padding(.top, 2)
    }

    private var triggerLabel: String {
        switch evidence.trigger {
        case .onSuccess:
            return NSLocalizedString("On success", comment: "")
        case .onFailure:
            return NSLocalizedString("On failure", comment: "")
        case .onTimeout:
            return NSLocalizedString("On timeout", comment: "")
        case .onCancelled:
            return NSLocalizedString("On cancel", comment: "")
        case .onConditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .onConditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .onOutcome(let predicate):
            return predicateLabel(for: predicate)
        case .always:
            return NSLocalizedString("Always", comment: "")
        }
    }

    private func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            return NSLocalizedString("Success", comment: "")
        case .failure:
            return NSLocalizedString("Failure", comment: "")
        case .timeout:
            return NSLocalizedString("Timeout", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .anyTerminal:
            return NSLocalizedString("Any terminal outcome", comment: "")
        }
    }

    private func joinPolicyLabel(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return NSLocalizedString("All incoming branches", comment: "")
        case .any:
            return NSLocalizedString("Any incoming branch", comment: "")
        case .firstMatched:
            return NSLocalizedString("First matching branch", comment: "")
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        if duration < 10 {
            return String(format: NSLocalizedString("%.1fs", comment: ""), duration)
        }
        return String(format: NSLocalizedString("%.0fs", comment: ""), duration.rounded())
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

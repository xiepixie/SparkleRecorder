import SwiftUI
import SparkleRecorderCore

struct AutomationTaskJoinPolicyEditorView: View {
    @Binding var selection: AutomationJoinPolicy
    let incomingDependencyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(NSLocalizedString("Join policy", comment: ""), systemImage: "arrow.triangle.merge")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Picker(NSLocalizedString("Join policy", comment: ""), selection: $selection) {
                    ForEach(policyOptions, id: \.self) { policy in
                        Text(title(for: policy)).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 172)
            }

            HStack(spacing: 6) {
                Text(title(for: selection))
                    .font(.caption)
                    .bold()

                if incomingDependencyCount > 0 {
                    Text(incomingCountLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(detail(for: selection))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var policyOptions: [AutomationJoinPolicy] {
        [.all, .any, .firstMatched]
    }

    private var incomingCountLabel: String {
        String(
            format: NSLocalizedString("%d incoming", comment: ""),
            incomingDependencyCount
        )
    }

    private var accessibilityText: String {
        if incomingDependencyCount > 0 {
            return String(
                format: NSLocalizedString("Join policy, %@, %@", comment: ""),
                title(for: selection),
                incomingCountLabel
            )
        }
        return String(
            format: NSLocalizedString("Join policy, %@", comment: ""),
            title(for: selection)
        )
    }

    private func title(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return NSLocalizedString("All incoming branches", comment: "")
        case .any:
            return NSLocalizedString("Any incoming branch", comment: "")
        case .firstMatched:
            return NSLocalizedString("First matching branch", comment: "")
        }
    }

    private func detail(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return NSLocalizedString("Run after every incoming branch for this task is satisfied.", comment: "")
        case .any:
            return NSLocalizedString("Run as soon as one incoming branch is ready.", comment: "")
        case .firstMatched:
            return NSLocalizedString("Lock onto the first incoming branch that matches and ignore later matches for this run.", comment: "")
        }
    }
}

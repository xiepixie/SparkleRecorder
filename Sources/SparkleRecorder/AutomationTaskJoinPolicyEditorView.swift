import SwiftUI
import SparkleRecorderCore

struct AutomationTaskJoinPolicyEditorView: View {
    @Binding var selection: AutomationJoinPolicy
    let incomingDependencyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(String(localized: "Join policy", table: "Common"), systemImage: "arrow.triangle.merge")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Picker(String(localized: "Join policy", table: "Common"), selection: $selection) {
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
            format: String(localized: "%d incoming", table: "Common"),
            incomingDependencyCount
        )
    }

    private var accessibilityText: String {
        if incomingDependencyCount > 0 {
            return String(
                format: String(localized: "Join policy, %@, %@", table: "Common"),
                title(for: selection),
                incomingCountLabel
            )
        }
        return String(
            format: String(localized: "Join policy, %@", table: "Common"),
            title(for: selection)
        )
    }

    private func title(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return String(localized: "All incoming branches", table: "Common")
        case .any:
            return String(localized: "Any incoming branch", table: "Common")
        case .firstMatched:
            return String(localized: "First matching branch", table: "Common")
        }
    }

    private func detail(for policy: AutomationJoinPolicy) -> String {
        switch policy {
        case .all:
            return String(localized: "Run after every incoming branch for this task is satisfied.", table: "Common")
        case .any:
            return String(localized: "Run as soon as one incoming branch is ready.", table: "Common")
        case .firstMatched:
            return String(localized: "Lock onto the first incoming branch that matches and ignore later matches for this run.", table: "Common")
        }
    }
}

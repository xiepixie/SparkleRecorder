import SwiftUI
import SparkleRecorderCore

struct AutomationJoinPolicyBadgeView: View {
    let policy: AutomationJoinPolicy
    let label: String
    let incomingDependencyCount: Int

    var body: some View {
        Label {
            Text(label)
                .lineLimit(1)
        } icon: {
            Image(systemName: "arrow.triangle.merge")
                .accessibilityHidden(true)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tint.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
                )
        )
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        switch policy {
        case .all:
            return .secondary
        case .any:
            return Brand.libraryBlue
        case .firstMatched:
            return Brand.sigAmber
        }
    }

    private var helpText: String {
        if incomingDependencyCount > 1 {
            return String(
                format: String(localized: "%@ across %d incoming branches", table: "Common"),
                label,
                incomingDependencyCount
            )
        }
        return label
    }

    private var accessibilityText: String {
        if incomingDependencyCount > 1 {
            return String(
                format: String(localized: "Join policy: %@, %d incoming branches", table: "Common"),
                label,
                incomingDependencyCount
            )
        }
        return String(format: String(localized: "Join policy: %@", table: "Common"), label)
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphEdgeLabelView: View {
    let edge: AutomationDependencyEdgeProjection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .accessibilityHidden(true)

            Text(edge.triggerLabel)
                .lineLimit(1)

            if showsDelay {
                Text(edge.delayLabel)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let decisionLabel {
                Text(decisionLabel)
                    .foregroundStyle(edge.status.tint)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(edge.status.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .automationSubsurface(
            cornerRadius: 7,
            tint: edge.status.tint,
            isActive: isSelected
        )
    }

    private var showsDelay: Bool {
        edge.delayLabel != String(localized: "No delay", table: "EditorUX")
    }

    private var decisionLabel: String? {
        guard let decision = edge.branchDecision else {
            return nil
        }

        switch decision.status {
        case .triggered, .skipped:
            return decision.status.label
        case .waiting, .disabled:
            return nil
        }
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphBranchGuideView: View {
    let sourceTitle: String
    let edges: [AutomationDependencyEdgeProjection]
    let targetTitles: [UUID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Branch", table: "Common"), systemImage: "arrow.triangle.branch")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ForEach(edges) { edge in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Capsule()
                        .fill(edge.status.tint.opacity(0.72))
                        .frame(width: 4, height: 13)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(branchTitle(for: edge.triggerLabel))
                            .font(.caption)
                            .bold()
                            .foregroundStyle(edge.status.tint)
                            .lineLimit(1)

                        Text(targetTitle(for: edge))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let detail = triggerDetail(for: edge) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 176, alignment: .leading)
        .automationSubsurface(cornerRadius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func targetTitle(for edge: AutomationDependencyEdgeProjection) -> String {
        targetTitles[edge.toTaskID] ?? String(localized: "Missing task", table: "Automation")
    }

    private func branchTitle(for triggerLabel: String) -> String {
        if isThenTrigger(triggerLabel) {
            return String(localized: "Then", table: "Common")
        }
        if isElseTrigger(triggerLabel) {
            return String(localized: "Else", table: "Common")
        }
        if isTimeoutTrigger(triggerLabel) {
            return String(localized: "Timeout", table: "Common")
        }
        if isCancelTrigger(triggerLabel) {
            return String(localized: "Cancel", table: "Common")
        }
        return String(localized: "Always", table: "Common")
    }

    private func triggerDetail(for edge: AutomationDependencyEdgeProjection) -> String? {
        if let decision = edge.branchDecision,
           decision.status == .triggered || decision.status == .skipped {
            return decision.detail
        }

        let noDelay = String(localized: "No delay", table: "EditorUX")
        guard edge.delayLabel != noDelay else {
            return branchTitle(for: edge.triggerLabel) == String(localized: "Always", table: "Common") ?
                edge.triggerLabel :
                nil
        }
        return "\(edge.triggerLabel), \(edge.delayLabel)"
    }

    private func isThenTrigger(_ label: String) -> Bool {
        label == String(localized: "On success", table: "Common") ||
            label == String(localized: "Success", table: "Common") ||
            label == String(localized: "Condition matched", table: "Automation")
    }

    private func isElseTrigger(_ label: String) -> Bool {
        label == String(localized: "On failure", table: "Common") ||
            label == String(localized: "Failure", table: "Common") ||
            label == String(localized: "Condition not matched", table: "Automation")
    }

    private func isTimeoutTrigger(_ label: String) -> Bool {
        label == String(localized: "On timeout", table: "Common") ||
            label == String(localized: "Timeout", table: "Common")
    }

    private func isCancelTrigger(_ label: String) -> Bool {
        label == String(localized: "On cancel", table: "Common") ||
            label == String(localized: "Cancelled", table: "Common")
    }

    private var accessibilitySummary: String {
        let rows = edges.map { edge in
            String(
                format: String(localized: "%@ to %@", table: "Common"),
                branchTitle(for: edge.triggerLabel),
                targetTitle(for: edge)
            )
        }
        .joined(separator: ", ")
        return String(
            format: String(localized: "Branches from %@: %@", table: "Common"),
            sourceTitle,
            rows
        )
    }
}

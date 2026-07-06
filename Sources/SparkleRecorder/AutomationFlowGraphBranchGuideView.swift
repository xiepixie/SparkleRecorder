import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphBranchGuideView: View {
    let sourceTitle: String
    let edges: [AutomationDependencyEdgeProjection]
    let targetTitles: [UUID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(NSLocalizedString("Branch", comment: ""), systemImage: "arrow.triangle.branch")
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
        targetTitles[edge.toTaskID] ?? NSLocalizedString("Missing task", comment: "")
    }

    private func branchTitle(for triggerLabel: String) -> String {
        if isThenTrigger(triggerLabel) {
            return NSLocalizedString("Then", comment: "")
        }
        if isElseTrigger(triggerLabel) {
            return NSLocalizedString("Else", comment: "")
        }
        if isTimeoutTrigger(triggerLabel) {
            return NSLocalizedString("Timeout", comment: "")
        }
        if isCancelTrigger(triggerLabel) {
            return NSLocalizedString("Cancel", comment: "")
        }
        return NSLocalizedString("Always", comment: "")
    }

    private func triggerDetail(for edge: AutomationDependencyEdgeProjection) -> String? {
        if let decision = edge.branchDecision,
           decision.status == .triggered || decision.status == .skipped {
            return decision.detail
        }

        let noDelay = NSLocalizedString("No delay", comment: "")
        guard edge.delayLabel != noDelay else {
            return branchTitle(for: edge.triggerLabel) == NSLocalizedString("Always", comment: "") ?
                edge.triggerLabel :
                nil
        }
        return "\(edge.triggerLabel), \(edge.delayLabel)"
    }

    private func isThenTrigger(_ label: String) -> Bool {
        label == NSLocalizedString("On success", comment: "") ||
            label == NSLocalizedString("Success", comment: "") ||
            label == NSLocalizedString("Condition matched", comment: "")
    }

    private func isElseTrigger(_ label: String) -> Bool {
        label == NSLocalizedString("On failure", comment: "") ||
            label == NSLocalizedString("Failure", comment: "") ||
            label == NSLocalizedString("Condition not matched", comment: "")
    }

    private func isTimeoutTrigger(_ label: String) -> Bool {
        label == NSLocalizedString("On timeout", comment: "") ||
            label == NSLocalizedString("Timeout", comment: "")
    }

    private func isCancelTrigger(_ label: String) -> Bool {
        label == NSLocalizedString("On cancel", comment: "") ||
            label == NSLocalizedString("Cancelled", comment: "")
    }

    private var accessibilitySummary: String {
        let rows = edges.map { edge in
            String(
                format: NSLocalizedString("%@ to %@", comment: ""),
                branchTitle(for: edge.triggerLabel),
                targetTitle(for: edge)
            )
        }
        .joined(separator: ", ")
        return String(
            format: NSLocalizedString("Branches from %@: %@", comment: ""),
            sourceTitle,
            rows
        )
    }
}

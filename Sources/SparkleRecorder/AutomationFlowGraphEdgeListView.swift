import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphEdgeListView: View {
    let edges: [AutomationDependencyEdgeProjection]
    let selectedDependencyID: UUID?
    let onSelectDependency: (UUID) -> Void
    let onDeleteDependency: (UUID) -> Void

    var body: some View {
        ForEach(edges) { edge in
            Button {
                onSelectDependency(edge.id)
            } label: {
                AutomationFlowGraphEdgeLabelView(
                    edge: edge,
                    isSelected: selectedDependencyID == edge.id
                )
            }
            .buttonStyle(.plain)
            .help(accessibilityLabel(for: edge))
            .accessibilityLabel(accessibilityLabel(for: edge))
            .contextMenu {
                Button("Delete Dependency", systemImage: "trash", role: .destructive) {
                    onDeleteDependency(edge.id)
                }
            }
            .position(midPoint(for: edge))
        }
    }

    private func midPoint(for edge: AutomationDependencyEdgeProjection) -> CGPoint {
        CGPoint(
            x: CGFloat((edge.start.x + edge.end.x) / 2),
            y: CGFloat((edge.start.y + edge.end.y) / 2)
        )
    }

    private func accessibilityLabel(for edge: AutomationDependencyEdgeProjection) -> String {
        let noDelay = NSLocalizedString("No delay", comment: "")
        let base = edge.delayLabel == noDelay
            ? edge.triggerLabel
            : "\(edge.triggerLabel), \(edge.delayLabel)"
        guard let decision = edge.branchDecision,
              decision.status == .triggered || decision.status == .skipped else {
            return base
        }
        return "\(base), \(decision.detail)"
    }
}

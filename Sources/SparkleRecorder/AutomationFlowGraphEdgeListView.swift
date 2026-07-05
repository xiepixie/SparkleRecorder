import SwiftUI
import SparkleRecorderCore

struct AutomationFlowGraphEdgeListView: View {
    let edges: [AutomationDependencyEdgeProjection]
    let selectedDependencyID: UUID?
    let onSelectDependency: (UUID) -> Void

    var body: some View {
        ForEach(edges) { edge in
            Button {
                onSelectDependency(edge.id)
            } label: {
                Label(edge.triggerLabel, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .lineLimit(1)
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                    .controlSurface(
                        cornerRadius: 7,
                        tint: edge.status.tint,
                        isActive: selectedDependencyID == edge.id
                    )
            }
            .buttonStyle(.plain)
            .help(edge.triggerLabel)
            .accessibilityLabel(edge.triggerLabel)
            .offset(x: midPoint(for: edge).x - 12, y: midPoint(for: edge).y - 12)
        }
    }

    private func midPoint(for edge: AutomationDependencyEdgeProjection) -> CGPoint {
        CGPoint(
            x: CGFloat((edge.start.x + edge.end.x) / 2),
            y: CGFloat((edge.start.y + edge.end.y) / 2)
        )
    }
}

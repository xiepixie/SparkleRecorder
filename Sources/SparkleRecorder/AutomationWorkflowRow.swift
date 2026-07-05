import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowRow: View {
    let workflow: AutomationWorkflowProjection
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(isSelected ? Brand.libraryBlue : .secondary)
                    .accessibilityHidden(true)

                Text(workflow.name)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label(String(format: NSLocalizedString("%d tasks", comment: ""), workflow.nodes.count), systemImage: "circle.grid.cross")
                Label(String(format: NSLocalizedString("%d dependencies", comment: ""), workflow.edges.count), systemImage: "arrow.triangle.branch")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: NSLocalizedString("%@, %d tasks, %d dependencies", comment: ""),
            workflow.name,
            workflow.nodes.count,
            workflow.edges.count
        ))
    }
}

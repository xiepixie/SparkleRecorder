import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowRow: View {
    let workflow: AutomationWorkflowProjection
    let isSelected: Bool
    @State private var isHovered = false

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
                Label(String(format: String(localized: "%d tasks", table: "Automation"), workflow.nodes.count), systemImage: "circle.grid.cross")
                Label(String(format: String(localized: "%d dependencies", table: "Common"), workflow.edges.count), systemImage: "arrow.triangle.branch")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(workflow.statusDetail, systemImage: workflow.status.systemImage)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(workflow.status.tint)

            AutomationNextScheduleBadge(
                date: workflow.nextScheduledOccurrence,
                title: String(localized: "Next", table: "Common"),
                isCompact: true
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Brand.libraryBlue.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { hover in
            isHovered = hover
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: String(localized: "%@, %d tasks, %d dependencies", table: "Automation"),
            workflow.name,
            workflow.nodes.count,
            workflow.edges.count
        ))
        .accessibilityValue("\(workflow.status.label), \(workflow.statusDetail)")
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationTimelineItemView: View {
    let item: AutomationResourceTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.lane.tint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(item.lane.displayName)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(item.lane.tint)

                Spacer(minLength: 0)

                Image(systemName: item.status.systemImage)
                    .foregroundStyle(item.status.tint)
                    .accessibilityHidden(true)
            }

            Text(item.title)
                .font(.subheadline)
                .bold()
                .lineLimit(2)

            Text(item.resourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let startedAt = item.startedAt {
                    Label {
                        Text(startedAt, style: .time)
                    } icon: {
                        Image(systemName: "play")
                    }
                }
                if let completedAt = item.completedAt {
                    Label {
                        Text(completedAt, style: .time)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                }
                if item.hasEvidence {
                    Label(NSLocalizedString("Evidence", comment: ""), systemImage: "doc.richtext")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionSurface(cornerRadius: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var summary = String(
            format: NSLocalizedString("%@, %@, %@", comment: ""),
            item.title,
            item.lane.displayName,
            item.status.label
        )
        if item.hasEvidence {
            summary += ", " + NSLocalizedString("Evidence available", comment: "")
        }
        return summary
    }
}

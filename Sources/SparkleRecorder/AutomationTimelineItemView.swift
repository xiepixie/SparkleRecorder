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

                Label(item.status.label, systemImage: item.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(item.status.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(item.title)
                .font(.subheadline)
                .bold()
                .lineLimit(2)

            Text(item.resourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            AutomationRuntimeDetailStrip(
                statusDetail: nil,
                statusTint: item.status.tint,
                timeoutCountdown: item.timeoutCountdown,
                retryAttemptSummary: item.retryAttemptSummary,
                density: .timeline
            )

            if let conditionProgress = item.conditionProgress {
                AutomationConditionProgressView(
                    progress: conditionProgress,
                    tint: item.status.tint,
                    density: .compact
                )
            }

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
        .overlay(alignment: .top) {
            AutomationRuntimeStatusHairline(status: item.status)
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
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
        if let runtimeSummary = AutomationRuntimeDetailFormatter.accessibilitySummary(
            timeoutCountdown: item.timeoutCountdown,
            retryAttemptSummary: item.retryAttemptSummary
        ) {
            summary += ", " + runtimeSummary
        }
        if let conditionProgress = item.conditionProgress {
            summary += ", " + AutomationConditionProgressFormatter.accessibilitySummary(for: conditionProgress)
        }
        return summary
    }
}

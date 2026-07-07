import SwiftUI
import SparkleRecorderCore

struct AutomationTimelineItemView: View {
    let item: AutomationResourceTimelineItem
    var hasConflict = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(item.kindLabel ?? item.lane.displayName, systemImage: item.status.systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.status.tint)
                    .lineLimit(1)

                if hasConflict {
                    Label(NSLocalizedString("Conflict", comment: ""), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Brand.red500)
                        .lineLimit(1)
                }

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

            if let statusDetail = item.statusDetail, !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(statusDetailTint)
                    .lineLimit(2)
            }

            if let waiting = item.resourceWaiting {
                Text(waiting.detail)
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
                    .lineLimit(2)
            }

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
                if let startedAt = item.timelineStart {
                    Label {
                        Text(AutomationTimelineTimeFormatter.timeString(startedAt))
                    } icon: {
                        Image(systemName: item.startedAt == nil ? "clock" : "play")
                    }
                }
                if let completedAt = item.completedAt {
                    Label {
                        Text(AutomationTimelineTimeFormatter.timeString(completedAt))
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
            Rectangle()
                .fill(hasConflict ? Brand.red500 : item.status.tint)
                .frame(height: 3)
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
            item.kindLabel ?? item.lane.displayName,
            item.status.label
        )
        if let statusDetail = item.statusDetail, !statusDetail.isEmpty {
            summary += ", " + statusDetail
        }
        if hasConflict {
            summary += ", " + NSLocalizedString("Conflict", comment: "")
        }
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

    private var statusDetailTint: Color {
        switch item.status {
        case .failed, .timedOut, .blocked:
            return item.status.tint
        case .cancelled:
            return .secondary
        default:
            return .secondary
        }
    }
}

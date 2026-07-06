import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRuntimeDetailView: View {
    let projection: AutomationTaskNodeProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: NSLocalizedString("RUN STATUS", comment: ""))

            HStack(alignment: .top, spacing: 8) {
                Label(projection.status.label, systemImage: projection.status.systemImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(projection.status.tint)
                    .lineLimit(1)

                Text(projection.statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            AutomationRuntimeDetailStrip(
                statusDetail: nil,
                statusTint: projection.status.tint,
                timeoutCountdown: projection.timeoutCountdown,
                retryAttemptSummary: projection.retryAttemptSummary,
                density: .timeline
            )

            if let conditionProgress = projection.conditionProgress {
                AutomationConditionProgressView(
                    progress: conditionProgress,
                    tint: projection.status.tint,
                    density: .detail
                )
            }

            if let timeoutCountdown = projection.timeoutCountdown {
                runtimeRow(
                    NSLocalizedString("Deadline", comment: ""),
                    timeoutCountdown.deadline.formatted(date: .omitted, time: .shortened)
                )
                runtimeRow(
                    NSLocalizedString("Timeout", comment: ""),
                    durationLabel(timeoutCountdown.timeout)
                )
            }

            if let retryAttemptSummary = projection.retryAttemptSummary {
                runtimeRow(NSLocalizedString("Attempt", comment: ""), retryAttemptSummary.label)
                runtimeRow(
                    NSLocalizedString("Remaining", comment: ""),
                    remainingAttemptLabel(retryAttemptSummary.remainingAttempts)
                )
                if let nextRetryAt = retryAttemptSummary.nextRetryAt {
                    runtimeRow(
                        NSLocalizedString("Next retry", comment: ""),
                        nextRetryAt.formatted(date: .omitted, time: .shortened)
                    )
                }
            }

            if let nextScheduledOccurrence = projection.nextScheduledOccurrence {
                AutomationNextScheduleBadge(
                    date: nextScheduledOccurrence,
                    title: NSLocalizedString("Next", comment: "")
                )
            }

            if projection.hasEvidence {
                Label(NSLocalizedString("Evidence available", comment: ""), systemImage: "doc.richtext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private func runtimeRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(duration)))
        if seconds >= 60 {
            return String(
                format: NSLocalizedString("%dm %02ds", comment: ""),
                seconds / 60,
                seconds % 60
            )
        }
        return String(
            format: NSLocalizedString("%ds", comment: ""),
            seconds
        )
    }

    private func remainingAttemptLabel(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("1 attempt", comment: "")
        }
        return String(
            format: NSLocalizedString("%d attempts", comment: ""),
            count
        )
    }
}

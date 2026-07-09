import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRuntimeDetailView: View {
    let projection: AutomationTaskNodeProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "RUN STATUS", table: "Common"))

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
                    String(localized: "Deadline", table: "Common"),
                    timeoutCountdown.deadline.formatted(date: .omitted, time: .shortened)
                )
                runtimeRow(
                    String(localized: "Timeout", table: "Common"),
                    durationLabel(timeoutCountdown.timeout)
                )
            }

            if let retryAttemptSummary = projection.retryAttemptSummary {
                runtimeRow(String(localized: "Attempt", table: "Common"), retryAttemptSummary.label)
                runtimeRow(
                    String(localized: "Remaining", table: "Common"),
                    remainingAttemptLabel(retryAttemptSummary.remainingAttempts)
                )
                if let nextRetryAt = retryAttemptSummary.nextRetryAt {
                    runtimeRow(
                        String(localized: "Next retry", table: "Common"),
                        nextRetryAt.formatted(date: .omitted, time: .shortened)
                    )
                }
            }

            if let nextScheduledOccurrence = projection.nextScheduledOccurrence {
                AutomationNextScheduleBadge(
                    date: nextScheduledOccurrence,
                    title: String(localized: "Next", table: "Common")
                )
            }

            if projection.hasEvidence {
                Label(String(localized: "Evidence available", table: "Automation"), systemImage: "doc.richtext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
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
                format: String(localized: "%dm %02ds", table: "Common"),
                seconds / 60,
                seconds % 60
            )
        }
        return String(
            format: String(localized: "%ds", table: "Common"),
            seconds
        )
    }

    private func remainingAttemptLabel(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 attempt", table: "Common")
        }
        return String(
            format: String(localized: "%d attempts", table: "Common"),
            count
        )
    }
}

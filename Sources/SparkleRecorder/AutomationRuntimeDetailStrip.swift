import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationRuntimeDetailStrip: View {
    enum Density {
        case node
        case timeline
    }

    let statusDetail: String?
    let statusTint: Color
    let timeoutCountdown: AutomationTimeoutCountdownProjection?
    let retryAttemptSummary: AutomationRetryAttemptSummary?
    let density: Density

    var body: some View {
        Group {
            if hasContent {
                ViewThatFits(in: .horizontal) {
                    fullLine
                    runtimeOnlyLine
                    fallbackLine
                }
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                .accessibilityLabel(accessibilityLabel)
            }
        }
    }

    private var hasContent: Bool {
        statusDetail != nil || hasRuntimeDetails
    }

    private var hasRuntimeDetails: Bool {
        timeoutCountdown != nil || retryAttemptSummary != nil
    }

    private var spacing: CGFloat {
        density == .node ? 5 : 8
    }

    private var progressWidth: CGFloat {
        density == .node ? 28 : 44
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let statusDetail {
            parts.append(statusDetail)
        }
        if let runtimeSummary = AutomationRuntimeDetailFormatter.accessibilitySummary(
            timeoutCountdown: timeoutCountdown,
            retryAttemptSummary: retryAttemptSummary
        ) {
            parts.append(runtimeSummary)
        }
        return parts.joined(separator: ", ")
    }

    private var fullLine: some View {
        HStack(spacing: spacing) {
            if let statusDetail {
                Text(statusDetail)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
                    .layoutPriority(hasRuntimeDetails ? 0 : 1)
            }
            runtimeBadges(compact: false, showsProgress: true)
        }
    }

    private var runtimeOnlyLine: some View {
        HStack(spacing: spacing) {
            if hasRuntimeDetails {
                runtimeBadges(compact: true, showsProgress: true)
            } else if let statusDetail {
                Text(statusDetail)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var fallbackLine: some View {
        if let timeoutCountdown {
            timeoutBadge(
                timeoutCountdown,
                compact: true,
                showsProgress: false
            )
        } else if let retryAttemptSummary {
            retryBadge(retryAttemptSummary, compact: true)
        } else if let statusDetail {
            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func runtimeBadges(compact: Bool, showsProgress: Bool) -> some View {
        if let timeoutCountdown {
            timeoutBadge(
                timeoutCountdown,
                compact: compact,
                showsProgress: showsProgress
            )
        }
        if let retryAttemptSummary {
            retryBadge(retryAttemptSummary, compact: compact)
        }
    }

    private func timeoutBadge(
        _ countdown: AutomationTimeoutCountdownProjection,
        compact: Bool,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .imageScale(.small)
            Text(AutomationRuntimeDetailFormatter.timeoutLabel(
                remaining: countdown.remaining,
                compact: compact
            ))
            if showsProgress {
                AutomationTimeoutProgressBar(
                    fraction: countdown.elapsedFraction,
                    tint: statusTint,
                    width: progressWidth
                )
            }
        }
        .foregroundStyle(statusTint)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func retryBadge(
        _ summary: AutomationRetryAttemptSummary,
        compact: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .imageScale(.small)
            Text(AutomationRuntimeDetailFormatter.retryLabel(summary, compact: compact))
            if !compact, let nextRetryAt = summary.nextRetryAt {
                Text(nextRetryAt, style: .time)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(Brand.sigAmber)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AutomationTimeoutProgressBar: View {
    let fraction: Double
    let tint: Color
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(tint.opacity(0.18))
            Capsule()
                .fill(tint.opacity(0.72))
                .frame(width: width * min(1, max(0, fraction)))
        }
        .frame(width: width, height: 3)
        .accessibilityHidden(true)
    }
}

enum AutomationRuntimeDetailFormatter {
    static func timeoutLabel(remaining: TimeInterval, compact: Bool) -> String {
        let seconds = max(0, Int(ceil(remaining)))
        if compact {
            if seconds >= 60 {
                return String(
                    format: String(localized: "%dm", table: "Common"),
                    seconds / 60
                )
            }
            return String(
                format: String(localized: "%ds", table: "Common"),
                seconds
            )
        }

        if seconds >= 60 {
            return String(
                format: String(localized: "%dm %02ds left", table: "Common"),
                seconds / 60,
                seconds % 60
            )
        }
        return String(
            format: String(localized: "%ds left", table: "Common"),
            seconds
        )
    }

    static func retryLabel(
        _ summary: AutomationRetryAttemptSummary,
        compact: Bool
    ) -> String {
        guard compact else {
            return summary.label
        }
        return "\(summary.currentAttempt)/\(summary.maxAttempts)"
    }

    static func accessibilitySummary(
        timeoutCountdown: AutomationTimeoutCountdownProjection?,
        retryAttemptSummary: AutomationRetryAttemptSummary?
    ) -> String? {
        var parts: [String] = []
        if let timeoutCountdown {
            let seconds = max(0, Int(ceil(timeoutCountdown.remaining)))
            parts.append(String(
                format: String(localized: "%d seconds until timeout", table: "Common"),
                seconds
            ))
        }
        if let retryAttemptSummary {
            parts.append(retryAttemptSummary.label)
            if retryAttemptSummary.nextRetryAt != nil {
                parts.append(String(localized: "Retry is scheduled", table: "Common"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

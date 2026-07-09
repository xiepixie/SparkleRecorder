import SwiftUI
import SparkleRecorderCore

struct AutomationConditionProgressView: View {
    enum Density {
        case compact
        case detail
    }

    let progress: AutomationConditionProgressProjection
    let tint: Color
    let density: Density

    var body: some View {
        switch density {
        case .compact:
            compactBody
        case .detail:
            detailBody
        }
    }

    private var compactBody: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Image(systemName: AutomationVisualConditionPresentation.systemImage(for: progress.kind))
                    .imageScale(.small)
                Text(compactTitle)
                    .lineLimit(1)
                if let timeoutCountdown = progress.timeoutCountdown {
                    Text(AutomationRuntimeDetailFormatter.timeoutLabel(
                        remaining: timeoutCountdown.remaining,
                        compact: true
                    ))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            HStack(spacing: 5) {
                Image(systemName: AutomationVisualConditionPresentation.systemImage(for: progress.kind))
                    .imageScale(.small)
                Text(progress.kindLabel)
                    .lineLimit(1)
                if let timeoutCountdown = progress.timeoutCountdown {
                    Text(AutomationRuntimeDetailFormatter.timeoutLabel(
                        remaining: timeoutCountdown.remaining,
                        compact: true
                    ))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(progress.isActivelyPolling ? tint : .secondary)
        .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
        .accessibilityLabel(AutomationConditionProgressFormatter.accessibilitySummary(for: progress))
    }

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(progress.kindLabel, systemImage: AutomationVisualConditionPresentation.systemImage(for: progress.kind))
                    .font(.caption)
                    .bold()
                    .foregroundStyle(progress.isActivelyPolling ? tint : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(pollingLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(progress.targetLabel)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let timeoutCountdown = progress.timeoutCountdown {
                AutomationRuntimeDetailStrip(
                    statusDetail: nil,
                    statusTint: tint,
                    timeoutCountdown: timeoutCountdown,
                    retryAttemptSummary: nil,
                    density: .timeline
                )
            }

            if hasMetadata {
                metadataRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AutomationConditionProgressFormatter.accessibilitySummary(for: progress))
    }

    private var metadataRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metadataBadges
            }
            VStack(alignment: .leading, spacing: 4) {
                metadataBadges
            }
        }
    }

    @ViewBuilder
    private var metadataBadges: some View {
        if let regionRef = progress.regionRef {
            badge(regionRef, systemImage: "viewfinder")
        }
        if let imageRef = progress.imageRef {
            badge(imageRef, systemImage: "photo")
        }
        if let baselineRef = progress.baselineRef {
            badge(baselineRef, systemImage: "rectangle.dashed")
        }
        if let colorHex = progress.colorHex {
            badge(colorHex, systemImage: "paintpalette")
        }
        if let pixelSampleRadius = progress.pixelSampleRadius {
            badge(
                String(format: String(localized: "Radius %d", table: "Common"), pixelSampleRadius),
                systemImage: "circle.grid.3x3"
            )
        }
        if let threshold = progress.threshold {
            badge(threshold.formatted(.number.precision(.fractionLength(2))), systemImage: "slider.horizontal.3")
        }
    }

    private func badge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var compactTitle: String {
        guard !progress.targetLabel.isEmpty else {
            return progress.kindLabel
        }
        return "\(progress.kindLabel): \(progress.targetLabel)"
    }

    private var hasMetadata: Bool {
        progress.regionRef != nil ||
            progress.imageRef != nil ||
            progress.baselineRef != nil ||
            progress.colorHex != nil ||
            progress.pixelSampleRadius != nil ||
            progress.threshold != nil
    }

    private var pollingLabel: String {
        let seconds = progress.pollingInterval.formatted(.number.precision(.fractionLength(2)))
        if progress.isActivelyPolling {
            return String(format: String(localized: "Polling every %@s", table: "Common"), seconds)
        }
        return String(format: String(localized: "Checks every %@s", table: "Common"), seconds)
    }
}

enum AutomationConditionProgressFormatter {
    static func accessibilitySummary(for progress: AutomationConditionProgressProjection) -> String {
        var parts = [progress.kindLabel, progress.targetLabel, progress.detail]
        if progress.isActivelyPolling {
            parts.append(String(localized: "Actively polling", table: "Common"))
        }
        if let runtimeSummary = AutomationRuntimeDetailFormatter.accessibilitySummary(
            timeoutCountdown: progress.timeoutCountdown,
            retryAttemptSummary: nil
        ) {
            parts.append(runtimeSummary)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

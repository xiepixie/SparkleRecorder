import SwiftUI
import SparkleRecorderCore

struct AutomationTaskBranchDecisionSummaryView: View {
    let decision: AutomationBranchDecisionProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(decision.status.label, systemImage: statusIcon)
                    .foregroundStyle(statusTint)

                Text(decision.outcomeLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let decidedAt = decision.decidedAt {
                    Text(decidedAt, style: .time)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Text(decision.detail)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(runBindingLabel)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .font(.caption)
    }

    private var statusIcon: String {
        switch decision.status {
        case .waiting:
            return "hourglass"
        case .triggered:
            return "arrow.triangle.branch"
        case .skipped:
            return "arrow.turn.down.right"
        case .disabled:
            return "slash.circle"
        }
    }

    private var statusTint: Color {
        switch decision.status {
        case .waiting:
            return .secondary
        case .triggered:
            return Brand.libraryGreen
        case .skipped:
            return .secondary.opacity(0.8)
        case .disabled:
            return .secondary
        }
    }

    private var runBindingLabel: String {
        if let targetRunID = decision.targetRunID {
            return String(
                format: String(localized: "Source %@ -> target %@", table: "Common"),
                shortID(decision.sourceRunID),
                shortID(targetRunID)
            )
        }

        return String(
            format: String(localized: "Source %@", table: "Common"),
            shortID(decision.sourceRunID)
        )
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

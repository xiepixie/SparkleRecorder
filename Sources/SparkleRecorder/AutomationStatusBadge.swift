import SwiftUI
import SparkleRecorderCore

struct AutomationStatusBadge: View {
    let status: AutomationDisplayStatus
    var count: Int?

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(status.label)
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: status.systemImage)
        }
        .font(.caption)
        .foregroundStyle(status.tint)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(status.tint.opacity(0.12))
        )
        .accessibilityLabel(count.map { "\(status.label), \($0)" } ?? status.label)
    }
}

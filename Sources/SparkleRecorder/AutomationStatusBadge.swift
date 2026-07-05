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
        .bold()
        .foregroundStyle(status.tint)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassSurface(cornerRadius: 8, tint: status.tint, interactive: false)
        .accessibilityLabel(count.map { "\(status.label), \($0)" } ?? status.label)
    }
}

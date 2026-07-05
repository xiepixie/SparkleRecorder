import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunRowView: View {
    let run: AutomationTaskRun

    var body: some View {
        let display = AutomationTaskRunDisplay(run: run)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: display.systemImage)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(display.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(display.title)
                            .font(.subheadline)
                            .bold()
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(display.primaryDate, style: .time)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }

                    Text(display.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(display.timestampSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(display.metadataSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilitySummary)
    }
}

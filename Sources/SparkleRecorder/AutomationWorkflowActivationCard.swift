import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowActivationCard: View {
    let activation: AutomationWorkflowActivationProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(activation.title, systemImage: activation.state.systemImage)
                    .font(.headline)
                    .foregroundStyle(activation.state.tint)

                Spacer()

                if let nextOccurrence = activation.nextOccurrence {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next run", tableName: "Automation")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(nextOccurrence, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }

            ForEach(activation.checks) { check in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: check.severity.systemImage)
                        .foregroundStyle(check.severity.tint)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.subheadline.weight(.medium))
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

}

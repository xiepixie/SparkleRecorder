import SwiftUI
import SparkleRecorderCore

struct AutomationTaskPositionControlView: View {
    let position: AutomationGraphPoint
    let onMove: (AutomationGraphPoint) -> Void

    private let step = 24.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AutomationSectionHeader(title: NSLocalizedString("POSITION", comment: ""))
                Spacer(minLength: 0)
                Text(positionSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                moveButton(
                    title: NSLocalizedString("Move task left", comment: ""),
                    systemImage: "arrow.left",
                    dx: -step,
                    dy: 0
                )
                VStack(spacing: 8) {
                    moveButton(
                        title: NSLocalizedString("Move task up", comment: ""),
                        systemImage: "arrow.up",
                        dx: 0,
                        dy: -step
                    )
                    moveButton(
                        title: NSLocalizedString("Move task down", comment: ""),
                        systemImage: "arrow.down",
                        dx: 0,
                        dy: step
                    )
                }
                moveButton(
                    title: NSLocalizedString("Move task right", comment: ""),
                    systemImage: "arrow.right",
                    dx: step,
                    dy: 0
                )
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }

    private var positionSummary: String {
        "\(Int(position.x)), \(Int(position.y))"
    }

    private func moveButton(title: String, systemImage: String, dx: Double, dy: Double) -> some View {
        Button(title, systemImage: systemImage) {
            onMove(AutomationGraphPoint(
                x: max(0, snapped(position.x + dx)),
                y: max(0, snapped(position.y + dy))
            ))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.6)
                )
        )
        .help(title)
        .accessibilityLabel(title)
    }

    private func snapped(_ value: Double) -> Double {
        (value / step).rounded() * step
    }
}

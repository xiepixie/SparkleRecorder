import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EditorFooter: View {
    let eventCount: Int
    let selectedCount: Int
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label(String(format: NSLocalizedString("%d events", comment: ""), eventCount), systemImage: "wave.3.right")
                Text("·").foregroundStyle(.tertiary)
                Label(formatDuration(duration), systemImage: "clock")
                if selectedCount > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label(String(format: NSLocalizedString("%d selected", comment: ""), selectedCount), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(NSLocalizedString("Edits apply live · use Save to persist", comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
        .background(VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow))
    }
}

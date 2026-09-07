import Cocoa
import SwiftUI
import SparkleRecorderCore

struct EditorFooter: View {
    let eventCount: Int
    let selectedCount: Int
    let duration: TimeInterval
    let health: MacroEditorHealthSummary

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Label(String(format: String(localized: "%d events", table: "EditorUX"), eventCount), systemImage: "wave.3.right")
                Text("·").foregroundStyle(.tertiary)
                Label(formatDuration(duration), systemImage: "clock")
                if selectedCount > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Label(String(format: String(localized: "%d selected", table: "Common"), selectedCount), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
                Spacer()
                Label(macroEditorHealthTitle(health), systemImage: footerHealthIcon)
                    .foregroundStyle(footerHealthTint)
                    .help(macroEditorHealthDetail(health))
                Text("·").foregroundStyle(.tertiary)
                Text("Edits apply live", tableName: "Common")
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

    private var footerHealthIcon: String {
        switch health.state {
        case .empty:
            return "record.circle"
        case .needsTargets:
            return "text.viewfinder"
        case .reviewReliability:
            return "wrench.and.screwdriver"
        case .ready:
            return "checkmark.seal"
        }
    }

    private var footerHealthTint: Color {
        switch health.state {
        case .empty:
            return .secondary
        case .needsTargets:
            return Brand.sigAmber
        case .reviewReliability:
            return Brand.sigTeal
        case .ready:
            return Brand.libraryGreen
        }
    }
}

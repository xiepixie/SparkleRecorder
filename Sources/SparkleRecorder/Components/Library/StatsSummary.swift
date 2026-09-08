import Cocoa
import SwiftUI
import SparkleRecorderCore

struct StatsSummary: View {
    let totalMacros: Int
    let totalPlays: Int
    let totalSaved: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(String(localized: "Macros", table: "EditorUX"), "\(totalMacros)", icon: "tray.full")
            statRow(String(localized: "Total plays", table: "Common"), "\(totalPlays)", icon: "play.circle")
            statRow(String(localized: "Time replayed", table: "Common"), formatDuration(totalSaved), icon: "clock")
	        }
	        .padding(8)
	        .sectionSurface(cornerRadius: 9)
	    }

    @ViewBuilder
    func statRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)
        }
    }

    func formatDuration(_ d: TimeInterval) -> String {
        if d < 60 { return String(format: "%ds", Int(d)) }
        if d < 3600 { return String(format: "%dm", Int(d / 60)) }
        return String(format: "%.1fh", d / 3600)
    }
}

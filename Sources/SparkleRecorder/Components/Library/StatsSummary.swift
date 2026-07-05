import Cocoa
import SwiftUI
import SparkleRecorderCore

struct StatsSummary: View {
    @EnvironmentObject var library: MacroLibrary

    private var totalMacros: Int { library.macros.count }
    private var totalPlays: Int { library.macros.reduce(0) { $0 + $1.playCount } }
    private var totalSaved: TimeInterval { library.macros.reduce(0) { $0 + $1.totalRunTime } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(NSLocalizedString("Macros", comment: ""), "\(totalMacros)", icon: "tray.full")
            statRow(NSLocalizedString("Total plays", comment: ""), "\(totalPlays)", icon: "play.circle")
            statRow(NSLocalizedString("Time replayed", comment: ""), formatDuration(totalSaved), icon: "clock")
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

import Cocoa
import SwiftUI
import SparkleRecorderCore

struct LegendChip: View {
    let label: String
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

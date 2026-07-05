import Cocoa
import SwiftUI
import SparkleRecorderCore

struct FooterRow: View {
    let icon: String
    let label: String
    let rightAccessory: AnyView?
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovered ? Brand.libraryBlue : Color.secondary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11.5, weight: hovered ? .semibold : .medium))
                    .foregroundStyle(hovered ? Brand.libraryBlue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
                if let r = rightAccessory { r }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Brand.libraryBlue.opacity(hovered ? 0.08 : 0.0))
        )
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
        .onHover { hovered = $0 }
    }
}

import Cocoa
import SwiftUI
import SparkleRecorderCore

struct CardActionButton: View {
    let systemImage: String
    let tint: Color
    var label: String = ""
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(label.isEmpty ? systemImage : label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary))
                .frame(width: 30, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .libraryControlSurface(cornerRadius: 8, tint: tint, isActive: hovered, activeFillOpacity: 0.74)
        .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
        .onHover { hovered = $0 }
        .accessibilityLabel(label.isEmpty ? systemImage : label)
    }
}

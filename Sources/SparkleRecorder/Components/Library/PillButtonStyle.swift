import Cocoa
import SwiftUI
import SparkleRecorderCore

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .blue
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let hoverScale: CGFloat = reduceMotion ? 1.0 : 1.012
        let pressScale: CGFloat = reduceMotion ? 1.0 : 0.985

        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .prominentGlassCapsule(tint: tint)
            .scaleEffect(configuration.isPressed ? pressScale : (hovered ? hoverScale : 1.0))
            .brightness(hovered && !configuration.isPressed ? 0.02 : 0)
            .animation(reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation, value: hovered)
            .animation(reduceMotion ? .linear(duration: 0.01) : Brand.pressAnimation, value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

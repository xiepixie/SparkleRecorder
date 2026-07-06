import SwiftUI

struct AutomationQuietButtonStyle: ButtonStyle {
    var tint: Color?
    var isDestructive = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let accent = tint ?? (isDestructive ? Brand.red500 : Color.primary)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        configuration.label
            .font(.caption)
            .bold()
            .foregroundStyle(foreground(accent: accent))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(
                shape
                    .fill(background(accent: accent, isPressed: configuration.isPressed))
                    .overlay(
                        shape.strokeBorder(
                            accent.opacity(configuration.isPressed ? 0.24 : 0.14),
                            lineWidth: 0.6
                        )
                    )
            )
            .opacity(isEnabled ? 1 : 0.45)
    }

    private func foreground(accent: Color) -> Color {
        if isDestructive {
            return Brand.red500
        }
        return tint ?? .primary
    }

    private func background(accent: Color, isPressed: Bool) -> Color {
        if isDestructive {
            return Brand.red500.opacity(isPressed ? 0.16 : 0.075)
        }
        if tint != nil {
            return accent.opacity(isPressed ? 0.14 : 0.07)
        }
        if colorScheme == .dark {
            return Color.white.opacity(isPressed ? 0.085 : 0.045)
        }
        return Color.primary.opacity(isPressed ? 0.075 : 0.045)
    }
}

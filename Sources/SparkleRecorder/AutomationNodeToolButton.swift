import SwiftUI

struct AutomationNodeToolButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .foregroundStyle(isActive ? tint : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? tint.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isActive ? tint.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
            )
            .contentShape(Rectangle())
            .help(title)
            .accessibilityLabel(title)
    }
}

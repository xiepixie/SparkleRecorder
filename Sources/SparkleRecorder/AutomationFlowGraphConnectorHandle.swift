import SwiftUI

struct AutomationFlowGraphConnectorHandle: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: "link.circle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .foregroundStyle(isActive ? Brand.sigAmber : Color.secondary)
            .background(
                Circle()
                    .fill(isActive ? Brand.sigAmber.opacity(0.16) : Color.black.opacity(0.18))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isActive ? Brand.sigAmber.opacity(0.62) : Color.primary.opacity(0.18),
                                lineWidth: isActive ? 1.2 : 0.8
                            )
                    )
            )
            .contentShape(Circle())
            .help(title)
            .accessibilityLabel(title)
    }
}

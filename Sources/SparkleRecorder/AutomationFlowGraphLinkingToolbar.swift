import SwiftUI

struct AutomationFlowGraphLinkingToolbar: View {
    let trigger: AutomationDependencyTriggerDraft
    let triggerOptions: [AutomationDependencyTriggerDraft]
    let onSetTrigger: (AutomationDependencyTriggerDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(String(localized: "Linking", table: "Common"), systemImage: "link")
                .labelStyle(.titleAndIcon)

            Divider()
                .frame(height: 14)
                .opacity(0.5)

            Menu {
                ForEach(triggerOptions) { option in
                    Button(option.title, action: { onSetTrigger(option) })
                }
            } label: {
                Label(
                    String(format: String(localized: "Trigger %@", table: "Automation"), trigger.title),
                    systemImage: "arrow.triangle.branch"
                )
                .labelStyle(.titleAndIcon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Cancel link", systemImage: "xmark", action: onCancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help(String(localized: "Cancel link", table: "Common"))
                .accessibilityLabel(String(localized: "Cancel link", table: "Common"))
        }
        .font(.caption)
        .foregroundStyle(Brand.sigAmber)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Brand.sigAmber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Brand.sigAmber.opacity(0.24), lineWidth: 0.7)
                )
        )
    }
}

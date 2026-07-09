import SwiftUI
import UniformTypeIdentifiers

struct AutomationWorkflowTaskEmptyDropView: View {
    let isActive: Bool
    let onTargetChanged: (Bool) -> Void
    let onDropMacro: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        Label(String(localized: "Drop a macro here", table: "EditorUX"), systemImage: "plus.circle")
            .font(.caption)
            .foregroundStyle(isActive ? Brand.libraryGreen : .secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                isTargeted: $isTargeted,
                perform: handleMacroDrop(providers:)
            )
            .onChange(of: isTargeted) {
                onTargetChanged(isTargeted)
            }
            .accessibilityHint(String(localized: "Drop a macro to create the first task", table: "Common"))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isActive ? Brand.libraryGreen.opacity(0.08) : Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Brand.libraryGreen.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: 0.7
                    )
            )
    }

    private func handleMacroDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String,
                  let macroID = AutomationMacroDragPayload.macroID(from: payload) else {
                return
            }

            Task { @MainActor in
                onDropMacro(macroID)
            }
        }
        return true
    }
}

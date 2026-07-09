import SwiftUI
import SparkleRecorderCore

struct AutomationMacroTaskRow: View {
    let macro: SavedMacro
    let selectedWorkflow: AutomationWorkflow?
    let onAddMacroTask: (SavedMacro) -> Void

    @State private var isHovered = false

    private var trailingSymbol: String {
        isHovered ? "plus.circle" : "line.3.horizontal"
    }

    private var trailingTint: Color {
        if isHovered {
            return selectedWorkflow == nil ? .secondary : Brand.libraryGreen
        }
        return .secondary
    }

    var body: some View {
        Button(action: addMacroTask) {
            HStack(spacing: 8) {
                macroIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.name)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(String(format: String(localized: "%d events", table: "EditorUX"), macro.eventCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: trailingSymbol)
                    .foregroundStyle(trailingTint)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: AutomationMacroDragPayload.string(for: macro.id) as NSString)
        }
        .onHover { hover in
            isHovered = hover
        }
        .help(String(localized: "Add macro as task", table: "Automation"))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "Press to add as a workflow task. Drag to place it on the graph or task list.", table: "Common"))
    }

    private var macroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(cardAccentColor(for: macro.accent).opacity(0.72))
            Image(systemName: macro.icon ?? "wave.3.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isHovered ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 0.6)
            )
    }

    private var accessibilityLabel: String {
        String(
            format: String(localized: "Add %@ as task", table: "Automation"),
            macro.name
        )
    }

    private func addMacroTask() {
        onAddMacroTask(macro)
    }
}

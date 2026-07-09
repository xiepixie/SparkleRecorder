import Cocoa
import SwiftUI
import SparkleRecorderCore

struct HotkeyAssignmentSheet: View {
    let macro: SavedMacro
    let currentHotkey: HotkeyBinding?
    let allHotkeys: Set<UInt32>
    let onSave: (HotkeyBinding?) -> Void
    let onCancel: () -> Void

    @State private var selected: HotkeyBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assign Hotkey", tableName: "Common").font(.system(size: 14, weight: .semibold))
                Text(String(format: String(localized: "Press any key combination to play %@ from any app.", table: "Automation"), macro.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ShortcutRecorderField(currentBinding: $selected, allHotkeys: allHotkeys)

            HStack {
                if currentHotkey != nil {
                    Button(String(localized: "Clear", table: "Common")) { onSave(nil) }
                        .controlSize(.regular)
                }
                Spacer()
                Button(String(localized: "Cancel", table: "Common"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Assign", table: "Common")) {
                    if let s = selected {
                        onSave(s)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { selected = currentHotkey }
    }
}

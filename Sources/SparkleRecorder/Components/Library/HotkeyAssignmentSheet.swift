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
                Text(NSLocalizedString("Assign Hotkey", comment: "")).font(.system(size: 14, weight: .semibold))
                Text(String(format: NSLocalizedString("Press any key combination to play %@ from any app.", comment: ""), macro.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ShortcutRecorderField(currentBinding: $selected, allHotkeys: allHotkeys)

            HStack {
                if currentHotkey != nil {
                    Button(NSLocalizedString("Clear", comment: "")) { onSave(nil) }
                        .controlSize(.regular)
                }
                Spacer()
                Button(NSLocalizedString("Cancel", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Assign", comment: "")) {
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

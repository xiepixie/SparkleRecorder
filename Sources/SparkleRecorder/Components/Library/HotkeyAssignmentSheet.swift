import Cocoa
import SwiftUI
import SparkleRecorderCore

struct HotkeyAssignmentSheet: View {
    let macro: SavedMacro
    let currentHotkey: HotkeyBinding?
    let allHotkeys: Set<UInt32>
    let onSave: (HotkeyBinding?) -> Void
    let onCancel: () -> Void

    @State private var selected: UInt32?

    private let fkeys: [(UInt32, String)] = [
        (KeyCode.f1, "F1"), (KeyCode.f2, "F2"), (KeyCode.f3, "F3"), (KeyCode.f4, "F4"),
        (KeyCode.f5, "F5"), (KeyCode.f6, "F6"), (KeyCode.f7, "F7"), (KeyCode.f8, "F8"),
        (KeyCode.f9, "F9"), (KeyCode.f10, "F10"), (KeyCode.f11, "F11"), (KeyCode.f12, "F12"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Assign Hotkey", comment: "")).font(.system(size: 14, weight: .semibold))
                Text(String(format: NSLocalizedString("Press F-key to play %@ from any app.", comment: ""), macro.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 6) {
                ForEach(fkeys, id: \.0) { (code, name) in
                    let inUse = allHotkeys.contains(code) && code != currentHotkey?.keyCode
                    Button {
                        selected = code
                    } label: {
                        Text(name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(inUse ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected == code ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(selected == code ? Color.accentColor : Color.primary.opacity(0.10),
                                                          lineWidth: selected == code ? 1.4 : 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(inUse)
                    .help(inUse ? NSLocalizedString("Already in use", comment: "") : "")
                }
            }

            HStack {
                if currentHotkey != nil {
                    Button(NSLocalizedString("Clear", comment: "")) { onSave(nil) }
                        .controlSize(.regular)
                }
                Spacer()
                Button(NSLocalizedString("Cancel", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Assign", comment: "")) {
                    if let s = selected, let pair = fkeys.first(where: { $0.0 == s }) {
                        onSave(HotkeyBinding(keyCode: pair.0, name: pair.1))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { selected = currentHotkey?.keyCode }
    }
}

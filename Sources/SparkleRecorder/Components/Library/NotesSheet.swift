import Cocoa
import SwiftUI
import SparkleRecorderCore

struct NotesSheet: View {
    let macro: SavedMacro
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Notes", comment: "")).font(.system(size: 14, weight: .semibold))
                Text(String(format: NSLocalizedString("A free-form scratchpad attached to %@.", comment: ""), macro.name))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                if text.isEmpty {
                    Text(NSLocalizedString("What does this macro do? When did you build it? Any caveats…", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .font(.system(size: 12))
            }
            .frame(minHeight: 200, idealHeight: 220)

            HStack {
                Spacer()
                Button(NSLocalizedString("Cancel", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Save", comment: ""), action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

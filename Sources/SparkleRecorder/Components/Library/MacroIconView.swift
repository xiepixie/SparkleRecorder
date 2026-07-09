import Cocoa
import SwiftUI
import SparkleRecorderCore

struct MacroIconView: View {
    let macro: SavedMacro
    let onSetIcon: (String?) -> Void

    private static let symbolPalette: [String] = [
        "wave.3.right", "bolt.fill", "sparkles", "cursorarrow.click",
        "keyboard", "envelope.fill", "doc.fill", "calendar", "message.fill",
        "globe", "terminal.fill", "hammer.fill", "pencil.tip", "paperplane.fill",
        "music.note", "photo.fill", "gamecontroller.fill", "cart.fill",
        "lock.fill", "star.fill",
    ]

    var body: some View {
        let tint = cardAccentColor(for: macro.accent)
        Menu {
            Section(String(localized: "SF Symbol", table: "Common")) {
                ForEach(Self.symbolPalette, id: \.self) { s in
                    Button {
                        onSetIcon(s)
                    } label: {
                        Label(s, systemImage: s)
                    }
                }
            }
            Divider()
            Button(String(localized: "Reset", table: "Common"), role: .destructive) { onSetIcon(nil) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    )
                Image(systemName: macro.icon ?? "wave.3.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .help(String(localized: "Change icon", table: "Common"))
        .accessibilityLabel(Text("Change icon", tableName: "Common"))
    }
}

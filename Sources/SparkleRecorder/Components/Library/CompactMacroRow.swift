import Cocoa
import SwiftUI
import SparkleRecorderCore

struct CompactMacroRow: View {
    let macro: SavedMacro
    let controller: MenuBarController
    let isCurrent: Bool
    let isSelected: Bool

    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onSetIcon: (String?) -> Void
    let onAssignHotkey: () -> Void

    @State private var hovered = false
    @State private var playHovered = false
    @State private var editHovered = false

    var body: some View {
        HStack(spacing: 12) {
            MacroIconView(macro: macro, onSetIcon: onSetIcon)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(macro.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCurrent ? Brand.libraryBlue : .primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(durationText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    if let hk = macro.hotkey {
                        Button(action: onAssignHotkey) {
                            KeyCapView(text: hk.name, size: .sm)
                        }
                        .buttonStyle(.plain)
                        .help(String(format: String(localized: "Hotkey: %@ — click to change", table: "EditorUX"), hk.name))
                    }
                    
                    if macro.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AnyShapeStyle(.yellow))
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            if hovered || isCurrent {
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(editHovered ? Brand.libraryBlue : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { editHovered = $0 }
                .padding(.trailing, 4)
                .help(String(localized: "Edit in Main Window", table: "Common"))
                
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Brand.libraryGreen.opacity(playHovered ? 1.0 : 0.85))
                                .shadow(color: Brand.libraryGreen.opacity(0.3), radius: 4, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .onHover { playHovered = $0 }
                .help(String(localized: "Play", table: "Common"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.05 : (isCurrent ? 0.03 : 0.0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.libraryBlue.opacity(isCurrent ? 0.4 : 0.0), lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .onTapGesture {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            onSelect(mods)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.name)
        .accessibilityAction { onSelect([]) }
        .accessibilityAction(named: String(localized: "Play", table: "Common")) { onPlay() }
        .accessibilityAction(named: String(localized: "Edit", table: "Common")) { onEdit() }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hovered)
    }
    
    private var durationText: String {
        let d = macro.duration
        let m = Int(d) / 60
        let s = Int(d) % 60
        let cs = Int((d - floor(d)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}

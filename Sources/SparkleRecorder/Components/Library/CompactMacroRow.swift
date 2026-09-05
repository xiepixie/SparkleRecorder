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
    let automationSummary: AutomationMacroScheduleSummary?
    let onSchedule: () -> Void
    let onShowEvidence: () -> Void
    let onReconstruct: () -> Void
    let onSetIcon: (String?) -> Void
    let onAssignHotkey: () -> Void

    @State private var hovered = false
    @State private var playHovered = false
    @State private var editHovered = false
    @State private var scheduleHovered = false

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

                    if let automationSummary {
                        Button(action: onSchedule) {
                            Label(automationSummary.statusText, systemImage: "calendar.badge.checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 190, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Edit automatic run…", table: "Automation"))
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            if hovered || isCurrent {
                Button(action: onReconstruct) { Image(systemName: "wand.and.stars") }
                    .buttonStyle(.plain)
                    .help(String(localized: "AI-assisted reconstruction…", table: "EditorUX"))
                Button(action: onShowEvidence) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Latest run…", table: "Automation"))

                Button(action: onSchedule) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(scheduleHovered ? Brand.sigAmber : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { scheduleHovered = $0 }
                .help(String(localized: "Run automatically…", table: "Automation"))

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
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction { onSelect([]) }
        .accessibilityAction(named: String(localized: "Play", table: "Common")) { onPlay() }
        .accessibilityAction(named: String(localized: "Edit", table: "Common")) { onEdit() }
        .accessibilityAction(named: automationActionTitle) { onSchedule() }
    }
    
    private var durationText: String {
        let d = macro.duration
        let m = Int(d) / 60
        let s = Int(d) % 60
        let cs = Int((d - floor(d)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    private var automationActionTitle: String {
        automationSummary == nil
            ? String(localized: "Run automatically", table: "Automation")
            : String(localized: "Edit automatic run", table: "Automation")
    }

    private var accessibilitySummary: String {
        guard let automationSummary else { return macro.name }
        return "\(macro.name), \(automationSummary.statusText)"
    }
}

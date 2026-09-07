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
    let onChooseTargetWindow: () -> Void
    let onSetIcon: (String?) -> Void
    let onAssignHotkey: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            MacroIconView(macro: macro, onSetIcon: onSetIcon)
            
            CompactMacroRowMetadataView(
                macro: macro,
                automationSummary: automationSummary,
                isCurrent: isCurrent,
                onAssignHotkey: onAssignHotkey,
                onSchedule: onSchedule
            )
            
            Spacer(minLength: 8)
            
            if hovered || isCurrent {
                CompactMacroRowActionsView(
                    hasTargetWindow: !macro.surfaces.isEmpty,
                    onReconstruct: onReconstruct,
                    onShowEvidence: onShowEvidence,
                    onSchedule: onSchedule,
                    onChooseTargetWindow: onChooseTargetWindow,
                    onEdit: onEdit,
                    onPlay: onPlay
                )
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

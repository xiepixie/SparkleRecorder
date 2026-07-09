import Cocoa
import SwiftUI
import SparkleRecorderCore
import UniformTypeIdentifiers

struct MacroCard: View {
    let macro: SavedMacro
    let controller: MenuBarController
    let isCurrent: Bool
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameText: String

    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onExportText: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onSetLoops: (Int) -> Void
    let onAssignHotkey: () -> Void
    let onClearHotkey: () -> Void
    let onToggleFavorite: () -> Void
    let onSetIcon: (String?) -> Void
    let onAddTag: () -> Void
    let onDragMove: (UUID, UUID) -> Void
    let onOpenNotes: () -> Void
    let onSetSpeed: (Double) -> Void
    let onSetAccent: (String?) -> Void
    let onSetChain: (UUID?) -> Void
    let chainCandidates: [(UUID, String)]
    let chainTargetName: String?
    let onCreateSequence: () -> Void

    @State private var hovered = false
    @State private var dragOver = false
    @State private var showCustomSpeed = false
    @State private var customSpeedText = ""
    @State private var clearButtonHovered = false
    @State private var moreButtonHovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var cardFocused: Bool
    @FocusState private var renameFocused: Bool

    private var durationText: String {
        let d = macro.duration
        let m = Int(d) / 60
        let s = Int(d) % 60
        let cs = Int((d - floor(d)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    private var strokeColor: Color {
        if isSelected { return Brand.libraryBlue.opacity(0.62) }
        if isCurrent { return Brand.libraryBlue.opacity(0.45) }
        if dragOver { return Brand.libraryBlue.opacity(0.50) }
        return Color.primary.opacity(0.10)
    }

    private var accentName: String? {
        normalizedAccentName(macro.accent)
    }

    private var hoverStrokeColor: Color {
        hovered && !isSelected && !isCurrent && !dragOver ? Brand.libraryBlue.opacity(0.20) : .clear
    }

    private var hoverAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : Brand.hoverAnimation
    }

    private var stateAnimation: Animation {
        reduceMotion ? .linear(duration: 0.01) : Brand.spring
    }

    var body: some View {
        styledCard
            .onHover { hovered = $0 }
            .onTapGesture {
                let mods = NSApp.currentEvent?.modifierFlags ?? []
                onSelect(mods)
            }
            // Keyboard + assistive access: the card is one focusable element with
            // every action exposed; Delete key removes, Escape commits a rename.
            .focusable(!isRenaming)
            .focused($cardFocused)
            .disableFocusEffect()
            .onDeleteCommand { onDelete() }
            .onExitCommand {
                if isRenaming { onCommitRename() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onSelect([]) }
	            .accessibilityAction(named: String(localized: "Play", table: "Common")) { onPlay() }
	            .accessibilityAction(named: String(localized: "Edit", table: "Common")) { onEdit() }
	            .accessibilityAction(named: macro.favorite ? String(localized: "Remove favorite", table: "Common") : String(localized: "Add favorite", table: "Common")) { onToggleFavorite() }
	            .accessibilityAction(named: String(localized: "Rename", table: "Common")) { onStartRename() }
	            .accessibilityAction(named: String(localized: "Delete", table: "Common")) { onDelete() }
	            .contextMenu { cardMenuItems(includePlayEdit: true) }
	            .alert(String(localized: "Custom playback speed", table: "Common"), isPresented: $showCustomSpeed) {
	                TextField(String(localized: "e.g. 1.75", table: "Common"), text: $customSpeedText)
	                Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
	                Button(String(localized: "Set", table: "Common")) {
                    let trimmed = customSpeedText.trimmingCharacters(in: .whitespaces)
                    if let v = Double(trimmed) {
                        onSetSpeed(max(0.1, min(10.0, v)))
                    }
                }
            } message: {
                Text("Multiplier between 0.1× and 10×.", tableName: "Automation")
            }

    }

    private var cardHeight: CGFloat {
        var base: CGFloat = macro.tags.isEmpty ? 102 : 124
        if macro.surfaces.values.first != nil {
            base += 20
        }
        return base
    }

    private var styledCard: some View {
        let isLifted = hovered || isCurrent || isSelected || cardFocused || dragOver

        return cardContent
            .padding(11)
            .frame(height: cardHeight)
            .animation(stateAnimation, value: cardHeight)
            .background { cardBackground }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isCurrent ? 1.0 : 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hoverStrokeColor, lineWidth: 0.75)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Brand.libraryBlue.opacity(cardFocused ? 0.58 : 0), lineWidth: 2)
            )
            .overlay(alignment: .leading) {
                if let accentName {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(cardAccentColor(for: accentName))
                        .frame(width: 3)
                        .padding(.vertical, 10)
                        .padding(.leading, 1)
                        .accessibilityHidden(true)
                }
            }
            .shadow(
                color: .black.opacity(isLifted ? 0.12 : 0.065),
                radius: isLifted ? 5 : 2.5,
                y: isLifted ? 2 : 1
            )
            .animation(hoverAnimation, value: hovered)
            .animation(stateAnimation, value: isCurrent)
            .animation(stateAnimation, value: isSelected)
            .animation(stateAnimation, value: cardFocused)
            .animation(stateAnimation, value: dragOver)
    }

    /// The card surface. Cards are the CONTENT layer, so per Apple's Liquid Glass
    /// guidance they are NOT glass — glass belongs to the floating control layer
    /// (Record button, HUD, countdown). A card is an opaque adaptive surface;
    /// current state is a restrained accent fill + the stroke overlay,
    /// never a heavy colored wash.
    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let tint = cardAccentColor(for: macro.accent)
        let tintOpacity = isCurrent ? 0.032 : (hovered ? 0.017 : 0.006)
        let highlightOpacity = scheme == .dark ? 0.05 : 0.16
        ZStack {
            shape.fill(.thinMaterial)
            shape.fill(tint.opacity(tintOpacity))
            shape
                .fill(LinearGradient(
                    colors: [Color.white.opacity(highlightOpacity), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .opacity(hovered ? 0.8 : 0.35)
        }
    }

	    @ViewBuilder
	    func cardMenuItems(includePlayEdit: Bool) -> some View {
	        if includePlayEdit {
	            Button { onPlay() } label: { Label(String(localized: "Play", table: "Common"), systemImage: "play.fill") }
	            Button { onEdit() } label: { Label(String(localized: "Edit…", table: "Common"), systemImage: "slider.horizontal.below.rectangle") }
	            Divider()
	        }
	        Button { onCreateSequence() } label: { Label(String(localized: "Create Sequence…", table: "Common"), systemImage: "arrow.right.circle") }
	        Divider()
	        Button { onStartRename() } label: { Label(String(localized: "Rename…", table: "Common"), systemImage: "pencil") }
	        Button { onToggleFavorite() } label: {
	            Label(macro.favorite ? String(localized: "Unfavorite", table: "Common") : String(localized: "Favorite", table: "Common"), systemImage: macro.favorite ? "star.slash" : "star")
	        }
	        Divider()
	        Button { onOpenNotes() } label: { Label(String(localized: "Notes…", table: "Common"), systemImage: "text.alignleft") }
	        Button(action: onAddTag) { Label(String(localized: "Add Tag…", table: "Common"), systemImage: "tag") }
	        Button { onAssignHotkey() } label: { Label(String(localized: "Assign Hotkey…", table: "Common"), systemImage: "keyboard") }
	        if macro.hotkey != nil {
	            Button { onClearHotkey() } label: { Label(String(localized: "Clear Hotkey", table: "Common"), systemImage: "keyboard.badge.ellipsis") }
	        }
	        Divider()
	        
	        Button { controller.bindCurrentWindow(to: macro.id) } label: { Label(String(localized: "Bind Active Window", table: "Common"), systemImage: "window.badge.key") }
	        if macro.surfaces.values.first != nil {
	            Button(action: { controller.library.setFollowWindowOffset(id: macro.id, enabled: !macro.followWindowOffset) }) {
	                Label(String(localized: "Follow Window Position", table: "Common"), systemImage: macro.followWindowOffset ? "checkmark.circle" : "circle")
	            }
	            Button { controller.clearWindowBinding(for: macro.id) } label: { Label(String(localized: "Clear Window Binding", table: "Common"), systemImage: "xmark.rectangle") }
	        }
	        Divider()

        speedSubmenu()
        colorSubmenu()
        chainSubmenu()
        Divider()
	        Button { onDuplicate() } label: { Label(String(localized: "Duplicate", table: "Common"), systemImage: "plus.square.on.square") }
	        Menu(String(localized: "Export", table: "Common")) {
	            Button { onExport() } label: { Label(String(localized: "As SparkleRecorder File…", table: "Recording"), systemImage: "doc.badge.plus") }
	            Button { onExportText() } label: { Label(String(localized: "As Text…", table: "EditorUX"), systemImage: "doc.plaintext") }
	        }
	        Divider()
	        Button(role: .destructive) { onDelete() } label: { Label(String(localized: "Delete", table: "Common"), systemImage: "trash") }
	    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Title row
            HStack(spacing: 6) {
                MacroIconView(macro: macro, onSetIcon: onSetIcon)

                if isRenaming {
                    TextField(String(localized: "Name", table: "Common"), text: $renameText, onCommit: onCommitRename)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .focused($renameFocused)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                renameFocused = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                                }
                            }
                        }
                } else {
                    Text(macro.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                if !macro.notes.isEmpty {
                    Button(action: onOpenNotes) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Has notes — click to open", table: "EditorUX"))
                }

                if let hk = macro.hotkey {
                    Button(action: onAssignHotkey) {
                        KeyCapView(text: hk.name)
                    }
                    .buttonStyle(.plain)
                    .help(String(format: String(localized: "Hotkey: %@ — click to change", table: "EditorUX"), hk.name))
                    .accessibilityLabel(String(format: String(localized: "Change hotkey %@", table: "Common"), hk.name))
                }

                Button(action: onToggleFavorite) {
                    Image(systemName: macro.favorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(macro.favorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .help(macro.favorite ? String(localized: "Unstar", table: "Common") : String(localized: "Star", table: "Common"))
                .accessibilityLabel(macro.favorite ? String(localized: "Remove favorite", table: "Common") : String(localized: "Add favorite", table: "Common"))
            }

            // Tiny waveform
            MiniWaveform(events: macro.events, bars: macro.waveformBars, duration: macro.duration)
                .frame(height: 18)

            // Tags row (if any)
            if !macro.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(macro.tags, id: \.self) { t in
                            Text(t)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.18))
                                )
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(height: 16)
            }

            // Window binding row
            if let surface = macro.surfaces.values.first {
                HStack(spacing: 4) {
                    Image(systemName: "window.badge.key")
                        .font(.system(size: 9))
                        .foregroundStyle(Brand.sigTeal)
                    Text(String(format: String(localized: "Bound: %@ (%dx%d)", table: "Common"), surface.appName ?? String(localized: "Window", table: "Common"), Int(surface.recordedFrame.width), Int(surface.recordedFrame.height)))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if macro.followWindowOffset {
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text("Offset dx/dy enabled", tableName: "Common")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        withAnimation(stateAnimation) {
                            controller.clearWindowBinding(for: macro.id)
                        }
                    }) {
                        Label(String(localized: "Clear window binding", table: "Common"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(clearButtonHovered ? AnyShapeStyle(Color.red.opacity(0.92)) : AnyShapeStyle(Color.secondary))
                            .frame(width: 19, height: 19)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(clearButtonHovered ? 0.12 : 0.0))
                            .overlay(Circle().strokeBorder(Color.red.opacity(clearButtonHovered ? 0.22 : 0.0), lineWidth: 0.5))
                    )
                    .animation(hoverAnimation, value: clearButtonHovered)
                    .help(String(localized: "Clear window binding", table: "Common"))
                    .onHover { clearButtonHovered = $0 }
                }
                .padding(.vertical, 1)
            }

            // Bottom row: meta + actions. These controls live INSIDE a content
            // card, so they stay plain (no glass) — glass is reserved for the
            // floating control layer.
            HStack(spacing: 4) {
                metaRow
                Spacer()
                CardActionButton(systemImage: "play.fill", tint: Brand.libraryGreen, label: String(format: String(localized: "Play %@", table: "Common"), macro.name)) { onPlay() }
                    .help(String(localized: "Play", table: "Common"))
                LoopChip(loops: macro.loops, onChange: onSetLoops)
                CardActionButton(systemImage: "slider.horizontal.below.rectangle", tint: Brand.libraryBlue, label: String(format: String(localized: "Edit %@", table: "Common"), macro.name)) { onEdit() }
                    .help(String(localized: "Edit", table: "Common"))
	                Menu {
	                    cardMenuItems(includePlayEdit: false)
	                } label: {
	                    Label(String(localized: "More actions", table: "EditorUX"), systemImage: "ellipsis")
	                        .labelStyle(.iconOnly)
	                        .font(.system(size: 10, weight: .bold))
	                        .foregroundStyle(moreButtonHovered ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary))
	                        .frame(width: 30, height: 22)
	                        .contentShape(Rectangle())
	                }
	                .menuStyle(.borderlessButton)
	                .menuIndicator(.hidden)
	                .frame(width: 30, height: 22)
	                .libraryControlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: moreButtonHovered, activeFillOpacity: 0.68)
	                .animation(hoverAnimation, value: moreButtonHovered)
	                .onHover { moreButtonHovered = $0 }
	                .accessibilityLabel(String(localized: "More actions", table: "EditorUX"))
            }
        }
    }

    /// What VoiceOver reads for the whole card.
    private var accessibilitySummary: String {
        var parts = [macro.name, durationText]
        if macro.playCount > 0 {
            parts.append(String(format: String(localized: "played %d times", table: "Common"), macro.playCount))
        }
        if let hotkey = macro.hotkey {
            parts.append(String(format: String(localized: "hotkey %@", table: "Common"), hotkey.name))
        }
        if let accentName {
            parts.append(String(format: String(localized: "color %@", table: "Common"), accentDisplayName(accentName)))
        }
        if macro.favorite {
            parts.append(String(localized: "favorite", table: "Common"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Meta row

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 4) {
            Text(durationText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if abs(macro.speed - 1.0) > 0.01 {
                Text(formatSpeed(macro.speed))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Brand.sigViolet)
            }
            if macro.chainTo != nil {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.tertiary)
                    .help(chainTargetName.map { String(format: String(localized: "Chains to %@", table: "Common"), $0) } ?? String(localized: "Chained", table: "Common"))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Submenus

    @ViewBuilder
    func speedSubmenu() -> some View {
        Menu(String(localized: "Speed", table: "Common")) {
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { v in
                Button {
                    onSetSpeed(v)
                } label: {
                    if abs(macro.speed - v) < 0.01 {
                        Label(formatSpeed(v), systemImage: "checkmark")
                    } else {
                        Text(formatSpeed(v))
                    }
                }
            }
            Divider()
            Button(String(localized: "Custom…", table: "Common")) {
                customSpeedText = String(format: "%g", macro.speed)
                showCustomSpeed = true
            }
        }
    }

    @ViewBuilder
    func colorSubmenu() -> some View {
        let currentAccent = accentName
        Menu(String(localized: "Color", table: "Common")) {
            Button {
                onSetAccent(nil)
            } label: {
                AccentMenuLabel(name: nil, isSelected: currentAccent == nil)
            }
            Divider()
            ForEach(accentNames, id: \.self) { name in
                let selected = currentAccent == normalizedAccentName(name)
                Button {
                    onSetAccent(name)
                } label: {
                    AccentMenuLabel(name: name, isSelected: selected)
                }
            }
        }
    }

    @ViewBuilder
    func chainSubmenu() -> some View {
        let candidates = chainCandidates.filter { $0.0 != macro.id }
        Menu(String(localized: "Chain To", table: "Common")) {
            Button {
                onSetChain(nil)
            } label: {
                if macro.chainTo == nil {
                    Label(String(localized: "None", table: "Common"), systemImage: "checkmark")
                } else {
                    Text("None", tableName: "Common")
                }
            }
            if !candidates.isEmpty { Divider() }
            ForEach(candidates, id: \.0) { (id, name) in
                Button {
                    onSetChain(id)
                } label: {
                    if macro.chainTo == id {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        }
    }

    func formatSpeed(_ v: Double) -> String {
        // 0.5 → "0.5×", 1.0 → "1×", 1.75 → "1.75×"
        let rounded = (v * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%g×", rounded)
    }

}

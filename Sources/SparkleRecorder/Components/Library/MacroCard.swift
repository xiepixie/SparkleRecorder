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
            .focusable()
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
	            .accessibilityAction(named: NSLocalizedString("Play", comment: "")) { onPlay() }
	            .accessibilityAction(named: NSLocalizedString("Edit", comment: "")) { onEdit() }
	            .accessibilityAction(named: macro.favorite ? NSLocalizedString("Remove favorite", comment: "") : NSLocalizedString("Add favorite", comment: "")) { onToggleFavorite() }
	            .accessibilityAction(named: NSLocalizedString("Rename", comment: "")) { onStartRename() }
	            .accessibilityAction(named: NSLocalizedString("Delete", comment: "")) { onDelete() }
	            .contextMenu { cardMenuItems(includePlayEdit: true) }
	            .alert(NSLocalizedString("Custom playback speed", comment: ""), isPresented: $showCustomSpeed) {
	                TextField(NSLocalizedString("e.g. 1.75", comment: ""), text: $customSpeedText)
	                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
	                Button(NSLocalizedString("Set", comment: "")) {
                    let trimmed = customSpeedText.trimmingCharacters(in: .whitespaces)
                    if let v = Double(trimmed) {
                        onSetSpeed(max(0.1, min(10.0, v)))
                    }
                }
            } message: {
                Text(NSLocalizedString("Multiplier between 0.1× and 10×.", comment: ""))
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
	            Button { onPlay() } label: { Label(NSLocalizedString("Play", comment: ""), systemImage: "play.fill") }
	            Button { onEdit() } label: { Label(NSLocalizedString("Edit…", comment: ""), systemImage: "slider.horizontal.below.rectangle") }
	            Divider()
	        }
	        Button { onStartRename() } label: { Label(NSLocalizedString("Rename…", comment: ""), systemImage: "pencil") }
	        Button { onToggleFavorite() } label: {
	            Label(macro.favorite ? NSLocalizedString("Unfavorite", comment: "") : NSLocalizedString("Favorite", comment: ""), systemImage: macro.favorite ? "star.slash" : "star")
	        }
	        Divider()
	        Button { onOpenNotes() } label: { Label(NSLocalizedString("Notes…", comment: ""), systemImage: "text.alignleft") }
	        Button(action: onAddTag) { Label(NSLocalizedString("Add Tag…", comment: ""), systemImage: "tag") }
	        Button { onAssignHotkey() } label: { Label(NSLocalizedString("Assign Hotkey…", comment: ""), systemImage: "keyboard") }
	        if macro.hotkey != nil {
	            Button { onClearHotkey() } label: { Label(NSLocalizedString("Clear Hotkey", comment: ""), systemImage: "keyboard.badge.ellipsis") }
	        }
	        Divider()
	        
	        Button { controller.bindCurrentWindow(to: macro.id) } label: { Label(NSLocalizedString("Bind Active Window", comment: ""), systemImage: "window.badge.key") }
	        if macro.surfaces.values.first != nil {
	            Button(action: { controller.library.setFollowWindowOffset(id: macro.id, enabled: !macro.followWindowOffset) }) {
	                Label(NSLocalizedString("Follow Window Position", comment: ""), systemImage: macro.followWindowOffset ? "checkmark.circle" : "circle")
	            }
	            Button { controller.clearWindowBinding(for: macro.id) } label: { Label(NSLocalizedString("Clear Window Binding", comment: ""), systemImage: "xmark.rectangle") }
	        }
	        Divider()

        speedSubmenu()
        colorSubmenu()
        chainSubmenu()
        Divider()
	        Button { onDuplicate() } label: { Label(NSLocalizedString("Duplicate", comment: ""), systemImage: "plus.square.on.square") }
	        Menu(NSLocalizedString("Export", comment: "")) {
	            Button { onExport() } label: { Label(NSLocalizedString("As SparkleRecorder File…", comment: ""), systemImage: "doc.badge.plus") }
	            Button { onExportText() } label: { Label(NSLocalizedString("As Text…", comment: ""), systemImage: "doc.plaintext") }
	        }
	        Divider()
	        Button(role: .destructive) { onDelete() } label: { Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash") }
	    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Title row
            HStack(spacing: 6) {
                MacroIconView(macro: macro, onSetIcon: onSetIcon)

                if isRenaming {
                    TextField(NSLocalizedString("Name", comment: ""), text: $renameText, onCommit: onCommitRename)
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                renameFocused = true
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
                    .help(NSLocalizedString("Has notes — click to open", comment: ""))
                }

                if let hk = macro.hotkey {
                    Button(action: onAssignHotkey) {
                        KeyCapView(text: hk.name)
                    }
                    .buttonStyle(.plain)
                    .help(String(format: NSLocalizedString("Hotkey: %@ — click to change", comment: ""), hk.name))
                    .accessibilityLabel(String(format: NSLocalizedString("Change hotkey %@", comment: ""), hk.name))
                }

                Button(action: onToggleFavorite) {
                    Image(systemName: macro.favorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(macro.favorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .help(macro.favorite ? NSLocalizedString("Unstar", comment: "") : NSLocalizedString("Star", comment: ""))
                .accessibilityLabel(macro.favorite ? NSLocalizedString("Remove favorite", comment: "") : NSLocalizedString("Add favorite", comment: ""))
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
                    Text(String(format: NSLocalizedString("Bound: %@ (%dx%d)", comment: ""), surface.appName ?? NSLocalizedString("Window", comment: ""), Int(surface.recordedFrame.width), Int(surface.recordedFrame.height)))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if macro.followWindowOffset {
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text(NSLocalizedString("Offset dx/dy enabled", comment: ""))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        withAnimation(stateAnimation) {
                            controller.clearWindowBinding(for: macro.id)
                        }
                    }) {
                        Label(NSLocalizedString("Clear window binding", comment: ""), systemImage: "xmark")
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
                    .help(NSLocalizedString("Clear window binding", comment: ""))
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
                CardActionButton(systemImage: "play.fill", tint: Brand.libraryGreen, label: String(format: NSLocalizedString("Play %@", comment: ""), macro.name)) { onPlay() }
                    .help(NSLocalizedString("Play", comment: ""))
                LoopChip(loops: macro.loops, onChange: onSetLoops)
                CardActionButton(systemImage: "slider.horizontal.below.rectangle", tint: Brand.libraryBlue, label: String(format: NSLocalizedString("Edit %@", comment: ""), macro.name)) { onEdit() }
                    .help(NSLocalizedString("Edit", comment: ""))
	                Menu {
	                    cardMenuItems(includePlayEdit: false)
	                } label: {
	                    Label(NSLocalizedString("More actions", comment: ""), systemImage: "ellipsis")
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
	                .accessibilityLabel(NSLocalizedString("More actions", comment: ""))
            }
        }
    }

    /// What VoiceOver reads for the whole card.
    private var accessibilitySummary: String {
        var parts = [macro.name, durationText]
        if macro.playCount > 0 {
            parts.append(String(format: NSLocalizedString("played %d times", comment: ""), macro.playCount))
        }
        if let hotkey = macro.hotkey {
            parts.append(String(format: NSLocalizedString("hotkey %@", comment: ""), hotkey.name))
        }
        if let accentName {
            parts.append(String(format: NSLocalizedString("color %@", comment: ""), accentDisplayName(accentName)))
        }
        if macro.favorite {
            parts.append(NSLocalizedString("favorite", comment: ""))
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
                    .help(chainTargetName.map { String(format: NSLocalizedString("Chains to %@", comment: ""), $0) } ?? NSLocalizedString("Chained", comment: ""))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Submenus

    @ViewBuilder
    func speedSubmenu() -> some View {
        Menu(NSLocalizedString("Speed", comment: "")) {
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
            Button(NSLocalizedString("Custom…", comment: "")) {
                customSpeedText = String(format: "%g", macro.speed)
                showCustomSpeed = true
            }
        }
    }

    @ViewBuilder
    func colorSubmenu() -> some View {
        let currentAccent = accentName
        Menu(NSLocalizedString("Color", comment: "")) {
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
        Menu(NSLocalizedString("Chain To", comment: "")) {
            Button {
                onSetChain(nil)
            } label: {
                if macro.chainTo == nil {
                    Label(NSLocalizedString("None", comment: ""), systemImage: "checkmark")
                } else {
                    Text(NSLocalizedString("None", comment: ""))
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

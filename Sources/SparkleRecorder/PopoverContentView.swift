import SwiftUI
import AppKit
@preconcurrency import Combine
import UniformTypeIdentifiers
import SparkleRecorderCore

// MARK: - Root view

struct PopoverContentView: View {
    let controller: MenuBarController
    /// `true` when hosted in the resizable Dock window, `false` for the menu-bar popover.
    var isWindow: Bool = false
    @ObservedObject private var recorder: Recorder

    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: MacroLibrary

    @State private var search: String = ""
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @State private var selection: Set<UUID> = []
    @State private var filter: LibraryFilter = .all
    @State private var showAssignHotkey: SavedMacro?
    @State private var showAddTag: SavedMacro?
    @State private var showNotesFor: SavedMacro?
    @State private var newTagText: String = ""
    @State private var notesDraft: String = ""
    @State private var isDroppingFiles = false
    @State private var workspace: WorkspaceMode = .library
    /// Deterministic anchor for shift-click range selection.
    @State private var lastAnchorID: UUID?

    private var filteredMacros: [SavedMacro] {
        library.macros(for: filter, search: search)
    }

    init(controller: MenuBarController, isWindow: Bool = false) {
        self.controller = controller
        self.isWindow = isWindow
        _recorder = ObservedObject(initialValue: controller.recorder)
    }

    private var usesRecordingPopover: Bool {
        !isWindow && state.isRecording
    }

    private var filteredMacroCountForAnimation: Int {
        usesRecordingPopover ? 0 : filteredMacros.count
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: isWindow ? .windowBackground : .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if usesRecordingPopover {
                RecordingMenuBarPopoverView(
                    controller: controller,
                    recorder: recorder,
                    state: state
                )
            } else if isWindow {
                VStack(spacing: 0) {
                    // Custom titlebar strip: wordmark centered, traffic lights
                    // live in the leading inset.
                    ZStack {
                        BrandTitleStrip()
                    }
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background(VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow))
                    .overlay(Divider().opacity(0.5), alignment: .bottom)

                    switch workspace {
                    case .library:
                        HStack(spacing: 0) {
                            LibrarySidebar(filter: $filter)
                                .frame(width: 200)
                            Divider().opacity(0.5)
                            libraryColumn
                        }

                    case .automation:
                        AutomationMainView(runtimeHost: controller.automationHost())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider().opacity(0.5)
                    LibraryFooter(controller: controller, state: state, workspace: $workspace)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .ignoresSafeArea(edges: .top)
            } else {
                VStack(spacing: 0) {
                    libraryColumn
                    Divider().opacity(0.5)
                    LibraryFooter(controller: controller, state: state, workspace: $workspace)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }

            // File-drop overlay (shown only while user is dragging .tinyrec files in)
            if isDroppingFiles {
                ZStack {
                    Color.accentColor.opacity(0.10)
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.tint)
	                        Text(NSLocalizedString("Drop to import", comment: ""))
	                            .font(.system(size: 13, weight: .semibold))
	                            .foregroundStyle(.primary)
	                        Text(NSLocalizedString("Drop a .tinyrec, legacy Windows .rec, or .txt macro.", comment: ""))
	                            .font(.system(size: 10.5))
	                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.7),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .padding(8)
                )
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .frame(
            minWidth: usesRecordingPopover ? 320 : (isWindow ? 600 : 400),
            idealWidth: usesRecordingPopover ? 320 : (isWindow ? 880 : 400),
            maxWidth: usesRecordingPopover ? 320 : (isWindow ? .infinity : 400),
            minHeight: usesRecordingPopover ? 236 : (isWindow ? 520 : 540),
            idealHeight: usesRecordingPopover ? 236 : (isWindow ? 620 : 540),
            maxHeight: usesRecordingPopover ? 236 : (isWindow ? .infinity : 540)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.accessibilityGranted)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.inputMonitoringGranted)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: usesRecordingPopover)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: filteredMacroCountForAnimation)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: filter)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: workspace)
        .onChange(of: filter) { selection.removeAll() }
        .sheet(item: $showAssignHotkey) { macro in
            HotkeyAssignmentSheet(
                macro: macro,
                currentHotkey: macro.hotkey,
                allHotkeys: usedHotkeys,
                onSave: { binding in
                    controller.setMacroHotkey(macro.id, to: binding)
                    showAssignHotkey = nil
                },
                onCancel: { showAssignHotkey = nil }
            )
        }
        .sheet(item: $showAddTag) { macro in
            TagAssignmentSheet(
                macro: macro,
                allTags: library.allTags,
                tagText: $newTagText,
                onAdd: { tag in
                    controller.addTag(macro.id, tag)
                    newTagText = ""
                },
                onRemove: { tag in controller.removeTag(macro.id, tag) },
                onDone: { showAddTag = nil; newTagText = "" }
            )
        }
        .sheet(item: $showNotesFor) { macro in
            NotesSheet(
                macro: macro,
                text: $notesDraft,
                onSave: {
                    controller.setMacroNotes(macro.id, to: notesDraft)
                    showNotesFor = nil
                },
                onCancel: { showNotesFor = nil }
            )
            .onAppear { notesDraft = macro.notes }
        }
        .animation(.easeInOut(duration: 0.15), value: isDroppingFiles)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDroppingFiles) { providers in
            handleFileDrop(providers: providers)
        }
    }

    /// Importable macro file extensions accepted via drag-and-drop.
    private static let importableExts: Set<String> = ["tinyrec", "rec", "txt", "trm", "json"]

    /// Returns `true` if any provider was a macro file URL we accepted.
    func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        let importableExts = Self.importableExts
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, importableExts.contains(url.pathExtension.lowercased()) else { return }
                DispatchQueue.main.async {
                    controller.importMacro(at: url)
                }
            }
        }
        return accepted
    }

    private var usedHotkeys: Set<UInt32> {
        var s: Set<UInt32> = [
            state.recordHotkey.keyCode,
            state.stopHotkey.keyCode,
            state.playHotkey.keyCode,
        ]
        for m in library.macros { if let hk = m.hotkey { s.insert(hk.keyCode) } }
        return s
    }

    private var libraryColumn: some View {
        LibraryMainView(
            controller: controller,
            isWindow: isWindow,
            filter: $filter,
            search: $search,
            selection: $selection,
            renamingID: $renamingID,
            renameText: $renameText,
            showAssignHotkey: $showAssignHotkey,
            showAddTag: $showAddTag,
            showNotesFor: $showNotesFor,
            handleCardSelect: handleCardSelect
        )
    }



    func handleCardSelect(macro: SavedMacro, event: NSEvent.ModifierFlags) {
        if event.contains(.command) {
            // Toggle in selection
            if selection.contains(macro.id) {
                selection.remove(macro.id)
            } else {
                selection.insert(macro.id)
            }
            lastAnchorID = macro.id
        } else if event.contains(.shift), let lastID = lastAnchorID ?? library.currentMacroID,
                  let lastIdx = filteredMacros.firstIndex(where: { $0.id == lastID }),
                  let thisIdx = filteredMacros.firstIndex(where: { $0.id == macro.id }) {
            let lo = min(lastIdx, thisIdx)
            let hi = max(lastIdx, thisIdx)
            selection.formUnion(filteredMacros[lo...hi].map(\.id))
        } else {
            selection.removeAll()
            lastAnchorID = macro.id
            controller.selectMacro(macro.id)
        }
    }
}

@MainActor
private final class RecordingPopoverSnapshotModel: ObservableObject {
    @Published private(set) var durationText = "00:00"
    @Published private(set) var stats = RecordingStats.zero

    private weak var recorder: Recorder?
    private var refreshTask: Task<Void, Never>?

    init(recorder: Recorder) {
        self.recorder = recorder
        stats = recorder.liveStats
        refreshDuration()

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshDuration()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func updateStats(_ stats: RecordingStats) {
        self.stats = stats
    }

    private func refreshDuration() {
        let totalSeconds = max(0, Int(recorder?.liveDuration ?? 0))
        durationText = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct RecordingMenuBarPopoverView: View {
    let controller: MenuBarController
    private let recorder: Recorder
    @ObservedObject private var state: AppState
    @StateObject private var model: RecordingPopoverSnapshotModel

    private var eventCount: Int {
        model.stats.clicks + model.stats.keys + model.stats.scrolls + model.stats.drags
    }

    init(controller: MenuBarController, recorder: Recorder, state: AppState) {
        self.controller = controller
        self.recorder = recorder
        _state = ObservedObject(initialValue: state)
        _model = StateObject(wrappedValue: RecordingPopoverSnapshotModel(recorder: recorder))
    }

    var body: some View {
        let stats = model.stats
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                RecDot(size: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Recording", comment: "").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.durationText)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .frame(width: 92, alignment: .leading)
                }
                Spacer()
                Text("\(eventCount)")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Brand.sigTeal)
                    .frame(width: 64, height: 32)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                    )
                    .accessibilityLabel("\(eventCount) \(NSLocalizedString("events", comment: ""))")
            }

            HStack(spacing: 7) {
                RecordingPopoverStat(icon: "cursorarrow.click", value: stats.clicks, tint: Brand.sigGreen)
                RecordingPopoverStat(icon: "keyboard", value: stats.keys, tint: Brand.sigBlue)
                RecordingPopoverStat(icon: "arrow.up.and.down", value: stats.scrolls, tint: Brand.sigTeal)
                RecordingPopoverStat(icon: "hand.draw", value: stats.drags, tint: Brand.sigViolet)
            }

            HStack(spacing: 8) {
                Button {
                    controller.cancelRecording()
                } label: {
                    Label(NSLocalizedString("Discard", comment: ""), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: nil))
                .help(state.stopHotkey.name)

                Button {
                    controller.toggleRecording()
                } label: {
                    Label(NSLocalizedString("Stop", comment: ""), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.red500))
                .help(state.recordHotkey.name)
            }

            HStack(spacing: 8) {
                Button {
                    controller.showSettingsWindow()
                } label: {
                    Label(NSLocalizedString("Settings", comment: ""), systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.libraryBlue, isQuiet: true))

                Button {
                    controller.showMainWindow()
                } label: {
                    Label(NSLocalizedString("Library", comment: ""), systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.libraryBlue, isQuiet: true))
            }
        }
        .padding(14)
        .frame(width: 320, height: 236, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onReceive(recorder.$liveStats.removeDuplicates()) { stats in
            model.updateStats(stats)
        }
    }
}

private struct RecordingPopoverStat: View {
    let icon: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 13)
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

private struct RecordingPopoverButtonStyle: ButtonStyle {
    var tint: Color?
    var isQuiet = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let accent = tint ?? Color.primary
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint == nil || isQuiet ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fillStyle(accent: accent, pressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(accent.opacity(tint == nil ? 0.12 : 0.22), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? .linear(duration: 0.01) : Brand.pressAnimation, value: configuration.isPressed)
    }

    private func fillStyle(accent: Color, pressed: Bool) -> AnyShapeStyle {
        if tint == nil {
            return AnyShapeStyle(Color.primary.opacity(pressed ? 0.11 : 0.055))
        }
        if isQuiet {
            return AnyShapeStyle(accent.opacity(pressed ? 0.16 : 0.08))
        }
        return AnyShapeStyle(Brand.redGradient)
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case library
    case automation

    var id: Self { self }

    var title: String {
        switch self {
        case .library:
            NSLocalizedString("Library", comment: "")
        case .automation:
            NSLocalizedString("Automation", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "rectangle.stack"
        case .automation:
            "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
}

// MARK: - Filter chips (popover mode)

// Extracted FilterChipRow.swift


// MARK: - Sidebar (window mode)

// Extracted LibrarySidebar.swift


// Extracted StatsSummary.swift


// MARK: - Header

// Extracted LibraryHeader.swift


// MARK: - Selection toolbar

// Extracted SelectionToolbar.swift


// MARK: - Macro card

// Extracted MacroCard.swift


// MARK: - Card pieces

// Extracted MacroIconView.swift


// Extracted CardActionButton.swift


// MARK: - Mini waveform

// Extracted MiniWaveform.swift


// MARK: - Empty state

// Extracted EmptyState.swift


// MARK: - Footer

// Extracted LibraryFooter.swift


// Extracted FooterRow.swift


// MARK: - Permission banner

// Extracted PermissionBanner.swift


// MARK: - Loop chip

// Extracted LoopChip.swift


// MARK: - Hotkey assignment sheet

// Extracted HotkeyAssignmentSheet.swift


// MARK: - Notes sheet

// Extracted NotesSheet.swift


// MARK: - Tag assignment sheet

// Extracted TagAssignmentSheet.swift


// Extracted FlowChips.swift


// MARK: - Settings panel

// Extracted SettingsPanel.swift


// MARK: - Pill button style

// Extracted PillButtonStyle.swift

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SparkleRecorderCore

// MARK: - Root view

struct PopoverContentView: View {
    let controller: MenuBarController
    /// `true` when hosted in the resizable Dock window, `false` for the menu-bar popover.
    var isWindow: Bool = false

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

    var body: some View {
        ZStack {
            VisualEffectBackground(material: isWindow ? .windowBackground : .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            if isWindow {
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
            minWidth: isWindow ? 600 : 400,
            idealWidth: isWindow ? 880 : 400,
            maxWidth: isWindow ? .infinity : 400,
            minHeight: isWindow ? 520 : 540,
            idealHeight: isWindow ? 620 : 540,
            maxHeight: isWindow ? .infinity : 540
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.accessibilityGranted)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.inputMonitoringGranted)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: filteredMacros.count)
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

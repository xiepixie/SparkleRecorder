import SwiftUI
import AppKit
import SparkleRecorderCore

struct LibraryMainView: View {
    let controller: MenuBarController
    let isWindow: Bool

    @EnvironmentObject var state: AppState
    @EnvironmentObject var library: MacroLibrary
    
    @Binding var filter: LibraryFilter
    @Binding var search: String
    @Binding var selection: Set<UUID>
    @Binding var renamingID: UUID?
    @Binding var renameText: String
    @Binding var showAssignHotkey: SavedMacro?
    @Binding var showAddTag: SavedMacro?
    @Binding var showNotesFor: SavedMacro?
    @State private var showSequenceBuilderFor: [SavedMacro]?
    
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    
    // Derived properties
    var filteredMacros: [SavedMacro] {
        library.macros(for: filter, search: search)
    }
    
    let handleCardSelect: (SavedMacro, NSEvent.ModifierFlags) -> Void
    
    var body: some View {
        let filtered = filteredMacros
        let visibleSelection = selection.intersection(Set(filtered.map(\.id)))
        let chainCandidates = library.macros.map { ($0.id, $0.name) }
        let chainNameByID = Dictionary(uniqueKeysWithValues: chainCandidates)
        
        VStack(spacing: 0) {
            LibraryHeader(
                controller: controller,
                search: $search,
                showSearch: $showSearch,
                isWindow: isWindow,
                macroCount: library.macros.count
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !state.accessibilityGranted || !state.inputMonitoringGranted || !state.screenCaptureGranted {
                PermissionBanner(
                    controller: controller,
                    accessibilityGranted: state.accessibilityGranted,
                    inputMonitoringGranted: state.inputMonitoringGranted,
                    screenCaptureGranted: state.screenCaptureGranted
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isWindow {
                LibraryWorkflowActionStrip(
                    macroCount: library.macros.count,
                    hasCurrentMacro: library.currentMacroID != nil,
                    visualEvidenceEnabled: state.semanticRecordingEnabled,
                    isRecording: state.isRecording,
                    onReview: { controller.openEditor() },
                    onWorkflow: { controller.showAutomationWorkspace() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !visibleSelection.isEmpty {
                SelectionToolbar(
                    selectionCount: visibleSelection.count,
                    onClearSelection: { selection.removeAll() },
                    onDelete: {
                        controller.deleteMacros(visibleSelection)
                        selection.removeAll()
                    },
                    onExport: {
                        for id in visibleSelection { controller.exportMacroToFile(id) }
                    },
                    onAddTag: {
                        if let firstID = visibleSelection.first,
                           let m = library.macros.first(where: { $0.id == firstID }) {
                            showAddTag = m
                        }
                    },
                    onCreateSequence: {
                        var arr = [SavedMacro]()
                        for id in visibleSelection {
                            if let m = library.macros.first(where: { $0.id == id }) {
                                arr.append(m)
                            }
                        }
                        showSequenceBuilderFor = arr
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Filter chips — brings the window sidebar's filters to the popover.
            if !isWindow {
                FilterChipRow(filter: $filter, tags: library.allTags)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if filtered.isEmpty {
                EmptyState(filter: filter, hasSearch: !search.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Section label, mockup-style.
                    HStack {
                        Text(filter.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("\(filtered.count)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 6)

                    if isWindow {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 12, alignment: .top)],
                            spacing: 12
                        ) {
                            ForEach(filtered) { macro in
                                MacroCard(
                                    macro: macro,
                                    controller: controller,
                                    isCurrent: macro.id == library.currentMacroID,
                                    isSelected: selection.contains(macro.id),
                                    isRenaming: renamingID == macro.id,
                                    renameText: $renameText,
                                    onSelect: { event in
                                        handleCardSelect(macro, event)
                                    },
                                    onPlay: {
                                        selection.removeAll()
                                        controller.playMacroByID(macro.id)
                                    },
                                    onEdit: {
                                        selection.removeAll()
                                        controller.selectMacro(macro.id)
                                        controller.openEditor()
                                    },
                                    onDelete: {
                                        selection.remove(macro.id)
                                        controller.deleteMacro(macro.id)
                                    },
                                    onDuplicate: {
                                        controller.duplicateMacro(macro.id)
                                    },
                                    onExport: {
                                        controller.exportMacroToFile(macro.id)
                                    },
                                    onExportText: {
                                        controller.exportMacroAsText(macro.id)
                                    },
                                    onStartRename: {
                                        renamingID = macro.id
                                        renameText = macro.name
                                    },
                                    onCommitRename: {
                                        if let id = renamingID {
                                            controller.renameMacro(id, to: renameText)
                                        }
                                        renamingID = nil
                                    },
                                    onSetLoops: { newLoops in
                                        controller.setMacroLoops(macro.id, to: newLoops)
                                    },
                                    onAssignHotkey: { showAssignHotkey = macro },
                                    onClearHotkey: { controller.setMacroHotkey(macro.id, to: nil) },
                                    onToggleFavorite: { controller.toggleFavorite(macro.id) },
                                    onSetIcon: { icon in controller.setMacroIcon(macro.id, to: icon) },
                                    onAddTag: { showAddTag = macro },
                                    onDragMove: { fromID, toID in
                                        library.move(id: fromID, before: toID)
                                    },
                                    onOpenNotes: { showNotesFor = macro },
                                    onSetSpeed: { speed in
                                        controller.setMacroSpeed(macro.id, to: speed)
                                    },
                                    onSetAccent: { color in
                                        controller.setMacroAccent(macro.id, to: color)
                                    },
                                    onSetChain: { target in
                                        controller.setChain(macro.id, to: target)
                                    },
                                    chainCandidates: chainCandidates,
                                    chainTargetName: macro.chainTo.flatMap { chainNameByID[$0] },
                                    onCreateSequence: { showSequenceBuilderFor = [macro] }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { macro in
                                CompactMacroRow(
                                    macro: macro,
                                    controller: controller,
                                    isCurrent: macro.id == library.currentMacroID,
                                    isSelected: selection.contains(macro.id),
                                    onSelect: { event in
                                        handleCardSelect(macro, event)
                                    },
                                    onPlay: {
                                        selection.removeAll()
                                        controller.playMacroByID(macro.id)
                                    },
                                    onEdit: {
                                        selection.removeAll()
                                        controller.selectMacro(macro.id)
                                        controller.openEditor()
                                    },
                                    onSetIcon: { icon in
                                        controller.setMacroIcon(macro.id, to: icon)
                                    },
                                    onAssignHotkey: {
                                        showAssignHotkey = macro
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !state.statusMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                    Text(state.statusMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(white: 0.15).opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .padding(.bottom, 60) // hover slightly above footer
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.statusMessage.isEmpty)
                .onAppear { scheduleStatusClear() }
                .onChange(of: state.statusMessage) { scheduleStatusClear() }
            }
        }
        .overlay(alignment: .bottom) {
            if showSearch || !search.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Search macros...", table: "EditorUX"), text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($searchFocused)
                        .onAppear {
                            searchFocused = true
                        }
                    
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Clear search", table: "Common"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onChange(of: showSearch) { _, newValue in if newValue { searchFocused = true } }
            }
        }
        .background {
            // Invisible button to catch Cmd+K
            Button("") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSearch.toggle()
                    if showSearch {
                        searchFocused = true
                    } else if search.isEmpty {
                        searchFocused = false
                    }
                }
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()
        }
        .onChange(of: searchFocused) { _, focused in
            if !focused && search.isEmpty {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSearch = false
                }
            }
        }
        .sheet(item: Binding(
            get: { showSequenceBuilderFor != nil ? SequenceBuilderSheetItem() : nil },
            set: { if $0 == nil { showSequenceBuilderFor = nil } }
        )) { _ in
            if let macros = showSequenceBuilderFor {
                AutomationSequentialBuilderSheet(initialMacros: macros, onCreate: { doc in
                    let id = UUID()
                    var options = AutomationWorkflowDraftImportOptions(mode: .confirm)
                    options.stableIDNamespace = id.uuidString
                    
                    let result = AutomationWorkflowDraftImporter.compile(
                        doc,
                        options: options
                    )
                    
                    if var imported = result.workflow {
                        imported.id = id
                        controller.appState.automationSession?.createWorkflow(id: id, workflow: imported)
                        
                        DispatchQueue.main.async {
                            NSApp.sendAction(Selector(("showAutomationWorkspace:")), to: nil, from: nil)
                        }
                    }
                })
            }
        }
    }
    
    /// Clears the status line a few seconds after the latest message.
    func scheduleStatusClear() {
        let snapshot = state.statusMessage
        guard !snapshot.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if state.statusMessage == snapshot {
                withAnimation(.easeOut(duration: 0.25)) { state.statusMessage = "" }
            }
        }
    }
}

private struct LibraryWorkflowActionStrip: View {
    let macroCount: Int
    let hasCurrentMacro: Bool
    let visualEvidenceEnabled: Bool
    let isRecording: Bool
    let onReview: () -> Void
    let onWorkflow: () -> Void

    private var statusText: String {
        if isRecording {
            return String(localized: "Recording active", table: "Recording")
        }
        let format = String(localized: "%d saved", table: "Common")
        return String(format: format, macroCount)
    }

    private var evidenceText: String {
        visualEvidenceEnabled
            ? String(localized: "Visual evidence on", table: "Automation")
            : String(localized: "Visual evidence off", table: "Automation")
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.libraryBlue)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(evidenceText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            libraryWorkflowButton(
                title: String(localized: "Review", table: "Common"),
                detail: String(localized: "Current macro", table: "EditorUX"),
                systemImage: "slider.horizontal.below.rectangle",
                isEnabled: hasCurrentMacro,
                action: onReview
            )

            libraryWorkflowButton(
                title: String(localized: "Workflow", table: "Automation"),
                detail: String(localized: "Schedule / repeat", table: "Common"),
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                isEnabled: macroCount > 0,
                action: onWorkflow
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func libraryWorkflowButton(
        title: String,
        detail: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 118, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isEnabled ? 0.045 : 0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(isEnabled ? 0.09 : 0.04), lineWidth: 0.5)
        )
        .help(isEnabled ? title : String(localized: "Record a macro first", table: "Recording"))
    }
}

private struct SequenceBuilderSheetItem: Identifiable, Equatable {
    let id = UUID()
}


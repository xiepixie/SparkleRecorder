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
    private let recorder: Recorder
    @ObservedObject private var player: Player

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
    /// Deterministic anchor for shift-click range selection.
    @State private var lastAnchorID: UUID?

    private var filteredMacros: [SavedMacro] {
        library.macros(for: filter, search: search)
    }

    init(controller: MenuBarController, isWindow: Bool = false) {
        self.controller = controller
        self.isWindow = isWindow
        recorder = controller.recorder
        _player = ObservedObject(initialValue: controller.player)
    }

    private var usesRecordingPopover: Bool {
        !isWindow && state.isRecording
    }

    private var usesRecordingFinalizationPopover: Bool {
        !isWindow && state.recordingFinalizationActive
    }

    private var usesRecordingPreparationPopover: Bool {
        !isWindow && state.recordingFlowActive && !state.isRecording
            && !state.recordingFinalizationActive
    }

    private var usesPlaybackPopover: Bool {
        !isWindow && !state.isRecording
            && (state.playbackFlowActive || player.isPlaybackTargetReserved || state.isPlaying)
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
            } else if usesRecordingFinalizationPopover {
                RecordingFinalizationMenuBarPopoverView(state: state)
            } else if usesRecordingPreparationPopover {
                RecordingPreparationMenuBarPopoverView(
                    controller: controller,
                    state: state
                )
            } else if usesPlaybackPopover {
                PlaybackMenuBarPopoverView(
                    controller: controller,
                    player: player,
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

                    switch state.workspace {
                    case .library:
                        HStack(spacing: 0) {
                            LibrarySidebar(filter: $filter)
                                .frame(width: 200)
                            Divider().opacity(0.5)
                            libraryColumn
                        }

                    case .automation:
                        AutomationMainView(
                            runtimeHost: controller.automationHost(),
                            onRecordMacro: { controller.toggleRecording() },
                            onPreviewScheduledMacro: { macroID, task in
                                try await controller.previewScheduledMacro(
                                    macroID,
                                    taskConfiguration: task
                                )
                            },
                            onRenameMacro: { macroID, name in
                                controller.renameMacro(macroID, to: name)
                            },
                            onSetMacroLoops: { macroID, loops in
                                controller.setMacroLoops(macroID, to: loops)
                            }
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider().opacity(0.5)
                    LibraryFooter(controller: controller, state: state, isWindow: isWindow, workspace: workspaceBinding)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .ignoresSafeArea(edges: .top)
            } else {
                VStack(spacing: 0) {
                    libraryColumn
                    Divider().opacity(0.5)
                    LibraryFooter(controller: controller, state: state, isWindow: isWindow, workspace: workspaceBinding)
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
	                        Text("Drop to import", tableName: "Common")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Drop a .tinyrec, legacy Windows .rec, or .txt macro.", tableName: "EditorUX")
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
        .disabled(isWindow && state.appInteractionLocked)
        .appStatusFeedbackOverlay(
            state: state,
            isWindow: isWindow,
            bottomPadding: 58,
            isEnabled: !usesRecordingPopover
                && !usesRecordingFinalizationPopover
                && !usesRecordingPreparationPopover
                && !usesPlaybackPopover
        )
        .frame(
            minWidth: usesRecordingPopover ? 320 : (isWindow ? 600 : 400),
            idealWidth: usesRecordingPopover ? 320 : (isWindow ? 880 : 400),
            maxWidth: usesRecordingPopover ? 320 : (isWindow ? .infinity : 400),
            minHeight: usesRecordingPopover ? 276 : (isWindow ? 520 : 540),
            idealHeight: usesRecordingPopover ? 276 : (isWindow ? 620 : 540),
            maxHeight: usesRecordingPopover ? 276 : (isWindow ? .infinity : 540)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: usesRecordingPopover)
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

    /// Returns `true` if any provider was a file URL. Import dispatch owns content
    /// sniffing, so drag-and-drop follows the same format rules and error feedback
    /// as Finder/open-panel imports instead of silently ignoring unknown extensions.
    func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    controller.importMacro(at: url)
                }
            }
        }
        return accepted
    }

    private var usedHotkeys: Set<HotkeyIdentity> {
        var identities = Set([
            state.recordHotkey.hotkeyIdentity,
            state.stopHotkey.hotkeyIdentity,
            state.playHotkey.hotkeyIdentity,
        ])
        for macro in library.macros {
            if let hotkey = macro.hotkey {
                identities.insert(hotkey.hotkeyIdentity)
            }
        }
        return identities
    }

    private var workspaceBinding: Binding<WorkspaceMode> {
        Binding(
            get: { state.workspace },
            set: { state.workspace = $0 }
        )
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
    @Published private(set) var semanticStatus: SemanticRecorderBridgeStatus = .idle

    private weak var recorder: Recorder?
    private var refreshTask: Task<Void, Never>?

    init(recorder: Recorder) {
        self.recorder = recorder
        stats = recorder.liveStats
        semanticStatus = recorder.semanticRecordingStatus
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
        guard self.stats != stats else { return }
        self.stats = stats
    }

    func updateSemanticStatus(_ status: SemanticRecorderBridgeStatus) {
        guard semanticStatus != status else { return }
        semanticStatus = status
    }

    private func refreshDuration() {
        let totalSeconds = max(0, Int(recorder?.liveDuration ?? 0))
        let text = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
        guard durationText != text else { return }
        durationText = text
    }
}

private struct RecordingFinalizationMenuBarPopoverView: View {
    @ObservedObject private var state: AppState

    init(state: AppState) {
        _state = ObservedObject(initialValue: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finishing recording…", tableName: "Recording")
                        .font(.headline)
                    Text("Finishing visual evidence and saving this macro. SparkleRecorder stays responsive; recording and playback will be available when this finishes.", tableName: "Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }

            Label(
                String(localized: "Saving evidence", table: "Automation"),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320, height: 150, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct RecordingPreparationMenuBarPopoverView: View {
    let controller: MenuBarController
    @ObservedObject private var state: AppState

    init(controller: MenuBarController, state: AppState) {
        self.controller = controller
        _state = ObservedObject(initialValue: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "record.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Brand.red500)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preparing recording…", tableName: "Recording")
                        .font(.headline)
                    Text(verbatim: state.statusFeedback?.message ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            ProgressView()
                .controlSize(.small)

            Button(role: .destructive) {
                controller.stopAll()
            } label: {
                Label(String(localized: "Cancel", table: "Common"), systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.red500))
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .frame(width: 320, height: 150, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct PlaybackMenuBarPopoverView: View {
    let controller: MenuBarController
    @ObservedObject private var player: Player
    @ObservedObject private var clock: PlaybackClock
    @ObservedObject private var state: AppState

    init(controller: MenuBarController, player: Player, state: AppState) {
        self.controller = controller
        _player = ObservedObject(initialValue: player)
        _clock = ObservedObject(initialValue: player.clock)
        _state = ObservedObject(initialValue: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: state.isPlaying ? "play.circle.fill" : "hourglass.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Brand.libraryGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        state.isPlaying
                            ? String(localized: "Playing", table: "Recording")
                            : String(localized: "Preparing playback…", table: "Recording")
                    )
                    .font(.headline)
                    Text(verbatim: state.statusFeedback?.message ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if state.isPlaying {
                ProgressView(value: min(1, max(0, clock.progress)))
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Button(role: .destructive) {
                controller.stopAll()
            } label: {
                Label(String(localized: "Stop", table: "Common"), systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.red500))
            .keyboardShortcut(.cancelAction)

            Label(
                String(localized: "Library and Settings stay locked until playback stops.", table: "Common"),
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320, height: 176, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
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
                    Text(String(localized: "Recording", table: "Recording").uppercased())
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
                    .accessibilityLabel("\(eventCount) \(String(localized: "events", table: "EditorUX"))")
            }

            HStack(spacing: 7) {
                RecordingPopoverStat(icon: "cursorarrow.click", value: stats.clicks, tint: Brand.sigGreen)
                RecordingPopoverStat(icon: "keyboard", value: stats.keys, tint: Brand.sigBlue)
                RecordingPopoverStat(icon: "arrow.up.and.down", value: stats.scrolls, tint: Brand.sigTeal)
                RecordingPopoverStat(icon: "hand.draw", value: stats.drags, tint: Brand.sigViolet)
            }

            HStack(spacing: 7) {
                RecordingPopoverStateBadge(
                    icon: visualEvidenceIcon,
                    title: visualEvidenceTitle,
                    tint: visualEvidenceTint
                )
                RecordingPopoverStateBadge(
                    icon: "tray.and.arrow.down.fill",
                    title: String(localized: "Stop saves to Library", table: "Common"),
                    tint: Brand.libraryBlue
                )
            }

            HStack(spacing: 8) {
                Button {
                    controller.cancelRecording()
                } label: {
                    Label(String(localized: "Discard", table: "Common"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: nil))
                .help(state.stopHotkey.name)

                Button {
                    controller.toggleRecording()
                } label: {
                    Label(String(localized: "Stop", table: "Common"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RecordingPopoverButtonStyle(tint: Brand.red500))
                .help(state.recordHotkey.name)
            }

            Label(
                String(localized: "Stop or discard to open Library or Settings.", table: "Common"),
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(
                String(localized: "Stop or discard to open Library or Settings.", table: "Common")
            )
        }
        .padding(14)
        .frame(width: 320, height: 276, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onReceive(
            recorder.$liveStats
                .removeDuplicates()
                .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
        ) { stats in
            model.updateStats(stats)
        }
        .onReceive(recorder.$semanticRecordingStatus.removeDuplicates()) { status in
            model.updateSemanticStatus(status)
        }
    }

    private var visualEvidenceTitle: String {
        guard state.semanticRecordingEnabled else {
            return String(localized: "Action recording", table: "Recording")
        }
        switch model.semanticStatus {
        case .starting:
            return String(localized: "Preparing evidence", table: "Automation")
        case .active:
            return String(localized: "Evidence recording", table: "Automation")
        case .finishing:
            return String(localized: "Saving evidence", table: "Automation")
        case .finished:
            return String(localized: "Evidence saved", table: "Automation")
        case .blocked, .failed:
            return String(localized: "Evidence issue", table: "Automation")
        case .suppressed:
            return String(localized: "Evidence stopped for privacy", table: "Automation")
        case .cancelled:
            return String(localized: "Evidence cancelled", table: "Automation")
        case .idle:
            return String(localized: "Evidence ready", table: "Automation")
        }
    }

    private var visualEvidenceIcon: String {
        guard state.semanticRecordingEnabled else {
            return "record.circle"
        }
        switch model.semanticStatus {
        case .blocked, .failed:
            return "exclamationmark.triangle.fill"
        case .suppressed:
            return "lock.shield.fill"
        case .finished:
            return "checkmark.circle.fill"
        default:
            return "film.stack.fill"
        }
    }

    private var visualEvidenceTint: Color {
        guard state.semanticRecordingEnabled else {
            return .secondary
        }
        switch model.semanticStatus {
        case .blocked, .failed:
            return .orange
        case .suppressed:
            return .purple
        case .finished:
            return .green
        default:
            return Brand.libraryBlue
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

private struct RecordingPopoverStateBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 13)
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.16), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
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
            String(localized: "Library", table: "Common")
        case .automation:
            String(localized: "Automation", table: "Automation")
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

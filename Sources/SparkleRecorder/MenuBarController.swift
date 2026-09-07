import Cocoa
import SwiftUI
import Combine
import UniformTypeIdentifiers
import SparkleRecorderCore

private struct RecordingPreparationVisibility {
    var appWasHidden: Bool
    var appWasActive: Bool
    var popoverWasShown: Bool
}

private enum RecordingStopContext {
    case normal
    case inputMonitoringRevoked
    case appBecameActive
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var globalClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var editorWC: EditorWindowController?
    private var candidateEditorWC: EditorWindowController?
    private var candidateEditorSession: MacroCandidateEditorSession?
    private var candidateEditorRecorder: Recorder?
    private var hud: RecordingHUDController?
    private var playbackHUD: PlaybackHUDController?
    private var countdown: CountdownOverlayController?
    private let windowTargetPicker = ScreenPointPickerOverlay()
    private var manualPlaybackTask: Task<Void, Never>?
    private let manualPlaybackVisibilitySession = ManualPlaybackVisibilitySession()
    private var playbackRequestGeneration: UInt64 = 0
    private var reconstructionTestActive = false
    private var recordingPreparationActive = false
    private var recordingPreparationTask: Task<Void, Never>?
    private var welcomeWC: WelcomeWindowController?

    let recorder = Recorder()
    let player = Player()
    let state = AppState()
    let library = MacroLibrary()
    private let automationSignalStore = AutomationSignalStore.shared
    private let automationRepository = AutomationRepositoryClient.fileBacked()
    private var automationRuntimeHost: LiveAutomationRuntimeHost?

    private var globalHotkeyIDs: [UInt32] = []
    private var perMacroHotkeyIDs: [UInt32: UUID] = [:]   // hotkey-id → macro id
    private var dockBadgeTimer: Timer?
    private var automationRunRetentionTimer: Timer?
    private var dockBadgeVisible = true
    private var playStartTime: CFAbsoluteTime = 0
    private var playingMacroID: UUID?
    /// Macros already visited in the current chain run — breaks A→B→A cycles.
    private var chainVisited: Set<UUID> = []
    private var settingsWC: SettingsWindowController?
    private var recordedSurface: PlaybackSurface?
    private var recorderLoadedMacroID: UUID?
    private var recorderLoadingMacroID: UUID?
    private var pendingSemanticRecordingMacroID: UUID?
    private var semanticSanitizationTask: Task<Void, Never>?
    private var recordingFinalizationTask: Task<Void, Never>?
    private var macroImportTail: Task<Void, Never>?
    private var pendingRecordingStartMessage: String?
    private var recordingPreparationVisibility: RecordingPreparationVisibility?
    private var pendingRelaunchRequest: ApplicationRelaunchRequest?
    private let auxiliaryCaptureActivityCenter = AuxiliaryCaptureActivityCenter.shared
    private var appInputSessionWasOwned = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        automationRuntimeHost = LiveAutomationRuntimeHost(
            player: player,
            repository: automationRepository,
            externalSignal: .appSignals(automationSignalStore),
            manualApproval: AutomationManualApprovalPresenter.client(),
            ocrSearchRegionContext: Self.automationOCRSearchRegionContext,
            foregroundInputAvailable: { [weak self] in
                await MainActor.run {
                    guard let self else { return false }
                    return !self.appInputSessionActivity.blocksForegroundInputStart
                }
            }
        )
        configureStatusItem()
        configurePopover()
        configureHUD()
        playbackHUD = PlaybackHUDController(player: player)
        countdown = CountdownOverlayController()
        observeStateForIcon()
        observeAppInputSessionOwnership()
        observeSemanticRecordingStatus()
        observeLibraryForHotkeys()
        observeLibraryIssues()
        observeLibrarySelectionForInitialEventLoad()
        observeRecordingPermissionRevocation()
        registerAllHotkeys()
        loadInitialMacroIntoRecorder()
        automationRuntimeHost?.start()
        scheduleSemanticRecordingRetentionCleanupIfNeeded()
        startAutomationRunRetentionMonitoring()
    }

    deinit {
        MainActor.assumeIsolated {
            automationRuntimeHost?.stop()
            if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
            HotkeyManager.shared.unregisterAll()
            dockBadgeTimer?.invalidate()
            automationRunRetentionTimer?.invalidate()
        }
    }

    // MARK: - Status item

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = SparkleIcons.idle
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("SparkleRecorder")
        }
    }

    private func observeStateForIcon() {
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                self?.state.isRecording = recording
                self?.refreshIcon()
                self?.updateDockBadge()
            }
            .store(in: &cancellables)
        recorder.$liveDuration
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self, self.recorder.isRecording else { return }
                guard self.state.recordingHUDMode == .menuBar else { return }
                self.refreshIcon()
            }
            .store(in: &cancellables)
        player.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.state.isPlaying = playing
                self?.refreshIcon()
                self?.updateDockBadge()
            }
            .store(in: &cancellables)
        state.$recordingHUDMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshIcon()
                self.showRecordingHUDIfNeeded()
            }
            .store(in: &cancellables)
        state.$recordingFinalizationActive
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
                self?.updateDockBadge()
            }
            .store(in: &cancellables)
    }

    private func observeAppInputSessionOwnership() {
        let signals: [AnyPublisher<Void, Never>] = [
            state.$recordingFlowActive.map { _ in () }.eraseToAnyPublisher(),
            state.$recordingFinalizationActive.map { _ in () }.eraseToAnyPublisher(),
            state.$playbackFlowActive.map { _ in () }.eraseToAnyPublisher(),
            recorder.$isRecording.map { _ in () }.eraseToAnyPublisher(),
            player.$isPlaybackTargetReserved.map { _ in () }.eraseToAnyPublisher(),
            player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            auxiliaryCaptureActivityCenter.$isActive.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(signals)
            // @Published emits from willSet. Hop through the main queue so the
            // projection reads the committed values from every owner.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshAppInputSessionOwnership()
            }
            .store(in: &cancellables)
    }

    private func refreshAppInputSessionOwnership() {
        let isOwned = appInputSessionActivity.ownsInputOrCaptureTarget
        let wasOwned = appInputSessionWasOwned
        appInputSessionWasOwned = isOwned
        state.setAppInteractionLocked(isOwned)
        if wasOwned && !isOwned {
            automationRuntimeHost?.foregroundInputBecameAvailable()
        }
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        if recorder.isRecording {
            button.image = SparkleIcons.recording
            button.title = state.recordingHUDMode == .menuBar ? recordingMenuBarTitle : " REC"
            button.setAccessibilityLabel(recordingMenuBarAccessibilityLabel)
        } else if state.recordingFinalizationActive {
            button.image = SparkleIcons.finalizing
            button.title = ""
            button.setAccessibilityLabel("SparkleRecorder — finishing recording")
        } else if player.isPlaying {
            button.image = SparkleIcons.playing
            button.title = ""
            button.setAccessibilityLabel("SparkleRecorder — playing")
        } else {
            button.image = SparkleIcons.idle
            button.title = ""
            button.setAccessibilityLabel("SparkleRecorder")
        }
    }

    private var recordingMenuBarTitle: String {
        " " + Self.recordingDurationText(recorder.liveDuration)
    }

    private var recordingMenuBarAccessibilityLabel: String {
        let seconds = Int(recorder.liveDuration)
        let eventCount = recorder.liveStats.clicks
            + recorder.liveStats.keys
            + recorder.liveStats.scrolls
            + recorder.liveStats.drags
        return "SparkleRecorder — recording, \(seconds) seconds, \(eventCount) events"
    }

    private static func recordingDurationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func updateDockBadge() {
        let tile = NSApp.dockTile
        if recorder.isRecording {
            tile.badgeLabel = "●"
            startBadgePulse()
        } else if state.recordingFinalizationActive {
            stopBadgePulse()
            tile.badgeLabel = "…"
        } else if player.isPlaying {
            stopBadgePulse()
            tile.badgeLabel = "▶"
        } else {
            stopBadgePulse()
            tile.badgeLabel = nil
        }
    }

    private func startBadgePulse() {
        guard dockBadgeTimer == nil else { return }
        dockBadgeVisible = true
        dockBadgeTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dockBadgeVisible.toggle()
                NSApp.dockTile.badgeLabel = self.dockBadgeVisible ? "●" : " "
            }
        }
    }

    private func stopBadgePulse() {
        dockBadgeTimer?.invalidate()
        dockBadgeTimer = nil
        dockBadgeVisible = true
    }

    // MARK: - Popover

    private func configurePopover() {
        popover.contentSize = NSSize(width: 400, height: 540)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let view = PopoverContentView(controller: self, isWindow: false)
            .environmentObject(state)
            .environmentObject(library)

        popover.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let inputSessionActive = state.recordingFlowActive || recorder.isRecording
            || state.recordingFinalizationActive
            || state.playbackFlowActive || player.isPlaybackTargetReserved || player.isPlaying
        popover.animates = !inputSessionActive
        if recorder.isRecording {
            popover.contentSize = NSSize(width: 320, height: 276)
        } else if state.recordingFinalizationActive {
            popover.contentSize = NSSize(width: 320, height: 150)
        } else if state.recordingFlowActive {
            popover.contentSize = NSSize(width: 320, height: 150)
        } else if state.playbackFlowActive || player.isPlaybackTargetReserved || player.isPlaying {
            popover.contentSize = NSSize(width: 320, height: 176)
        } else {
            popover.contentSize = NSSize(width: 400, height: 540)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !inputSessionActive {
            popover.contentViewController?.view.window?.becomeKey()
        }
        installGlobalClickMonitor()
    }

    private func installGlobalClickMonitor() {
        if let m = globalClickMonitor {
            NSEvent.removeMonitor(m)
            globalClickMonitor = nil
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = globalClickMonitor {
            NSEvent.removeMonitor(m)
            globalClickMonitor = nil
        }
    }

    func automationHost() -> LiveAutomationRuntimeHost {
        if let automationRuntimeHost {
            return automationRuntimeHost
        }

        let host = LiveAutomationRuntimeHost(
            player: player,
            repository: automationRepository,
            externalSignal: .appSignals(automationSignalStore),
            manualApproval: AutomationManualApprovalPresenter.client(),
            ocrSearchRegionContext: Self.automationOCRSearchRegionContext
        )
        automationRuntimeHost = host
        host.start()
        return host
    }

    private static func automationOCRSearchRegionContext(
        _: AutomationConditionEvaluationRequest,
        _ displayBounds: RectValue
    ) async -> AutomationOCRSearchRegionContext {
        await MainActor.run {
            guard let screen = NSScreen.main ?? NSScreen.screens.first,
                  let surface = try? WindowSurfaceCapture().captureFrontmostWindow() else {
                return AutomationOCRSearchRegionContext(displayBounds: displayBounds)
            }

            let screenFrame = topLeftFrame(for: screen)
            return AutomationOCRSearchRegionContext(
                displayBounds: displayBounds,
                windowFrame: displayRect(
                    from: surface.recordedFrame,
                    screenFrame: screenFrame,
                    displayBounds: displayBounds
                ),
                contentFrame: surface.recordedContentFrame.flatMap {
                    displayRect(
                        from: $0,
                        screenFrame: screenFrame,
                        displayBounds: displayBounds
                    )
                }
            )
        }
    }

    private static func topLeftFrame(for screen: NSScreen) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return screen.frame
        }
        let primaryHeight = primaryScreen.frame.height
        return CGRect(
            x: screen.frame.minX,
            y: primaryHeight - (screen.frame.minY + screen.frame.height),
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private static func displayRect(
        from rect: RectValue,
        screenFrame: CGRect,
        displayBounds: RectValue
    ) -> RectValue? {
        let globalRect = CGRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
        let clipped = globalRect.intersection(screenFrame)
        guard !clipped.isNull,
              clipped.width > 1,
              clipped.height > 1 else {
            return nil
        }

        let scaleX = displayBounds.width / max(1, screenFrame.width)
        let scaleY = displayBounds.height / max(1, screenFrame.height)
        return RectValue(
            x: displayBounds.x + (clipped.minX - screenFrame.minX) * scaleX,
            y: displayBounds.y + (clipped.minY - screenFrame.minY) * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        )
    }

    // MARK: - HUD

    private func configureHUD() {
        hud = RecordingHUDController(
            recorder: recorder,
            state: state,
            onDiscard: { [weak self] in self?.cancelRecording() },
            onStop:    { [weak self] in self?.toggleRecording() }
        )
    }

    private func showRecordingHUDIfNeeded() {
        guard recorder.isRecording else {
            hud?.hide()
            return
        }
        let mode = state.recordingHUDMode
        if mode.showsFloatingPanel {
            hud?.show(mode: mode)
        } else {
            hud?.hide()
        }
    }

    /// Stop recording and throw away the captured events without saving.
    /// The input tap stops immediately, but the app remains in Finalizing until
    /// semantic capture cancellation has removed its temporary bundle.
    func cancelRecording() {
        guard recorder.isRecording else { return }
        recorder.cancelRecording()
        state.isRecording = false
        state.recordingFlowActive = false
        recorder.clearAll()
        recorderLoadedMacroID = nil
        hud?.hide()
        SoundController.shared.play(.error)
        beginRecordingFinalization(
            savedMacroID: nil,
            eventCount: 0,
            completionMessage: String(localized: "Recording discarded.", table: "Recording"),
            completionTone: .info,
            restoreSelectedMacroAfterward: true
        )
    }

    // MARK: - Hotkeys

    private func observeLibraryForHotkeys() {
        // Re-register per-macro hotkeys when the library changes. Debounced so a
        // burst of mutations (rename keystrokes, playback stat updates) costs one
        // re-registration, and delayed past objectWillChange so we read the
        // library AFTER the mutation lands. DispatchQueue.main (not RunLoop.main)
        // so it still fires during event-tracking run-loop modes.
        library.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPerMacroHotkeys()
                self?.refreshIgnoredHotkeyChords()
            }
            .store(in: &cancellables)
        // Global-hotkey changes go through reapplyHotkeys() explicitly from the
        // settings UI — no state-wide sink needed.
    }

    private func observeLibraryIssues() {
        library.$issue
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] issue in
                guard let self else { return }
                switch issue {
                case .loadLibrary(let message):
                    self.state.presentStatus(
                        String(
                            format: String(localized: "Could not load the macro library: %@", table: "Common"),
                            message
                        ),
                        tone: .error
                    )
                case .readMacro(let message):
                    self.state.presentStatus(
                        String(
                            format: String(localized: "Could not read the macro data: %@", table: "Common"),
                            message
                        ),
                        tone: .error
                    )
                case .saveChanges(let message):
                    self.state.presentStatus(
                        String(
                            format: String(localized: "Could not save library changes: %@", table: "Common"),
                            message
                        ),
                        tone: .error
                    )
                }
                SoundController.shared.play(.error)
            }
            .store(in: &cancellables)
    }

    private func observeLibrarySelectionForInitialEventLoad() {
        library.$currentMacroID
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self, !self.recorder.isRecording else { return }
                self.loadMacroEventsIntoRecorder(id)
            }
            .store(in: &cancellables)
    }

    /// Input Monitoring owns the live event tap. While recording, AppState keeps
    /// polling permissions so a revocation cannot leave the UI pretending that
    /// capture is still active. Preserve every event captured before revocation as
    /// a normal new macro instead of leaving an orphaned in-memory buffer.
    private func observeRecordingPermissionRevocation() {
        state.$inputMonitoringGranted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self, !granted, self.recorder.isRecording else { return }
                _ = self.stopRecordingAndSave(context: .inputMonitoringRevoked)
                SoundController.shared.play(.error)
            }
            .store(in: &cancellables)
    }

    /// AppKit can activate SparkleRecorder independently of our own window guards
    /// (Dock click, Cmd-Tab, system reopen). Once the app itself is frontmost, a
    /// foreground input session can no longer trust the target application. Stop
    /// immediately instead of letting subsequent input land in SparkleRecorder.
    func handleApplicationDidBecomeActive() {
        state.refreshPermissions()

        switch AppActivationInterruptionPolicy.resolve(
            activity: appInputSessionActivity,
            recordingTargetHandoffArmed: recordingPreparationVisibility != nil
        ) {
        case .none:
            return

        case .cancelRecordingPreparation:
            stopAll()
            state.presentStatus(
                String(
                    localized: "Recording preparation was cancelled because SparkleRecorder became active. Return to the target app and start recording again.",
                    table: "Recording"
                ),
                tone: .warning
            )
            SoundController.shared.play(.error)

        case .saveInterruptedRecording:
            _ = stopRecordingAndSave(context: .appBecameActive)
            SoundController.shared.play(.error)

        case .stopPlayback:
            stopAll()
            state.presentStatus(
                String(
                    localized: "Playback stopped because SparkleRecorder became active. Return to the target app and start again.",
                    table: "Recording"
                ),
                tone: .warning
            )
            SoundController.shared.play(.error)
        }
    }

    private func registerAllHotkeys() {
        registerGlobalHotkeys()
        refreshPerMacroHotkeys()
        refreshIgnoredHotkeyChords()
    }

    private func registerGlobalHotkeys() {
        for id in globalHotkeyIDs { HotkeyManager.shared.unregister(id) }
        globalHotkeyIDs.removeAll()

        let recordH: () -> Void = { [weak self] in
            guard let self else { return }
            self.toggleRecording(triggeredBy: self.state.recordHotkey)
        }
        let stopH:   () -> Void = { [weak self] in self?.stopAll() }
        let playH:   () -> Void = { [weak self] in
            guard let self else { return }
            if self.state.playbackFlowActive || self.player.isPlaybackTargetReserved
                || self.player.isPlaying || self.manualPlaybackTask != nil
                || self.reconstructionTestActive {
                self.stopAll()
            } else {
                self.play(triggeredBy: self.state.playHotkey)
            }
        }

        if let id = HotkeyManager.shared.register(keyCode: state.recordHotkey.keyCode, modifiers: state.recordHotkey.modifiers, handler: recordH) {
            globalHotkeyIDs.append(id)
        }
        if let id = HotkeyManager.shared.register(keyCode: state.stopHotkey.keyCode, modifiers: state.stopHotkey.modifiers, handler: stopH) {
            globalHotkeyIDs.append(id)
        }
        if let id = HotkeyManager.shared.register(keyCode: state.playHotkey.keyCode, modifiers: state.playHotkey.modifiers, handler: playH) {
            globalHotkeyIDs.append(id)
        }
    }

    private func refreshPerMacroHotkeys() {
        for id in perMacroHotkeyIDs.keys { HotkeyManager.shared.unregister(id) }
        perMacroHotkeyIDs.removeAll()

        for macro in library.macros {
            guard let hk = macro.hotkey else { continue }
            // Skip if conflicts with global hotkeys.
            if (hk.keyCode == state.recordHotkey.keyCode && hk.modifiers == state.recordHotkey.modifiers) ||
               (hk.keyCode == state.stopHotkey.keyCode && hk.modifiers == state.stopHotkey.modifiers) ||
               (hk.keyCode == state.playHotkey.keyCode && hk.modifiers == state.playHotkey.modifiers) { continue }
            let macroID = macro.id
            if let id = HotkeyManager.shared.register(keyCode: hk.keyCode, modifiers: hk.modifiers, handler: { [weak self] in
                guard let self = self else { return }
                if self.state.playbackFlowActive || self.player.isPlaybackTargetReserved
                    || self.player.isPlaying || self.manualPlaybackTask != nil
                    || self.reconstructionTestActive {
                    self.stopAll()
                } else {
                    self.playMacroByID(macroID, triggeredBy: hk)
                }
            }) {
                perMacroHotkeyIDs[id] = macroID
            }
        }
    }

    private func refreshIgnoredHotkeyChords() {
        var ignored: Set<RecordingIgnoredKeyChord> = [
            state.recordHotkey.recordingIgnoredKeyChord,
            state.stopHotkey.recordingIgnoredKeyChord,
            state.playHotkey.recordingIgnoredKeyChord,
        ]
        for macro in library.macros {
            if let hotkey = macro.hotkey {
                ignored.insert(hotkey.recordingIgnoredKeyChord)
            }
        }
        recorder.ignoredKeyChords = ignored
    }

    func reapplyHotkeys() {
        registerGlobalHotkeys()
        refreshPerMacroHotkeys()
        refreshIgnoredHotkeyChords()
    }

    // MARK: - Library glue

    private func loadInitialMacroIntoRecorder() {
        if let m = library.currentMacro {
            loadMacroEventsIntoRecorder(m.id)
        }
    }

    func selectMacro(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        persistCurrentMacroIfNeeded()
        library.select(id: id)
        if let m = library.currentMacro {
            loadMacroEventsIntoRecorder(m.id, statusName: m.name)
        }
    }

    private func loadMacroEventsIntoRecorder(_ id: UUID, statusName: String? = nil) {
        guard !recorder.isRecording else { return }
        guard recorderLoadedMacroID != id, recorderLoadingMacroID != id else { return }

        recorderLoadingMacroID = id
        if let statusName {
            state.presentStatus(
                String(
                    format: String(localized: "Loading %@...", table: "Recording"),
                    statusName
                ),
                tone: .progress
            )
        }
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.recorderLoadingMacroID == id {
                    self.recorderLoadingMacroID = nil
                }
            }

            do {
                let events = try await self.library.loadEvents(for: id)
                guard !self.macroLibraryInteractionLocked,
                      self.library.currentMacroID == id else { return }
                self.recorder.loadEvents(events)
                self.recorderLoadedMacroID = id
                if let statusName {
                    self.state.presentStatus(
                        String(
                            format: String(localized: "Loaded %@.", table: "Recording"),
                            statusName
                        ),
                        tone: .success
                    )
                }
            } catch {
                if self.library.currentMacroID == id, !self.recorder.isRecording {
                    self.recorderLoadedMacroID = nil
                    self.recorder.clearAll()
                }
                if let statusName {
                    self.state.presentStatus(
                        String(
                            format: String(localized: "Failed to load %@.", table: "Recording"),
                            statusName
                        ),
                        tone: .error
                    )
                }
            }
        }
    }

    func renameMacro(_ id: UUID, to name: String) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard library.macros.contains(where: { $0.id == id }) else { return }
        library.rename(id: id, to: name)
        guard let updatedName = library.macros.first(where: { $0.id == id })?.name else { return }
        state.presentStatus(
            String(
                format: String(localized: "Renamed macro to %@.", table: "Common"),
                updatedName
            ),
            tone: .success
        )
    }

    func duplicateMacro(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let sourceName = library.macros.first(where: { $0.id == id })?.name else { return }
        state.presentStatus(
            String(
                format: String(localized: "Duplicating %@…", table: "Common"),
                sourceName
            ),
            tone: .progress
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let copy = try await self.library.duplicate(id: id) else {
                    self.state.presentStatus(
                        String(localized: "The macro is no longer available.", table: "Automation"),
                        tone: .error
                    )
                    return
                }
                self.state.presentStatus(
                    String(
                        format: String(localized: "Created %@.", table: "Common"),
                        copy.name
                    ),
                    tone: .success
                )
            } catch {
                self.state.presentStatus(
                    String(
                        format: String(localized: "Could not duplicate %@. The original was not changed.", table: "Common"),
                        sourceName
                    ),
                    tone: .error
                )
            }
        }
    }

    func deleteMacro(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let deletedName = library.macros.first(where: { $0.id == id })?.name else { return }
        // Only reload the recorder buffer when the CURRENT macro was deleted;
        // otherwise we'd wipe unsaved editor edits to an unrelated macro.
        let wasCurrent = (id == library.currentMacroID)
        library.delete(id: id)
        if wasCurrent {
            recorderLoadedMacroID = nil
            if let macro = library.currentMacro {
                loadMacroEventsIntoRecorder(macro.id)
            } else {
                recorder.clearAll()
            }
        }
        state.presentStatus(
            String(
                format: String(localized: "Deleted %@.", table: "Common"),
                deletedName
            ),
            tone: .success
        )
    }

    func deleteMacros(_ ids: Set<UUID>) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        let existingIDs = Set(library.macros.lazy.map(\.id)).intersection(ids)
        guard !existingIDs.isEmpty else { return }
        let wasCurrent = library.currentMacroID.map { existingIDs.contains($0) } ?? false
        library.deleteMany(ids: existingIDs)
        if wasCurrent {
            recorderLoadedMacroID = nil
            if let macro = library.currentMacro {
                loadMacroEventsIntoRecorder(macro.id)
            } else {
                recorder.clearAll()
            }
        }
        state.presentStatus(
            String(localized: "Selected macros deleted.", table: "Common"),
            tone: .success
        )
    }

    func setMacroLoops(_ id: UUID, to loops: Int) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setLoops(id: id, loops: loops)
        state.presentStatus(
            String(
                format: String(localized: "Repeat setting updated for %@.", table: "Common"),
                name
            ),
            tone: .success
        )
    }

    func setMacroSpeed(_ id: UUID, to speed: Double) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setSpeed(id: id, speed: speed)
        state.presentStatus(
            String(
                format: String(localized: "Playback speed updated for %@.", table: "Common"),
                name
            ),
            tone: .success
        )
    }

    func setMacroIcon(_ id: UUID, to icon: String?) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setIcon(id: id, icon: icon)
        state.presentStatus(
            String(
                format: String(localized: "Icon updated for %@.", table: "Common"),
                name
            ),
            tone: .success
        )
    }

    func setMacroAccent(_ id: UUID, to color: String?) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setAccent(id: id, accent: color)
        state.presentStatus(
            String(
                format: String(localized: "Color updated for %@.", table: "Common"),
                name
            ),
            tone: .success
        )
    }

    func setMacroHotkey(_ id: UUID, to hotkey: HotkeyBinding?) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setHotkey(id: id, hotkey: hotkey)
        refreshPerMacroHotkeys()
        refreshIgnoredHotkeyChords()
        state.presentStatus(
            hotkey == nil
                ? String(
                    format: String(localized: "Shortcut removed from %@.", table: "Common"),
                    name
                )
                : String(
                    format: String(localized: "Shortcut assigned to %@.", table: "Common"),
                    name
                ),
            tone: .success
        )
    }

    func toggleFavorite(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        library.toggleFavorite(id: id)
        state.presentStatus(
            macro.favorite
                ? String(
                    format: String(localized: "Removed %@ from Favorites.", table: "Common"),
                    macro.name
                )
                : String(
                    format: String(localized: "Added %@ to Favorites.", table: "Common"),
                    macro.name
                ),
            tone: .success
        )
    }

    func addTag(_ id: UUID, _ tag: String) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            state.presentStatus(
                String(localized: "Enter a tag before adding it.", table: "Common"),
                tone: .warning
            )
            return
        }
        let alreadyPresent = macro.tags.contains(normalized)
        library.addTag(id: id, normalized)
        state.presentStatus(
            alreadyPresent
                ? String(
                    format: String(localized: "%@ already has that tag.", table: "Common"),
                    macro.name
                )
                : String(
                    format: String(localized: "Tag added to %@.", table: "Common"),
                    macro.name
                ),
            tone: alreadyPresent ? .info : .success
        )
    }

    func removeTag(_ id: UUID, _ tag: String) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        library.removeTag(id: id, tag)
        state.presentStatus(
            String(
                format: String(localized: "Tag removed from %@.", table: "Common"),
                macro.name
            ),
            tone: .success
        )
    }

    func setMacroNotes(_ id: UUID, to notes: String) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let name = library.macros.first(where: { $0.id == id })?.name else { return }
        library.setNotes(id: id, notes: notes)
        state.presentStatus(
            String(
                format: String(localized: "Notes updated for %@.", table: "Common"),
                name
            ),
            tone: .success
        )
    }

    func setChain(_ id: UUID, to target: UUID?) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let sourceName = library.macros.first(where: { $0.id == id })?.name else { return }
        let targetName = target.flatMap { targetID in
            library.macros.first(where: { $0.id == targetID })?.name
        }

        switch library.setChainTo(id: id, target: target) {
        case .applied:
            if let targetName {
                state.presentStatus(
                    String(
                        format: String(localized: "%@ will continue with %@ after playback.", table: "Common"),
                        sourceName,
                        targetName
                    ),
                    tone: .success
                )
            } else {
                state.presentStatus(
                    String(
                        format: String(localized: "Playback chain removed from %@.", table: "Common"),
                        sourceName
                    ),
                    tone: .success
                )
            }
        case .selfReference, .cycle:
            state.presentStatus(
                String(localized: "That chain would create a playback loop. Choose a different macro.", table: "Common"),
                tone: .warning
            )
        case .targetMissing:
            state.presentStatus(
                String(localized: "The selected next macro is no longer available.", table: "Common"),
                tone: .warning
            )
        case .sourceMissing:
            state.presentStatus(
                String(localized: "The macro is no longer available.", table: "Automation"),
                tone: .error
            )
        }
    }

    func moveMacro(_ id: UUID, before targetID: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard id != targetID,
              library.macros.contains(where: { $0.id == id }),
              library.macros.contains(where: { $0.id == targetID }) else { return }
        library.move(id: id, before: targetID)
        state.presentStatus(
            String(localized: "Macro order updated.", table: "Common"),
            tone: .success
        )
    }

    func chooseTargetWindow(for id: UUID) {
        guard let macro = library.macros.first(where: { $0.id == id }) else {
            state.presentStatus(
                String(localized: "The macro is no longer available.", table: "Automation"),
                tone: .error
            )
            return
        }
        let existingID = MacroPlaybackSurfaceEditing.orderedSurfaceIDs(macro.surfaces).first
        chooseTargetWindow(for: id, surfaceID: existingID)
    }

    func chooseTargetWindow(for id: UUID, surfaceID: String?) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else {
            state.presentStatus(
                String(localized: "The macro is no longer available.", table: "Automation"),
                tone: .error
            )
            return
        }
        chooseTargetWindow(named: macro.name) { [weak self] surface in
            guard let self else { return false }
            if let surfaceID {
                return self.library.rebindSurface(id: id, surfaceID: surfaceID, surface: surface)
            }
            return self.library.addSurface(id: id, surface: surface) != nil
        }
    }

    func chooseTargetWindow(for session: MacroCandidateEditorSession) {
        let existingID = MacroPlaybackSurfaceEditing.orderedSurfaceIDs(session.draftMacro.surfaces).first
        chooseTargetWindow(for: session, surfaceID: existingID)
    }

    func chooseTargetWindow(for session: MacroCandidateEditorSession, surfaceID: String?) {
        guard requireScreenPickingAvailable() else { return }
        chooseTargetWindow(named: session.draftMacro.name) { [weak session] surface in
            guard let session else { return false }
            if let surfaceID {
                return session.rebindSurface(surfaceID, to: surface)
            }
            _ = session.addSurface(surface)
            return true
        }
    }

    private func chooseTargetWindow(
        named macroName: String,
        apply: @escaping @MainActor (PlaybackSurface) -> Bool
    ) {
        let visibility = ApplicationWindowVisibilitySnapshot.capture()
        windowTargetPicker.onPicked = { [weak self] point in
            guard let self else { return }
            defer { visibility.restore() }
            do {
                let surface = try WindowSurfaceCapture().captureWindow(at: point)
                guard apply(surface) else {
                    self.state.presentStatus(
                        String(localized: "The Playback Surface changed before it could be updated. Try again.", table: "EditorUX"),
                        tone: .warning
                    )
                    SoundController.shared.play(.error)
                    return
                }
                let appName = surface.appName ?? String(localized: "Target window", table: "Recording")
                let detail = surface.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                let target = detail.flatMap { $0.isEmpty ? nil : "\(appName) — \($0)" } ?? appName
                self.state.presentStatus(
                    String(
                        format: String(localized: "Target window set: %@.", table: "Recording"),
                        target
                    ),
                    tone: .success
                )
                SoundController.shared.play(.tick)
            } catch WindowCaptureError.noWindowAtPoint {
                self.state.presentStatus(
                    String(
                        localized: "No app window was found there. Try again and click inside the window this macro should control.",
                        table: "Recording"
                    ),
                    tone: .warning
                )
                SoundController.shared.play(.error)
            } catch WindowCaptureError.noAccessibilityPermission {
                self.state.presentStatus(
                    String(
                        localized: "Accessibility permission is required to choose a target window. Enable it in Settings, then try again.",
                        table: "Recording"
                    ),
                    tone: .error
                )
                SoundController.shared.play(.error)
                self.showSettingsWindow()
            } catch {
                self.state.presentStatus(
                    String(localized: "Could not set the target window. Try again.", table: "Recording"),
                    tone: .error
                )
                SoundController.shared.play(.error)
            }
        }
        windowTargetPicker.onCancelled = { [weak self] in
            guard let self else { return }
            visibility.restore()
            self.state.presentStatus(
                String(localized: "Window selection cancelled.", table: "Recording"),
                tone: .info
            )
        }
        let didStartPicker = windowTargetPicker.start(
            configuration: .init(
                title: String(
                    format: String(localized: "Choose a target window for %@", table: "Recording"),
                    macroName
                ),
                subtitle: String(
                    localized: "Click the window to bind it. SparkleRecorder will not run any actions. Press ESC to cancel.",
                    table: "Recording"
                ),
                systemImage: "window.badge.key",
                requiredClickCount: 1
            )
        )
        guard didStartPicker else {
            state.presentStatus(
                String(localized: "No display is available for window selection.", table: "Recording"),
                tone: .error
            )
            return
        }
        state.presentStatus(
            String(localized: "Choose the window this macro should control.", table: "Recording"),
            tone: .progress
        )
        visibility.concealCapturedWindows()
    }

    func removeTargetWindow(for id: UUID, surfaceID: String) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard library.removeSurface(id: id, surfaceID: surfaceID) else {
            state.presentStatus(
                String(localized: "Reassign every action that uses this Playback Surface before removing it.", table: "EditorUX"),
                tone: .warning
            )
            SoundController.shared.play(.error)
            return
        }
        state.presentStatus(
            String(localized: "Target window removed.", table: "Recording"),
            tone: .success
        )
        SoundController.shared.play(.tick)
    }

    func clearWindowBinding(for id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let ids = MacroPlaybackSurfaceEditing.orderedSurfaceIDs(macro.surfaces)
        guard ids.count == 1, let surfaceID = ids.first else {
            state.presentStatus(
                ids.isEmpty
                    ? String(localized: "No target window is set.", table: "Recording")
                    : String(localized: "This macro uses multiple Playback Surfaces. Open the editor to manage them individually.", table: "EditorUX"),
                tone: .info
            )
            return
        }
        removeTargetWindow(for: id, surfaceID: surfaceID)
    }

    private func persistCurrentMacroIfNeeded() {
        // Never persist while a recording is live: the buffer holds the partial
        // in-flight recording, and writing it over the selected macro destroys it.
        guard !recorder.isRecording else { return }
        guard let id = library.currentMacroID, recorderLoadedMacroID == id, recorderLoadingMacroID == nil else { return }
        library.updateEvents(id: id, events: recorder.events)
    }

    // MARK: - Actions

    func toggleRecording(triggeredBy hotkey: HotkeyBinding? = nil) {
        if auxiliaryCaptureActive {
            stopAll()
            return
        }
        guard !state.recordingFinalizationActive else {
            state.presentStatus(
                String(
                    localized: "Wait for the current recording to finish saving before starting another recording or playback.",
                    table: "Recording"
                ),
                tone: .warning
            )
            return
        }
        if state.playbackFlowActive || player.isPlaybackTargetReserved || player.isPlaying
            || manualPlaybackTask != nil || reconstructionTestActive {
            stopAll()
            state.presentStatus(
                String(
                    localized: "Playback stopped. Start recording again when you are ready.",
                    table: "Recording"
                ),
                tone: .info
            )
            return
        }
        // A second press during the countdown means "never mind".
        if let countdown, countdown.isActive {
            countdown.cancel()
            state.recordingFlowActive = false
            restoreVisibilityAfterAbortedRecordingPreparation()
            state.presentStatus(
                String(localized: "Recording cancelled.", table: "Recording"),
                tone: .info
            )
            return
        }
        if recorder.isRecording {
            _ = stopRecordingAndSave(triggeredBy: hotkey?.recordingIgnoredKeyChord)
        } else {
            beginRecordingFlow()
        }
    }

    @discardableResult
    private func stopRecordingAndSave(
        triggeredBy hotkeyChord: RecordingIgnoredKeyChord? = nil,
        context: RecordingStopContext = .normal
    ) -> UUID? {
        guard recorder.isRecording else { return nil }

        recorder.stopRecording(
            ignoringTrailingHotkeyArtifactsFor: hotkeyChord
        )
        state.isRecording = false
        let count = recorder.eventCount
        let savedMacroID: UUID?
        if count > 0 {
            let newMacro = library.add(events: recorder.events, loops: state.loops)
            savedMacroID = newMacro.id
            recorderLoadedMacroID = newMacro.id
            if !recorder.activeSurfaces.isEmpty {
                library.setSurfaces(id: newMacro.id, surfaces: recorder.activeSurfaces)
            } else if let surface = recordedSurface {
                library.setSingleRecordedSurface(id: newMacro.id, surface: surface)
            }
            pendingSemanticRecordingMacroID = newMacro.id
            attachSemanticRecordingIfFinished(recorder.semanticRecordingStatus)
            SoundController.shared.play(.recordStop)
        } else {
            savedMacroID = nil
        }
        state.recordingFlowActive = false
        hud?.hide()

        let completionMessage: String
        switch (context, savedMacroID.flatMap { id in library.macros.first(where: { $0.id == id }) }) {
        case (.inputMonitoringRevoked, .some(let macro)):
            completionMessage = String(
                format: String(
                    localized: "Input Monitoring was revoked. Saved the partial recording as %@.",
                    table: "Recording"
                ),
                macro.name
            )
        case (.inputMonitoringRevoked, .none):
            completionMessage = String(
                localized: "Input Monitoring was revoked before any events were captured.",
                table: "Recording"
            )
        case (.appBecameActive, .some(let macro)):
            completionMessage = String(
                format: String(
                    localized: "SparkleRecorder became active. Saved the interrupted recording as %@.",
                    table: "Recording"
                ),
                macro.name
            )
        case (.appBecameActive, .none):
            completionMessage = String(
                localized: "SparkleRecorder became active before any events were captured.",
                table: "Recording"
            )
        case (.normal, .some(let macro)):
            completionMessage = String(
                format: String(localized: "Saved %@ · %d events.", table: "Recording"),
                macro.name,
                count
            )
        case (.normal, .none):
            completionMessage = String(localized: "No events captured.", table: "Recording")
        }

        let completionTone: AppStatusFeedback.Tone = switch context {
        case .normal:
            savedMacroID == nil ? .info : .success
        case .inputMonitoringRevoked, .appBecameActive:
            .warning
        }
        beginRecordingFinalization(
            savedMacroID: savedMacroID,
            eventCount: count,
            completionMessage: completionMessage,
            completionTone: completionTone,
            restoreSelectedMacroAfterward: savedMacroID == nil
        )
        return savedMacroID
    }

    private func beginRecordingFinalization(
        savedMacroID: UUID?,
        eventCount: Int,
        completionMessage: String,
        completionTone: AppStatusFeedback.Tone,
        restoreSelectedMacroAfterward: Bool
    ) {
        guard recordingFinalizationTask == nil else {
            assertionFailure("Recording finalization must be serialized")
            return
        }
        let finalizingMessage = String(localized: "Finishing recording…", table: "Recording")
        state.recordingFinalizationActive = true
        state.presentStatus(finalizingMessage, tone: .progress)
        let finalizingFeedbackID = state.statusFeedback?.id
        refreshIcon()
        updateDockBadge()

        recordingFinalizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.recorder.waitForSemanticRecordingCompletion()
            self.attachSemanticRecordingIfFinished(status)
            if case .finished = status {
                // attachSemanticRecordingIfFinished owns the pending reference.
            } else {
                self.pendingSemanticRecordingMacroID = nil
            }
            let sanitizationTask = self.semanticSanitizationTask
            await sanitizationTask?.value

            if let savedMacroID {
                // library.add() already queued the event payload and ordered
                // metadata for this Macro. Normal stop only needs a scoped
                // durability barrier; termination performs the stronger full
                // repository flush separately.
                await self.library.flushPendingPersistence(for: savedMacroID)
            }

            if restoreSelectedMacroAfterward {
                if let macro = self.library.currentMacro {
                    self.recorderLoadedMacroID = nil
                    do {
                        let events = try await self.library.loadEvents(for: macro.id)
                        if self.library.currentMacroID == macro.id {
                            self.recorder.loadEvents(events)
                            self.recorderLoadedMacroID = macro.id
                        }
                    } catch {
                        self.recorder.clearAll()
                        self.state.presentStatus(
                            String(
                                format: String(localized: "Could not read the macro data: %@", table: "Common"),
                                error.localizedDescription
                            ),
                            tone: .error
                        )
                    }
                } else {
                    self.recorder.clearAll()
                }
            }

            // Persistence or sanitization may have published a more actionable
            // failure while Finalizing. Only replace the neutral saving message;
            // never hide a later repository/privacy diagnostic behind "Saved".
            if self.state.statusFeedback?.id == finalizingFeedbackID {
                let feedback = self.recordingFinalizationFeedback(
                    semanticStatus: status,
                    fallback: completionMessage,
                    fallbackTone: completionTone,
                    savedMacroID: savedMacroID,
                    eventCount: eventCount
                )
                self.state.presentStatus(feedback.message, tone: feedback.tone)
            }
            self.state.recordingFinalizationActive = false
            self.recordingFinalizationTask = nil
            self.refreshIcon()
            self.updateDockBadge()
        }
    }

    private func recordingFinalizationFeedback(
        semanticStatus: SemanticRecorderBridgeStatus,
        fallback: String,
        fallbackTone: AppStatusFeedback.Tone,
        savedMacroID: UUID?,
        eventCount: Int
    ) -> (message: String, tone: AppStatusFeedback.Tone) {
        switch semanticStatus {
        case .failed(let message):
            guard let savedMacroID,
                  let macro = library.macros.first(where: { $0.id == savedMacroID }) else {
                return (
                    String(
                        format: String(localized: "Visual recording failed: %@", table: "Recording"),
                        message
                    ),
                    .error
                )
            }
            return (
                String(
                    format: String(
                        localized: "Saved %@ · %d events. Visual recording failed: %@",
                        table: "Recording"
                    ),
                    macro.name,
                    eventCount,
                    message
                ),
                .warning
            )
        case .suppressed:
            guard savedMacroID != nil else { return (fallback, fallbackTone) }
            return (
                String(
                    localized: "Saved the action recording. Visual evidence was stopped to protect sensitive content.",
                    table: "Recording"
                ),
                .warning
            )
        case .blocked(let preflight):
            let issue = visualRecordingBlockedStatus(preflight.blockingIssues)
            guard savedMacroID != nil else { return (issue, .error) }
            return (
                String(
                    format: String(
                        localized: "Saved the action recording. Visual evidence was unavailable: %@",
                        table: "Recording"
                    ),
                    issue
                ),
                .warning
            )
        case .idle, .starting, .active, .finishing, .finished, .cancelled:
            return (fallback, fallbackTone)
        }
    }

    private func waitForRecordingFinalization() async {
        let task = recordingFinalizationTask
        await task?.value
    }

    /// Wraps the actual recording start with an optional countdown.
    private func beginRecordingFlow() {
        guard !reconstructionTestActive,
              !recordingPreparationActive,
              !state.recordingFinalizationActive else { return }
        recordingPreparationActive = true
        state.recordingFlowActive = true
        if player.isPlaying { player.stop() }
        persistCurrentMacroIfNeeded()

        recordingPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.recordingPreparationActive = false
                self.recordingPreparationTask = nil
            }
            await self.prepareSemanticRecordingAndContinue()
        }
    }

    private func prepareSemanticRecordingAndContinue() async {
        pendingRecordingStartMessage = nil
        state.semanticRecordingPreflightPresentation = nil

        await finishPreviousRecordingPostprocessingBeforeNewRecording()
        guard !Task.isCancelled else {
            state.recordingFlowActive = false
            return
        }

        guard await chooseRecordingEvidenceModeIfNeeded() else {
            state.recordingFlowActive = false
            return
        }
        guard !Task.isCancelled else {
            state.recordingFlowActive = false
            return
        }
        guard state.semanticRecordingEnabled else {
            closePopoverForRecording()
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                state.recordingFlowActive = false
                restoreVisibilityAfterAbortedRecordingPreparation()
                return
            }
            startRecordingAfterPreflight()
            return
        }

        state.presentStatus(
            String(localized: "Checking visual recording permissions…", table: "Recording"),
            tone: .progress
        )
        let result = await SemanticRecordingPreflightClient.live.evaluate(
            policy: SemanticRecordingPreflightPolicy(
                capturePolicy: state.semanticRecordingCapturePolicy
            )
        )
        let presentation = SemanticRecordingPreflightPresenter.presentation(for: result)
        state.semanticRecordingPreflightPresentation = presentation

        guard presentation.canStart else {
            state.recordingFlowActive = false
            state.presentStatus(
                visualRecordingBlockedStatus(result.blockingIssues),
                tone: .error
            )
            SoundController.shared.play(.error)
            showSettingsWindow()
            return
        }

        if presentation.status == .degraded {
            pendingRecordingStartMessage = String(localized: "Recording with limited visual context.", table: "Recording")
        }
        closePopoverForRecording()
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else {
            state.recordingFlowActive = false
            restoreVisibilityAfterAbortedRecordingPreparation()
            return
        }
        startRecordingAfterPreflight()
    }

    private func finishPreviousRecordingPostprocessingBeforeNewRecording() async {
        let status = await recorder.waitForSemanticRecordingCompletion()
        handleSemanticRecordingStatus(status)
        let sanitizationTask = semanticSanitizationTask
        await sanitizationTask?.value

        // Starting a new recording only depends on the Macro whose editor buffer
        // is about to be cleared. Unrelated Library writes remain background work.
        if let currentMacroID = library.currentMacroID {
            await library.flushPendingPersistence(for: currentMacroID)
        }
    }

    /// Ask once before the first action-only recording, so missing visual
    /// evidence is a deliberate choice rather than an invisible default.
    private func chooseRecordingEvidenceModeIfNeeded() async -> Bool {
        let defaults = UserDefaults.standard
        guard !state.semanticRecordingEnabled,
              !defaults.bool(forKey: "recordingEvidenceModeChosen") else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save visual evidence with this recording?", table: "Recording")
        alert.informativeText = String(localized: "Video and keyframes are saved locally with your actions. AI can use these images to locate anchors when you explicitly include them in an export. Action-only recordings cannot recover missing images later. You can change this in Settings.", table: "Recording")
        alert.addButton(withTitle: String(localized: "Record with video and keyframes", table: "Recording"))
        alert.addButton(withTitle: String(localized: "Record actions only", table: "Recording"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Common"))
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        guard response != .alertThirdButtonReturn else { return false }
        state.semanticRecordingEnabled = response == .alertFirstButtonReturn
        if state.semanticRecordingEnabled {
            state.semanticRecordingCaptureMode = .videoAndKeyframes
        }
        defaults.set(true, forKey: "recordingEvidenceModeChosen")
        return true
    }

    private func closePopoverForRecording() {
        recordingPreparationVisibility = RecordingPreparationVisibility(
            appWasHidden: NSApp.isHidden,
            appWasActive: NSApp.isActive,
            popoverWasShown: popover.isShown
        )
        if popover.isShown { popover.performClose(nil) }
        // The standalone library must also relinquish focus before capturing
        // the recording surface, including when countdown is disabled.
        NSApp.hide(nil)
    }

    private func restoreVisibilityAfterAbortedRecordingPreparation() {
        guard let visibility = recordingPreparationVisibility else { return }
        recordingPreparationVisibility = nil
        guard !visibility.appWasHidden else { return }

        NSApp.unhide(nil)
        if visibility.appWasActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if visibility.popoverWasShown {
            showPopoverProgrammatically()
        }
    }

    private func startRecordingAfterPreflight() {
        let secs = state.countdownSeconds
        if secs > 0 {
            countdown?.start(seconds: secs) { [weak self] in
                self?.actuallyStartRecording()
            }
        } else {
            actuallyStartRecording()
        }
    }

    private func actuallyStartRecording() {
        let capture = WindowSurfaceCapture()
        self.recordedSurface = try? capture.captureFrontmostWindow()
        let semanticCaptureTarget: RecordingCaptureTarget
        switch state.semanticRecordingCaptureScope {
        case .frontmostWindow:
            semanticCaptureTarget = SemanticRecordingCaptureTargetMapper.target(
                surface: recordedSurface
            )
        case .display:
            semanticCaptureTarget = SemanticRecordingCaptureTargetMapper.target(
                surface: nil,
                fallbackDisplayID: recordedSurface?.recordedDisplayId
            )
        }
        
        // A new recording owns a fresh buffer. Detach it from the previously
        // selected macro before Recorder clears events so startup failure or an
        // interrupted recording can never be persisted over that macro.
        recorderLoadedMacroID = nil
        let ok = recorder.startRecording(
            semanticRecordingEnabled: state.semanticRecordingEnabled,
            semanticCaptureTarget: semanticCaptureTarget,
            semanticCapturePolicy: state.semanticRecordingCapturePolicy
        )
        if ok {
            recordingPreparationVisibility = nil
            state.isRecording = true
            editorWC?.window?.orderOut(nil)
            showRecordingHUDIfNeeded()
            state.presentStatus(
                pendingRecordingStartMessage ?? String(localized: "Recording…", table: "Recording"),
                tone: .progress
            )
            pendingRecordingStartMessage = nil
            SoundController.shared.play(.recordStart)
        } else {
            state.recordingFlowActive = false
            pendingRecordingStartMessage = nil
            restoreVisibilityAfterAbortedRecordingPreparation()
            if let macro = library.currentMacro {
                loadMacroEventsIntoRecorder(macro.id)
            } else {
                recorder.clearAll()
            }
            state.refreshPermissions()
            state.presentStatus(recordingStartFailureStatus(), tone: .error)
            SoundController.shared.play(.error)
        }
    }

    func stopAll() {
        if state.recordingFinalizationActive {
            state.presentStatus(
                String(localized: "Finishing recording…", table: "Recording"),
                tone: .progress
            )
            return
        }

        let wasPlaybackActive = state.playbackFlowActive
            || manualPlaybackTask != nil
            || player.isPlaybackTargetReserved
            || player.isPlaying
        let wasRecordingPreparationActive = state.recordingFlowActive && !recorder.isRecording
        let wasAuxiliaryCaptureActive = auxiliaryCaptureActive

        playbackRequestGeneration &+= 1
        manualPlaybackTask?.cancel()
        manualPlaybackTask = nil
        playingMacroID = nil
        recorderLoadingMacroID = nil
        manualPlaybackVisibilitySession.restore()
        cancelAuxiliaryCaptures()
        recordingPreparationTask?.cancel()
        recordingPreparationTask = nil
        recordingPreparationActive = false
        state.playbackFlowActive = false
        player.stop()
        countdown?.cancel()
        if !recorder.isRecording {
            state.recordingFlowActive = false
            restoreVisibilityAfterAbortedRecordingPreparation()
        }
        if recorder.isRecording {
            // Global Stop during a live recording is destructive by design: discard
            // the in-flight recording instead of routing through the Save flow.
            cancelRecording()
            return
        }
        if wasPlaybackActive {
            state.presentStatus(
                String(localized: "Playback stopped.", table: "Recording"),
                tone: .info
            )
        } else if wasRecordingPreparationActive {
            state.presentStatus(
                String(localized: "Recording setup cancelled.", table: "Recording"),
                tone: .info
            )
        } else if wasAuxiliaryCaptureActive {
            state.presentStatus(
                String(localized: "Picking cancelled.", table: "EditorUX"),
                tone: .info
            )
        } else {
            state.presentStatus(
                String(localized: "Nothing is running.", table: "Recording"),
                tone: .info
            )
        }
    }

    private func observeSemanticRecordingStatus() {
        recorder.$semanticRecordingStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleSemanticRecordingStatus(status)
            }
            .store(in: &cancellables)
    }

    private func handleSemanticRecordingStatus(
        _ status: SemanticRecorderBridgeStatus
    ) {
        switch status {
        case .finished:
            attachSemanticRecordingIfFinished(status)

        case .blocked(let preflight):
            pendingSemanticRecordingMacroID = nil
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled"),
                  !state.recordingFinalizationActive else {
                return
            }
            state.presentStatus(
                visualRecordingBlockedStatus(preflight.blockingIssues),
                tone: .error
            )

        case .failed(let message):
            pendingSemanticRecordingMacroID = nil
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled"),
                  !state.recordingFinalizationActive else {
                return
            }
            state.presentStatus(
                String(
                    format: String(localized: "Visual recording failed: %@", table: "Recording"),
                    message
                ),
                tone: .error
            )

        case .cancelled:
            pendingSemanticRecordingMacroID = nil

        case .suppressed:
            pendingSemanticRecordingMacroID = nil
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled"),
                  !state.recordingFinalizationActive else {
                return
            }
            state.presentStatus(
                String(
                    localized: "Visual evidence stopped to protect sensitive content. Action recording continues.",
                    table: "Recording"
                ),
                tone: .warning
            )

        default:
            break
        }
    }

    private func attachSemanticRecordingIfFinished(
        _ status: SemanticRecorderBridgeStatus
    ) {
        guard case .finished(let bundleID, let bundleDirectory, let eventCount) = status,
              let macroID = pendingSemanticRecordingMacroID else {
            return
        }

        let reference = MacroSemanticRecordingReference(
            recordingID: bundleID,
            bundleRelativePath: MacroSemanticRecordingReference.defaultBundleRelativePath(
                recordingID: bundleID
            ),
            manifestRelativePath: MacroSemanticRecordingReference.defaultManifestRelativePath(
                recordingID: bundleID
            ),
            capturedAt: Date(),
            eventCount: eventCount
        )
        library.attachSemanticRecording(id: macroID, reference: reference)
        applyPlayableSanitizationIfNeeded(
            macroID: macroID,
            bundleID: bundleID,
            bundleDirectory: bundleDirectory
        )
        pendingSemanticRecordingMacroID = nil
    }

    private func applyPlayableSanitizationIfNeeded(
        macroID: UUID,
        bundleID: UUID,
        bundleDirectory: URL
    ) {
        semanticSanitizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.semanticSanitizationTask = nil }
            do {
                let store = RecordingBundleStore(
                    rootDirectory: bundleDirectory.deletingLastPathComponent()
                )
                let bundle = try await store.loadBundle(from: bundleDirectory)
                guard bundle.id == bundleID else {
                    return
                }
                let inMemoryEvents = library.macros.first(where: { $0.id == macroID })?.events ?? []
                let events = inMemoryEvents.isEmpty
                    ? try await library.loadEvents(for: macroID)
                    : inMemoryEvents
                let plan = await Task.detached(priority: .utility) {
                    SemanticRecordingPlayableSanitizationPlanner.plan(
                        for: events,
                        bundle: bundle
                    )
                }.value
                guard !plan.isEmpty else {
                    return
                }

                guard let summary = await library.applyPlayableSanitization(
                    id: macroID,
                    plan: plan
                ) else {
                    return
                }
                if library.currentMacroID == macroID,
                   let macro = library.macros.first(where: { $0.id == macroID }),
                   !macro.events.isEmpty {
                    recorder.loadEvents(macro.events)
                }
                if summary.sanitizedEventCount > 0,
                   summary.reviewRequiredEventCount > 0 {
                    state.presentStatus(
                        String(
                            format: String(localized: "Saved visual evidence, hid readable text from %d action(s), and left %d action(s) for review.", table: "Recording"),
                            summary.sanitizedEventCount,
                            summary.reviewRequiredEventCount
                        ),
                        tone: .warning
                    )
                } else if summary.sanitizedEventCount > 0 {
                    state.presentStatus(
                        String(
                            format: String(localized: "Saved visual evidence and hid readable text from %d action(s).", table: "Recording"),
                            summary.sanitizedEventCount
                        ),
                        tone: .success
                    )
                } else if summary.reviewRequiredEventCount > 0 {
                    state.presentStatus(
                        String(
                            format: String(localized: "Saved visual evidence. Review %d sensitive action(s) before changing the text used during playback.", table: "Recording"),
                            summary.reviewRequiredEventCount
                        ),
                        tone: .warning
                    )
                }
            } catch {
                state.presentStatus(
                    String(
                        format: String(localized: "Recording text protection could not finish: %@", table: "Recording"),
                        error.localizedDescription
                    ),
                    tone: .warning
                )
            }
        }
    }

    private func loadedEventsForExport(
        macro: SavedMacro
    ) async throws -> [RecordedEvent] {
        if macro.events.isEmpty {
            return try await library.loadEvents(for: macro.id)
        }
        return macro.events
    }

    private func recordingStartFailureStatus() -> String {
        switch (state.accessibilityGranted, state.inputMonitoringGranted) {
        case (false, false):
            return String(
                localized: "Could not start. Grant Accessibility and Input Monitoring permissions.",
                table: "Recording"
            )
        case (false, true):
            return String(localized: "Could not start. Grant Accessibility permission.", table: "Recording")
        case (true, false):
            return String(localized: "Could not start. Grant Input Monitoring permission.", table: "Recording")
        case (true, true):
            return String(localized: "Could not start recording. Check permissions in Settings.", table: "Recording")
        }
    }

    private func visualRecordingBlockedStatus(
        _ issues: [SemanticRecordingPreflightIssue]
    ) -> String {
        String(
            format: String(localized: "Visual recording blocked: %@", table: "Recording"),
            semanticRecordingIssueSummary(issues)
        )
    }

    private func semanticRecordingIssueSummary(
        _ issues: [SemanticRecordingPreflightIssue]
    ) -> String {
        let labels = issues.prefix(2).map { issue in
            semanticRecordingPermissionLabel(issue.permission)
        }
        guard !labels.isEmpty else {
            return String(localized: "Unavailable", table: "Common")
        }
        return labels.joined(separator: ", ")
    }

    private func semanticRecordingPermissionLabel(
        _ permission: SemanticRecordingPermissionKind
    ) -> String {
        switch permission {
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .inputMonitoring:
            return String(localized: "Input Monitoring", table: "Common")
        case .screenRecording:
            return String(localized: "Screen Recording", table: "Recording")
        }
    }

    func refreshSemanticRecordingPreflightPresentation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            state.presentStatus(
                String(localized: "Checking visual recording permissions…", table: "Recording"),
                tone: .progress
            )
            let result = await SemanticRecordingPreflightClient.live.evaluate(
                policy: SemanticRecordingPreflightPolicy(
                    capturePolicy: state.semanticRecordingCapturePolicy
                )
            )
            state.semanticRecordingPreflightPresentation = SemanticRecordingPreflightPresenter.presentation(
                for: result
            )
            if result.isReadyToStart {
                state.presentStatus(
                    result.isDegraded
                        ? String(localized: "Visual recording can continue with limited context.", table: "Recording")
                        : String(localized: "Visual recording is ready.", table: "Recording"),
                    tone: result.isDegraded ? .warning : .success
                )
            } else {
                state.presentStatus(
                    visualRecordingBlockedStatus(result.blockingIssues),
                    tone: .error
                )
            }
        }
    }

    func openSemanticRecordingPermissionSettings(
        _ permission: SemanticRecordingPermissionKind
    ) {
        switch permission {
        case .accessibility:
            openAccessibilityPrefs()
        case .inputMonitoring:
            openInputMonitoringPrefs()
        case .screenRecording:
            openScreenCapturePrefs()
        }
    }

    func semanticRecordingRetentionCleanupPreview() async throws -> SemanticRecordingRetentionCleanupPreview {
        let store = RecordingBundleStore()
        return try await store.retentionCleanupPreview(
            settings: state.semanticRecordingRetentionSettings
        )
    }

    func applySemanticRecordingRetentionCleanup(
        _ preview: SemanticRecordingRetentionCleanupPreview
    ) async throws -> [RecordingBundleRetentionApplicationResult] {
        let store = RecordingBundleStore()
        return try await store.applyRetentionCleanup(
            preview,
            dryRun: false
        )
    }

    func automationRunRetentionCleanupPreview() async throws -> AutomationRunRetentionCleanupPreview {
        try await AutomationRunRetentionStore(repository: automationRepository).preview(
            settings: state.automationRunRetentionSettings
        )
    }

    func applyAutomationRunRetentionCleanup(
        _ preview: AutomationRunRetentionCleanupPreview
    ) async throws -> AutomationRunRetentionCleanupResult {
        try await AutomationRunRetentionStore(repository: automationRepository).apply(preview)
    }

    func automationRunStorageUsage() async throws -> AutomationRunStorageUsage {
        try await AutomationRunRetentionStore(repository: automationRepository).storageUsage()
    }

    func automationRunManualDeletionPreview(
        runIDs: Set<UUID>,
        scope: AutomationRunManualDeletionScope
    ) async throws -> AutomationRunManualDeletionPreview {
        try await AutomationRunRetentionStore(repository: automationRepository).manualDeletionPreview(
            runIDs: runIDs,
            scope: scope
        )
    }

    func applyAutomationRunManualDeletion(
        _ preview: AutomationRunManualDeletionPreview
    ) async throws -> AutomationRunManualDeletionResult {
        try await AutomationRunRetentionStore(repository: automationRepository).applyManualDeletion(preview)
    }

    func automationRunCleanupPreferenceDidChange() {
        scheduleAutomationRunRetentionCleanupIfNeeded()
    }

    private func scheduleSemanticRecordingRetentionCleanupIfNeeded(
        evaluatedAt: Date = Date()
    ) {
        let decision = SemanticRecordingScheduledRetentionCleanupPlanner.decision(
            settings: state.semanticRecordingRetentionSettings,
            lastRunAt: state.semanticRecordingLastScheduledRetentionCleanupAt,
            evaluatedAt: evaluatedAt
        )
        guard decision.shouldRun else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.runScheduledSemanticRecordingRetentionCleanup(decision: decision)
        }
    }

    private func runScheduledSemanticRecordingRetentionCleanup(
        decision: SemanticRecordingScheduledRetentionCleanupDecision
    ) async {
        let store = RecordingBundleStore()
        do {
            let preview = try await store.retentionCleanupPreview(
                settings: state.semanticRecordingRetentionSettings,
                evaluatedAt: decision.evaluatedAt
            )
            let results = try await store.applyRetentionCleanup(
                preview,
                dryRun: false
            )
            state.semanticRecordingLastScheduledRetentionCleanupAt = decision.evaluatedAt

            guard !preview.isEmpty else {
                return
            }
            let deletedArtifacts = results.reduce(0) { total, result in
                total + result.deletedRelativePaths.count
            }
            let deletedBundles = results.filter(\.deletedBundleDirectory).count
            state.presentStatus(
                String(
                    format: String(localized: "Cleaned up %d expired visual evidence artifact(s) and %d bundle(s).", table: "Automation"),
                    deletedArtifacts,
                    deletedBundles
                ),
                tone: .success
            )
        } catch {
            state.presentStatus(
                String(
                    format: String(localized: "Scheduled visual evidence cleanup failed: %@", table: "Automation"),
                    error.localizedDescription
                ),
                tone: .error
            )
        }
    }

    private func startAutomationRunRetentionMonitoring() {
        scheduleAutomationRunRetentionCleanupIfNeeded()
        automationRunRetentionTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleAutomationRunRetentionCleanupIfNeeded()
            }
        }
    }

    private func scheduleAutomationRunRetentionCleanupIfNeeded(evaluatedAt: Date = Date()) {
        guard state.automationRunAutomaticCleanupEnabled else { return }
        let decision = AutomationRunScheduledRetentionCleanupPlanner.decision(
            lastRunAt: state.automationRunLastScheduledRetentionCleanupAt,
            evaluatedAt: evaluatedAt
        )
        guard decision.shouldRun else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let store = AutomationRunRetentionStore(repository: automationRepository)
                let preview = try await store.preview(
                    settings: state.automationRunRetentionSettings,
                    evaluatedAt: evaluatedAt
                )
                if !preview.isEmpty {
                    let result = try await store.apply(preview)
                    state.automationRunLastCleanupEvidenceCount = result.prunedArtifactRunCount
                    state.automationRunLastCleanupHistoryCount = result.deletedMetadataRunCount
                    state.automationRunLastCleanupFreedByteCount = preview.estimatedByteCount
                    let cleanupMessage: String
                    if preview.estimatedByteCount == 0 {
                        cleanupMessage = String(
                            format: String(localized: "Updated %d expired evidence record(s) and removed %d old history record(s). No local evidence files needed deletion.", table: "Automation"),
                            result.prunedArtifactRunCount,
                            result.deletedMetadataRunCount
                        )
                    } else {
                        cleanupMessage = String(
                            format: String(localized: "Cleaned up evidence from %d run(s) and removed %d old history record(s).", table: "Automation"),
                            result.prunedArtifactRunCount,
                            result.deletedMetadataRunCount
                        )
                    }
                    state.presentStatus(cleanupMessage, tone: .success)
                } else {
                    state.automationRunLastCleanupEvidenceCount = 0
                    state.automationRunLastCleanupHistoryCount = 0
                    state.automationRunLastCleanupFreedByteCount = 0
                }
                state.automationRunLastScheduledRetentionCleanupAt = decision.evaluatedAt
            } catch {
                state.presentStatus(
                    String(
                        format: String(localized: "Run history cleanup failed: %@", table: "Automation"),
                        error.localizedDescription
                    ),
                    tone: .error
                )
                NSLog("SparkleRecorder: Run history cleanup failed: \(error)")
            }
        }
    }

    func play(triggeredBy hotkey: HotkeyBinding? = nil) {
        guard !reconstructionTestActive else { return }
        if auxiliaryCaptureActive {
            stopAll()
            return
        }
        play(isChained: false, triggeredBy: hotkey)
    }

    private func play(isChained: Bool, triggeredBy hotkey: HotkeyBinding? = nil) {
        if recorder.isRecording {
            _ = stopRecordingAndSave(triggeredBy: hotkey?.recordingIgnoredKeyChord)
            state.presentStatus(
                String(
                    localized: "Recording stopped. Play again after saving finishes.",
                    table: "Recording"
                ),
                tone: .info
            )
            return
        }
        guard !state.recordingFinalizationActive else {
            state.presentStatus(
                String(
                    localized: "Wait for the current recording to finish saving before starting another recording or playback.",
                    table: "Recording"
                ),
                tone: .warning
            )
            return
        }
        guard !recorder.events.isEmpty, recorderLoadingMacroID == nil else {
            if isChained { state.playbackFlowActive = false }
            state.presentStatus(
                String(localized: "No macro is ready to play. Select a macro and wait for its actions to load.", table: "Recording"),
                tone: .warning
            )
            return
        }
        guard !player.isPlaying,
              manualPlaybackTask == nil,
              !recordingPreparationActive,
              (!state.playbackFlowActive || isChained) else {
            if isChained { state.playbackFlowActive = false }
            return
        }
        if let failure = player.playbackPermissionFailure {
            state.playbackFlowActive = false
            state.presentStatus(failure, tone: .error)
            SoundController.shared.play(.error)
            showSettingsWindow()
            return
        }
        countdown?.cancel()
        if let currentMacroID = library.currentMacroID,
           recorderLoadedMacroID != currentMacroID {
            if isChained { state.playbackFlowActive = false }
            state.presentStatus(
                String(localized: "No macro is ready to play. Select a macro and wait for its actions to load.", table: "Recording"),
                tone: .warning
            )
            return
        }
        if !isChained { chainVisited.removeAll() }
        var macro = library.currentMacro ?? SavedMacro(name: "macro", events: recorder.events, loops: state.loops)
        macro.events = recorder.events
        if library.currentMacro == nil { macro.speed = state.speed }
        let snapshot = macro
        let generation = playbackRequestGeneration
        let client = AutomationPlayerClient.live(player: player, windowTracker: WindowTracker())
        let request = AutomationPlayerStartRequest(runID: UUID(), macro: snapshot,
            targetApplicationPolicy: snapshot.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded,
            targetApplicationReadyDelay: 0, targetApplicationCleanupPolicy: .keepOpen,
            targetApplicationQuitTimeout: 5, targetApplicationForceQuitOnTimeout: false)
        manualPlaybackVisibilitySession.beginIfNeeded()
        state.playbackFlowActive = true
        state.presentStatus(
            String(localized: "Preparing playback…", table: "Recording"),
            tone: .progress
        )
        if popover.isShown { popover.performClose(nil) }
        if snapshot.surfaces.isEmpty { NSApp.hide(nil) }
        manualPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playbackRequestGeneration == generation {
                    self.manualPlaybackTask = nil
                    self.playingMacroID = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await AutomationScheduledMacroPreviewClient(player: client).run(request, onStarted: { [weak self] in
                    await MainActor.run {
                        guard let self, self.playbackRequestGeneration == generation else { return }
                        self.playStartTime = CFAbsoluteTimeGetCurrent()
                        self.playingMacroID = snapshot.id
                        self.chainVisited.insert(snapshot.id)
                        self.state.presentStatus(
                            String(
                                format: String(localized: "Playing %@ · ×%d…", table: "Recording"),
                                snapshot.name,
                                snapshot.loops
                            ),
                            tone: .progress
                        )
                        SoundController.shared.play(.playStart)
                    }
                })
                try Task.checkCancellation()
                guard self.playbackRequestGeneration == generation else {
                    self.manualPlaybackVisibilitySession.restore()
                    return
                }
                let elapsed = CFAbsoluteTimeGetCurrent() - self.playStartTime
                self.library.recordPlay(id: snapshot.id, runTime: elapsed)
                let chainID = self.library.macros.first(where: { $0.id == snapshot.id })?.chainTo
                if let id = chainID, let next = self.library.macros.first(where: { $0.id == id }) {
                    guard !self.chainVisited.contains(id) else {
                        self.state.playbackFlowActive = false
                        self.manualPlaybackVisibilitySession.restore()
                        self.state.presentStatus(
                            String(localized: "Playback chain stopped because it would repeat a macro already played in this run.", table: "Recording"),
                            tone: .warning
                        )
                        return
                    }
                    self.library.select(id: id)
                    // The current playback has completed. Release this Task slot before
                    // loading the next chained macro, while playbackFlowActive keeps
                    // user-facing App windows locked until the whole chain ends.
                    self.manualPlaybackTask = nil
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let events = try await self.library.loadEvents(for: id)
                            guard self.playbackRequestGeneration == generation, self.library.currentMacroID == id else {
                                self.state.playbackFlowActive = false
                                self.manualPlaybackVisibilitySession.restore()
                                return
                            }
                            self.recorder.loadEvents(events)
                            self.recorderLoadedMacroID = id
                            self.state.presentStatus(
                                String(
                                    format: String(localized: "Chaining to %@…", table: "Recording"),
                                    next.name
                                ),
                                tone: .progress
                            )
                            self.play(isChained: true)
                        } catch {
                            self.state.playbackFlowActive = false
                            self.manualPlaybackVisibilitySession.restore()
                            self.state.presentStatus(
                                String(
                                    format: String(localized: "Failed to load %@.", table: "Recording"),
                                    next.name
                                ),
                                tone: .error
                            )
                        }
                    }
                } else {
                    self.state.playbackFlowActive = false
                    self.manualPlaybackVisibilitySession.restore()
                    self.state.presentStatus(
                        String(localized: "Playback finished.", table: "Recording"),
                        tone: .success
                    )
                    SoundController.shared.play(.playEnd)
                }
            } catch {
                self.manualPlaybackVisibilitySession.restore()
                guard self.playbackRequestGeneration == generation else { return }
                self.state.playbackFlowActive = false
                self.state.presentStatus(
                    Task.isCancelled
                        ? String(localized: "Playback stopped.", table: "Recording")
                        : error.localizedDescription,
                    tone: Task.isCancelled ? .info : .error
                )
                if !Task.isCancelled {
                    SoundController.shared.play(.error)
                }
            }
        }
    }

    /// Runs an Editor subset preview through the same manual-playback ownership seam
    /// as Library playback. This keeps Stop, App window locking, Automation resource
    /// arbitration, target preparation, and visibility restoration consistent.
    func playEditorPreview(events: [RecordedEvent], sourceMacro: SavedMacro?) {
        guard !events.isEmpty else {
            state.presentStatus(
                String(localized: "This preview has no playable actions.", table: "Common"),
                tone: .warning
            )
            return
        }
        guard canStartForegroundInputSession else {
            state.presentStatus(
                String(localized: "Stop recording or playback before previewing.", table: "Automation"),
                tone: .warning
            )
            return
        }
        if let failure = player.playbackPermissionFailure {
            state.presentStatus(failure, tone: .error)
            SoundController.shared.play(.error)
            showSettingsWindow()
            return
        }

        var preview = sourceMacro ?? SavedMacro(name: "Preview", events: events, loops: 1)
        preview.events = events
        preview.loops = 1
        preview.chainTo = nil
        if sourceMacro == nil {
            preview.speed = state.speed
        }
        guard !PlaybackPlanner.plan(
            events: preview.events,
            loops: preview.loops,
            speed: preview.speed
        ).steps.isEmpty else {
            state.presentStatus(
                String(localized: "This preview has no playable actions.", table: "Common"),
                tone: .warning
            )
            return
        }

        playbackRequestGeneration &+= 1
        let generation = playbackRequestGeneration
        let client = AutomationPlayerClient.live(player: player, windowTracker: WindowTracker())
        let request = AutomationPlayerStartRequest(
            runID: UUID(),
            macro: preview,
            targetApplicationPolicy: preview.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded,
            targetApplicationReadyDelay: 0,
            targetApplicationCleanupPolicy: .keepOpen,
            targetApplicationQuitTimeout: 5,
            targetApplicationForceQuitOnTimeout: false
        )

        manualPlaybackVisibilitySession.beginIfNeeded()
        state.playbackFlowActive = true
        state.presentStatus(
            String(localized: "Playing preview…", table: "Common"),
            tone: .progress
        )
        if popover.isShown { popover.performClose(nil) }
        if preview.surfaces.isEmpty { NSApp.hide(nil) }

        manualPlaybackTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.playbackRequestGeneration == generation {
                    self.manualPlaybackTask = nil
                    self.playingMacroID = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await AutomationScheduledMacroPreviewClient(player: client).run(
                    request,
                    onStarted: { [weak self] in
                        await MainActor.run {
                            guard let self,
                                  self.playbackRequestGeneration == generation else { return }
                            self.playingMacroID = preview.id
                            self.state.presentStatus(
                                String(localized: "Playing preview…", table: "Common"),
                                tone: .progress
                            )
                            SoundController.shared.play(.playStart)
                        }
                    }
                )
                try Task.checkCancellation()
                guard self.playbackRequestGeneration == generation else {
                    self.manualPlaybackVisibilitySession.restore()
                    return
                }
                self.state.playbackFlowActive = false
                self.manualPlaybackVisibilitySession.restore()
                self.state.presentStatus(
                    String(localized: "Preview finished.", table: "Common"),
                    tone: .success
                )
                SoundController.shared.play(.playEnd)
            } catch {
                self.manualPlaybackVisibilitySession.restore()
                guard self.playbackRequestGeneration == generation else { return }
                self.state.playbackFlowActive = false
                self.state.presentStatus(
                    Task.isCancelled
                        ? String(localized: "Playback stopped.", table: "Recording")
                        : error.localizedDescription,
                    tone: Task.isCancelled ? .info : .error
                )
                if !Task.isCancelled {
                    SoundController.shared.play(.error)
                }
            }
        }
    }

    /// Play a specific saved macro by id (used by per-macro hotkeys + library card buttons).
    /// Loading is part of the playback session: Stop can cancel it and recording cannot
    /// begin while an older async load is still able to replace the Recorder buffer.
    func playMacroByID(_ id: UUID, triggeredBy hotkey: HotkeyBinding? = nil) {
        guard let macroName = library.macros.first(where: { $0.id == id })?.name,
              !reconstructionTestActive else { return }
        if auxiliaryCaptureActive {
            stopAll()
            return
        }
        if recorder.isRecording {
            _ = stopRecordingAndSave(triggeredBy: hotkey?.recordingIgnoredKeyChord)
            state.presentStatus(
                String(
                    localized: "Recording stopped. Play again after saving finishes.",
                    table: "Recording"
                ),
                tone: .info
            )
            return
        }
        guard !state.recordingFinalizationActive else {
            state.presentStatus(
                String(
                    localized: "Wait for the current recording to finish saving before starting another recording or playback.",
                    table: "Recording"
                ),
                tone: .warning
            )
            return
        }

        let previous = manualPlaybackTask
        stopAll()
        persistCurrentMacroIfNeeded()
        chainVisited.removeAll()
        library.select(id: id)

        let generation = playbackRequestGeneration
        recorderLoadingMacroID = id
        state.playbackFlowActive = true
        state.presentStatus(
            String(
                format: String(localized: "Loading %@...", table: "Recording"),
                macroName
            ),
            tone: .progress
        )

        let loadTask = Task { [weak self] in
            await previous?.value
            guard let self,
                  self.playbackRequestGeneration == generation,
                  !Task.isCancelled else { return }
            do {
                let events = try await self.library.loadEvents(for: id)
                try Task.checkCancellation()
                guard self.playbackRequestGeneration == generation,
                      self.state.playbackFlowActive,
                      self.library.currentMacroID == id,
                      !self.recorder.isRecording,
                      !self.state.recordingFinalizationActive else { return }

                self.recorder.loadEvents(events)
                self.recorderLoadedMacroID = id
                if self.recorderLoadingMacroID == id {
                    self.recorderLoadingMacroID = nil
                }
                self.manualPlaybackTask = nil
                self.state.playbackFlowActive = false
                self.play()
            } catch {
                guard self.playbackRequestGeneration == generation else { return }
                if self.recorderLoadingMacroID == id {
                    self.recorderLoadingMacroID = nil
                }
                self.manualPlaybackTask = nil
                self.state.playbackFlowActive = false
                self.state.presentStatus(
                    Task.isCancelled
                        ? String(localized: "Playback stopped.", table: "Recording")
                        : String(
                            format: String(localized: "Failed to load %@.", table: "Recording"),
                            macroName
                        ),
                    tone: Task.isCancelled ? .info : .error
                )
            }
        }
        manualPlaybackTask = loadTask
    }

    func reconstructionReviewModel(for id: UUID) -> MacroReconstructionReviewModel {
        MacroReconstructionReviewModel(macroID: id, testMacro: { [weak self] macro in
            guard let self, self.canStartForegroundInputSession else {
                throw AutomationTargetApplicationPreparationFailure(message: String(
                    localized: "Stop recording or playback before previewing.", table: "Automation"))
            }
            guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
                throw AutomationTargetApplicationPreparationFailure(message: String(
                    localized: "Macro has no playable events.", table: "Automation"))
            }
            self.reconstructionTestActive = true
            self.state.playbackFlowActive = true
            defer {
                self.reconstructionTestActive = false
                self.state.playbackFlowActive = false
            }
            let client = AutomationPlayerClient.live(player: self.player, windowTracker: WindowTracker())
            let request = AutomationPlayerStartRequest(runID: UUID(), macro: macro,
                targetApplicationPolicy: macro.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded,
                targetApplicationReadyDelay: 0, targetApplicationCleanupPolicy: .keepOpen,
                targetApplicationQuitTimeout: 5, targetApplicationForceQuitOnTimeout: false)
            if let failure = self.player.playbackPermissionFailure {
                throw AutomationScheduledMacroPreviewFailure(message: failure)
            }
            let visibility = ApplicationWindowVisibilitySnapshot.capture()
            if macro.surfaces.isEmpty { NSApp.hide(nil) }
            defer { visibility.restore() }
            try await AutomationScheduledMacroPreviewClient(player: client).run(request)
        }, stopTest: { [weak self] in
            self?.player.stop()
        }, canPublish: { [weak self] in
            guard let self else { return false }
            return self.canStartForegroundInputSession
        }, editCandidate: { [weak self] candidate, onSaved in
            self?.openCandidateEditor(candidate, onSaved: onSaved)
        }, onRevision: { [weak self] macro in
            guard let self else { return }
            await self.library.load()
            if self.library.currentMacroID == macro.id, !self.recorder.isRecording {
                self.recorder.loadEvents(macro.events)
                self.recorderLoadedMacroID = macro.id
            }
        })
    }

    func previewScheduledMacro(
        _ id: UUID,
        taskConfiguration: AutomationTask? = nil
    ) async throws {
        guard var macro = library.macros.first(where: { $0.id == id }) else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "The macro is no longer available.",
                table: "Automation"
            ))
        }
        guard canStartForegroundInputSession else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "Stop recording or playback before previewing.",
                table: "Automation"
            ))
        }

        macro.events = try await library.loadEvents(for: id)
        guard canStartForegroundInputSession else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "Stop recording or playback before previewing.",
                table: "Automation"
            ))
        }
        macro.loops = 1
        guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "Macro has no playable events.",
                table: "Automation"
            ))
        }

        let previewVisibility = ApplicationWindowVisibilitySnapshot.capture()
        state.playbackFlowActive = true
        defer {
            state.playbackFlowActive = false
            previewVisibility.restore()
        }

        let runID = UUID()
        let windowTracker = WindowTracker()
        let previewPlayer = AutomationPlayerClient.live(
            player: player,
            windowTracker: windowTracker
        )
        let request = AutomationPlayerStartRequest(
            runID: runID,
            macro: macro,
            targetApplicationPolicy: taskConfiguration?.targetApplicationPolicy
                ?? (macro.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded),
            targetApplicationReadyDelay: taskConfiguration?.targetApplicationReadyDelay ?? 0,
            targetApplicationCleanupPolicy: taskConfiguration?.targetApplicationCleanupPolicy
                ?? .quitIfLaunched,
            targetApplicationQuitTimeout: taskConfiguration?.targetApplicationQuitTimeout ?? 5,
            targetApplicationForceQuitOnTimeout: taskConfiguration?.targetApplicationForceQuitOnTimeout
                ?? true
        )

        try await AutomationScheduledMacroPreviewClient(player: previewPlayer).run(request)
    }

    // MARK: - Save / Open / Export

    private var auxiliaryCaptureActive: Bool {
        auxiliaryCaptureActivityCenter.isActive
    }

    private var appInputSessionActivity: AppInputSessionActivity {
        AppInputSessionActivity(
            recordingFlowActive: state.recordingFlowActive,
            isRecording: recorder.isRecording,
            recordingFinalizationActive: state.recordingFinalizationActive,
            manualPlaybackActive: state.playbackFlowActive || manualPlaybackTask != nil,
            playbackTargetReserved: player.isPlaybackTargetReserved,
            isPlaying: player.isPlaying,
            reconstructionTestActive: reconstructionTestActive,
            auxiliaryCaptureActive: auxiliaryCaptureActive
        )
    }

    private func cancelAuxiliaryCaptures() {
        windowTargetPicker.cancel()
        CoordinatePickerOverlay.shared.cancel()
        TextPickerOverlay.shared.cancel()
        AutomationOCRRegionPickerOverlay.shared.cancel()
    }

    func requireScreenPickingAvailable() -> Bool {
        guard canStartForegroundInputSession else {
            state.presentStatus(
                String(
                    localized: "Finish the current recording or playback before picking from the screen.",
                    table: "EditorUX"
                ),
                tone: .warning
            )
            return false
        }
        return true
    }

    private var canStartForegroundInputSession: Bool {
        !appInputSessionActivity.blocksForegroundInputStart
            && !recordingPreparationActive
            && countdown?.isActive != true
    }

    private var macroLibraryInteractionLocked: Bool {
        AppInputSessionInteractionLock.protectsMacroLibrary(appInputSessionActivity)
    }

    private var captureSurfaceInteractionLocked: Bool {
        AppInputSessionInteractionLock.protectsAppWindows(appInputSessionActivity)
    }

    var preventsSystemWindowReopen: Bool {
        captureSurfaceInteractionLocked
    }

    var appMenuInteractionLocked: Bool {
        appInputSessionActivity.ownsInputOrCaptureTarget
    }

    var stopMenuMode: AppStopMenuMode {
        AppStopMenuMode.project(appInputSessionActivity)
    }

    @discardableResult
    private func requireMacroLibraryInteractionAvailable() -> Bool {
        guard !macroLibraryInteractionLocked else {
            state.presentStatus(
                String(
                    localized: "Wait for the current recording to finish saving, or stop recording or playback, before opening or changing the macro library.",
                    table: "Common"
                ),
                tone: .warning
            )
            SoundController.shared.play(.error)
            return false
        }
        return true
    }

    @discardableResult
    private func requireCaptureSurfaceInteractionAvailable() -> Bool {
        guard !captureSurfaceInteractionLocked else {
            state.presentStatus(
                String(
                    localized: "Wait for the current recording to finish saving, or stop recording or playback, before opening another SparkleRecorder window.",
                    table: "Common"
                ),
                tone: .warning
            )
            SoundController.shared.play(.error)
            return false
        }
        return true
    }

    func openExternalMacroFiles(_ urls: [URL]) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        enqueueMacroImports(urls, showMainWindowAfterward: true)
    }

    /// Import any supported macro file without blocking the MainActor on file IO
    /// or decoding. Library mutation is committed back on MainActor only after the
    /// input-session lock is rechecked.
    func importMacro(at url: URL) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        enqueueMacroImports([url], showMainWindowAfterward: false)
    }

    private func enqueueMacroImports(
        _ urls: [URL],
        showMainWindowAfterward: Bool
    ) {
        guard !urls.isEmpty else { return }
        let previous = macroImportTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await self.performMacroImports(
                urls,
                showMainWindowAfterward: showMainWindowAfterward
            )
        }
        macroImportTail = task
    }

    private func performMacroImports(
        _ urls: [URL],
        showMainWindowAfterward: Bool
    ) async {
        for url in urls {
            guard !macroLibraryInteractionLocked else {
                state.presentStatus(
                    String(
                        localized: "Import stopped because recording or playback started. Try again after it finishes.",
                        table: "Common"
                    ),
                    tone: .warning
                )
                SoundController.shared.play(.error)
                return
            }

            state.presentStatus(
                String(
                    format: String(localized: "Importing %@…", table: "Common"),
                    url.lastPathComponent
                ),
                tone: .progress
            )

            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try MacroImportLoader.load(url: url)
                }.value

                guard !macroLibraryInteractionLocked else {
                    state.presentStatus(
                        String(
                            localized: "Import stopped because recording or playback started. Try again after it finishes.",
                            table: "Common"
                        ),
                        tone: .warning
                    )
                    SoundController.shared.play(.error)
                    return
                }
                applyPreparedMacroImport(prepared)
            } catch {
                state.presentStatus(
                    String(
                        format: String(localized: "Import failed: %@", table: "Common"),
                        MacroImportPresentation.errorMessage(error)
                    ),
                    tone: .error
                )
                SoundController.shared.play(.error)
            }
        }

        if showMainWindowAfterward, !captureSurfaceInteractionLocked {
            showMainWindow()
        }
    }

    private func applyPreparedMacroImport(_ prepared: PreparedMacroImport) {
        switch prepared {
        case .savedMacro(let saved):
            let copy = SavedMacroStandaloneTransfer.importedCopy(from: saved)
            library.insert(copy)
            recorder.loadEvents(copy.events)
            recorderLoadedMacroID = copy.id
            state.presentStatus(
                String(
                    format: String(localized: "Imported %@.", table: "Common"),
                    copy.name
                ),
                tone: .success
            )

        case .events(let name, let events, let skippedEntryCount, let legacyVersionWarning):
            let imported = library.add(events: events, name: name)
            recorder.loadEvents(imported.events)
            recorderLoadedMacroID = imported.id
            if let warning = MacroImportPresentation.warning(
                skippedEntryCount: skippedEntryCount,
                legacyVersionWarning: legacyVersionWarning
            ) {
                state.presentStatus(
                    String(
                        format: String(localized: "Imported %@ — %@", table: "Common"),
                        imported.name,
                        warning
                    ),
                    tone: .warning
                )
            } else {
                state.presentStatus(
                    String(
                        format: String(localized: "Imported %@ · %d actions.", table: "Common"),
                        imported.name,
                        events.count
                    ),
                    tone: .success
                )
            }
        }
    }

    /// Export the current macro as a hand-editable `.txt` (TRM) file.
    func exportAsText() {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard !recorder.events.isEmpty else {
            state.presentStatus(
                String(localized: "This macro has no actions to export.", table: "Common"),
                tone: .warning
            )
            return
        }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export as Text", table: "Common")
        let baseName = library.currentMacro?.name ?? defaultMacroName()
        panel.nameFieldStringValue = baseName + ".txt"
        if let ut = UTType(filenameExtension: "txt") {
            panel.allowedContentTypes = [ut]
        }
        panel.canCreateDirectories = true
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    let events = try await MacroExportPrivacySanitizer.live.prepare(
                        self.recorder.events,
                        macro: self.library.currentMacro
                    )
                    try await MacroExportWriter.writeText(events, to: url)
                    self.state.presentStatus(
                        self.exportSucceededStatus(url.lastPathComponent),
                        tone: .success
                    )
                } catch {
                    self.state.presentStatus(self.exportFailedStatus(error), tone: .error)
                }
            }
        }
    }

    /// Export a specific macro (by id) as a `.txt` (TRM) file.
    func exportMacroAsText(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = String(
            format: String(localized: "Export %@ as Text", table: "Common"),
            macro.name
        )
        panel.nameFieldStringValue = macro.name + ".txt"
        if let ut = UTType(filenameExtension: "txt") {
            panel.allowedContentTypes = [ut]
        }
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    let loadedEvents = try await self.loadedEventsForExport(macro: macro)
                    let events = try await MacroExportPrivacySanitizer.live.prepare(
                        loadedEvents,
                        macro: macro
                    )
                    try await MacroExportWriter.writeText(events, to: url)
                    self.state.presentStatus(
                        self.exportSucceededStatus(url.lastPathComponent),
                        tone: .success
                    )
                } catch {
                    self.state.presentStatus(self.exportFailedStatus(error), tone: .error)
                }
            }
        }
    }

    func open() {
        guard requireMacroLibraryInteractionAvailable() else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Macro", table: "Common")
        panel.message = String(
            localized: "Import a SparkleRecorder (.tinyrec), legacy Windows .rec, or text (.txt) macro.",
            table: "Common"
        )
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let exts = ["tinyrec", "rec", "txt", "trm"]
        var types = exts.compactMap { UTType(filenameExtension: $0) }
        types.append(.json)
        types.append(.plainText)
        panel.allowedContentTypes = types
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.enqueueMacroImports(panel.urls, showMainWindowAfterward: false)
        }
    }

    func exportAsScript() {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard !recorder.events.isEmpty else {
            state.presentStatus(
                String(localized: "This macro has no actions to export.", table: "Common"),
                tone: .warning
            )
            return
        }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export as Shell Script", table: "Common")
        let baseName = library.currentMacro?.name ?? defaultMacroName()
        panel.nameFieldStringValue = baseName + ".command"
        if let ut = UTType(filenameExtension: "command") {
            panel.allowedContentTypes = [ut]
        }
        panel.canCreateDirectories = true
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    // Embed the full v3 SavedMacro so name/speed/loops survive the
                    // round-trip. Hotkey and chain are meaningless outside this
                    // library, so strip them.
                    var payload: SavedMacro
                    if let current = self.library.currentMacro {
                        let events = try await MacroExportPrivacySanitizer.live.prepare(
                            self.recorder.events,
                            macro: current
                        )
                        payload = SavedMacroStandaloneTransfer.exportedPayload(
                            from: current,
                            events: events
                        )
                    } else {
                        payload = SavedMacro(
                            name: self.defaultMacroName(),
                            events: self.recorder.events
                        )
                    }
                    payload.hotkey = nil
                    payload.chainTo = nil
                    let exec = Bundle.main.executablePath ?? "/Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder"
                    try await MacroExportWriter.writeShellScript(
                        payload,
                        executablePath: exec,
                        to: url
                    )
                    self.state.presentStatus(
                        self.exportSucceededStatus(url.lastPathComponent),
                        tone: .success
                    )
                } catch {
                    self.state.presentStatus(self.exportFailedStatus(error), tone: .error)
                }
            }
        }
    }

    /// Export a specific macro (from card menu).
    func exportMacroToFile(_ id: UUID) {
        guard requireMacroLibraryInteractionAvailable() else { return }
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = String(
            format: String(localized: "Export %@", table: "Common"),
            macro.name
        )
        panel.nameFieldStringValue = macro.name + ".tinyrec"
        if let ut = UTType(filenameExtension: "tinyrec") {
            panel.allowedContentTypes = [ut]
        }
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    let loadedEvents = try await self.loadedEventsForExport(macro: macro)
                    let events = try await MacroExportPrivacySanitizer.live.prepare(
                        loadedEvents,
                        macro: macro
                    )
                    let payload = SavedMacroStandaloneTransfer.exportedPayload(
                        from: macro,
                        events: events
                    )
                    try await MacroExportWriter.writeNative(payload, to: url)
                    self.state.presentStatus(
                        self.exportSucceededStatus(url.lastPathComponent),
                        tone: .success
                    )
                } catch {
                    self.state.presentStatus(self.exportFailedStatus(error), tone: .error)
                }
            }
        }
    }

    private func exportSucceededStatus(_ fileName: String) -> String {
        String(
            format: String(localized: "Exported %@.", table: "Common"),
            fileName
        )
    }

    private func exportFailedStatus(_ error: Error) -> String {
        String(
            format: String(localized: "Export failed: %@", table: "Common"),
            error.localizedDescription
        )
    }

    func persistEdits() {
        persistCurrentMacroIfNeeded()
        state.presentStatus(
            String(localized: "Changes saved.", table: "Common"),
            tone: .success
        )
    }

    private func defaultMacroName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "macro-" + f.string(from: Date())
    }

    // MARK: - Editor

    func openEditor() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if popover.isShown { popover.performClose(nil) }
        if editorWC == nil {
            let view = EditorView(controller: self)
                .appStatusFeedbackOverlay(
                    state: state,
                    isWindow: true,
                    bottomPadding: 18
                )
                .environmentObject(recorder)
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(state)
            editorWC = EditorWindowController(rootView: view)
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWC?.showWindow(nil)
        editorWC?.window?.makeKeyAndOrderFront(nil)
    }

    func openCandidateEditor(
        _ candidate: MacroStoredCandidate,
        onSaved: @escaping @MainActor (MacroStoredCandidate) -> Void
    ) {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if popover.isShown { popover.performClose(nil) }

        guard closeCandidateEditor() else { return }
        persistCurrentMacroIfNeeded()
        if library.currentMacroID != candidate.macro.id {
            library.select(id: candidate.macro.id)
        }

        let draftRecorder = Recorder()
        draftRecorder.loadEvents(candidate.macro.events)
        let session = MacroCandidateEditorSession(candidate: candidate, onSaved: onSaved)
        let view = CandidateEditorContainer(controller: self, session: session)
            .appStatusFeedbackOverlay(
                state: state,
                isWindow: true,
                bottomPadding: 18
            )
            .environmentObject(draftRecorder)
            .environmentObject(player)
            .environmentObject(library)
            .environmentObject(state)

        let title = String(
            format: String(localized: "Candidate Editor — %@", table: "EditorUX"),
            candidate.macro.name
        )
        let windowController = EditorWindowController(rootView: view, title: title)
        windowController.shouldClose = { [weak session] in
            guard let session, session.hasChanges else { return true }
            let alert = NSAlert()
            alert.messageText = String(localized: "Discard candidate draft changes?", table: "EditorUX")
            alert.informativeText = String(localized: "The accepted macro is unchanged. Unsaved candidate edits will be lost.", table: "EditorUX")
            alert.addButton(withTitle: String(localized: "Discard changes", table: "EditorUX"))
            alert.addButton(withTitle: String(localized: "Keep editing", table: "EditorUX"))
            alert.alertStyle = .warning
            return alert.runModal() == .alertFirstButtonReturn
        }
        windowController.onClose = { [weak self, weak windowController] in
            guard let self, self.candidateEditorWC === windowController else { return }
            self.candidateEditorWC = nil
            self.candidateEditorSession = nil
            self.candidateEditorRecorder = nil
        }
        candidateEditorSession = session
        candidateEditorRecorder = draftRecorder
        candidateEditorWC = windowController

        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func closeCandidateEditor() -> Bool {
        guard let candidateEditorWC else { return true }
        candidateEditorWC.window?.performClose(nil)
        return self.candidateEditorWC == nil
    }

    // MARK: - Appearance (Dock vs menu-bar-only)

    /// Apply the persisted appearance mode to the activation policy. Call on launch.
    func applyAppearanceMode() {
        NSApp.setActivationPolicy(state.menuBarOnly ? .accessory : .regular)
    }

    /// Switch between Dock app (`.regular`) and menu-bar-only (`.accessory`) live.
    func setMenuBarOnly(_ menuBarOnly: Bool) {
        guard menuBarOnly != state.menuBarOnly else { return }
        state.menuBarOnly = menuBarOnly
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        if menuBarOnly {
            // No Dock icon now — flash the menu-bar popover so the control surface
            // is discoverable, then leave the user there.
            state.presentStatus(
                String(localized: "Menu-bar only. Click the menu-bar icon to open SparkleRecorder.", table: "Settings"),
                tone: .info
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showPopoverProgrammatically()
            }
        } else {
            // Dock icon returns — bring the app forward and show the library window.
            NSApp.activate(ignoringOtherApps: true)
            showMainWindow()
        }
    }

    /// Bring up the menu-bar popover from code (used after switching to menu-bar-only).
    func showPopoverProgrammatically() {
        guard !popover.isShown else { return }
        showPopover()
    }

    /// Opens the main library window (forwarded from AppDelegate so the controller
    /// can show it after an appearance switch).
    var showMainWindowHandler: (() -> Void)?
    func showMainWindow() {
        guard requireMacroLibraryInteractionAvailable() else { return }
        showMainWindowHandler?()
    }

    func showAutomationWorkspace() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        state.automationWorkspaceDestination = nil
        state.workspace = .automation
        if popover.isShown { popover.performClose(nil) }
        showMainWindow()
    }

    func showAutomationWorkspace(workflowID: UUID, taskID: UUID? = nil) {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        state.automationWorkspaceDestination = AutomationWorkspaceDestination(
            workflowID: workflowID,
            taskID: taskID
        )
        state.workspace = .automation
        if popover.isShown { popover.performClose(nil) }
        showMainWindow()
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if popover.isShown { popover.close() }
        if settingsWC == nil {
            settingsWC = SettingsWindowController(controller: self)
        }
        settingsWC?.show()
    }

    func showRunHistorySettings() {
        showSettingsWindow()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sparkleShowRunHistorySettings, object: nil)
        }
    }

    func applyLanguagePreferenceAndRelaunch(_ preference: AppLanguagePreference) {
        preference.apply()

        let bundleURL = Bundle.main.bundleURL
        let isApplicationBundle = bundleURL.pathExtension.lowercased() == "app"
        pendingRelaunchRequest = ApplicationRelaunchRequest(
            applicationURL: isApplicationBundle
                ? bundleURL
                : (Bundle.main.executableURL ?? bundleURL),
            isApplicationBundle: isApplicationBundle
        )
        // AppDelegate delays termination until recording evidence and repository
        // writes finish. The replacement process is launched from
        // applicationWillTerminate, after that preparation has completed.
        NSApp.terminate(nil)
    }

    func performPendingRelaunchIfNeeded() {
        guard let request = pendingRelaunchRequest else { return }
        pendingRelaunchRequest = nil
        do {
            try request.makeProcess().run()
        } catch {
            NSLog("SparkleRecorder: Failed to relaunch after language change: \(error)")
        }
    }

    // MARK: - Onboarding

    func showWelcomeIfNeeded() {
        guard !state.onboardingComplete else { return }
        if welcomeWC == nil {
            // Closing the window by ANY means (Done button or the red close
            // button) completes onboarding — never leave a half-finished state.
            welcomeWC = WelcomeWindowController(controller: self, onDone: { [weak self] in
                self?.welcomeWC?.window?.performClose(nil)
            }, onClose: { [weak self] in
                self?.state.onboardingComplete = true
                self?.welcomeWC = nil
            })
        }
        welcomeWC?.show()
    }

    func showWelcome() {
        // Force-show even if already complete.
        welcomeWC = WelcomeWindowController(controller: self, onDone: { [weak self] in
            self?.welcomeWC?.window?.performClose(nil)
        }, onClose: { [weak self] in
            self?.welcomeWC = nil
        })
        welcomeWC?.show()
    }

    // MARK: - Termination

    /// Completes termination-sensitive work before AppDelegate allows the process
    /// to exit. This deliberately waits for visual evidence and repository writes
    /// instead of relying on fire-and-forget Tasks during applicationWillTerminate.
    func prepareForTermination() async {
        await automationRuntimeHost?.stopAndWait()
        recordingPreparationTask?.cancel()
        recordingPreparationTask = nil
        recordingPreparationActive = false
        state.recordingFlowActive = false
        state.playbackFlowActive = false
        countdown?.cancel()
        playbackRequestGeneration &+= 1
        manualPlaybackTask?.cancel()
        manualPlaybackTask = nil
        playingMacroID = nil
        recorderLoadingMacroID = nil
        cancelAuxiliaryCaptures()
        manualPlaybackVisibilitySession.restore()
        if player.isPlaying { player.stop() }

        if recorder.isRecording {
            _ = stopRecordingAndSave()
        }

        if state.recordingFinalizationActive {
            await waitForRecordingFinalization()
        }

        // Imports do file IO off-main but commit through this controller. Let any
        // already-requested import either commit or abort against the session lock
        // before taking the final repository snapshot for termination.
        let importTask = macroImportTail
        await importTask?.value

        if !state.recordingFinalizationActive,
           let currentMacroID = library.currentMacroID,
                  recorderLoadedMacroID == currentMacroID,
                  recorderLoadingMacroID == nil {
            await library.persistEventsAndMetadataImmediately(
                id: currentMacroID,
                events: recorder.events
            )
        }

        await library.persistAllMetadataImmediately()
    }

    func showAboutPanel() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func showHelp() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if let url = URL(string: "https://github.com/Aaru1801/SparkleRecorder-macOS#readme") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilityPrefs() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringPrefs() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenCapturePrefs() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationPrefs() {
        guard requireCaptureSurfaceInteractionAvailable() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)   // prepareForTermination runs via applicationWillTerminate
    }
}

// MARK: - Icons

enum SparkleIcons {
    private static func make(_ name: String, description: String, color: NSColor? = nil) -> NSImage? {
        let baseCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let cfg: NSImage.SymbolConfiguration
        if let color {
            cfg = baseCfg.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        } else {
            cfg = baseCfg
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = (color == nil)
        return img
    }
    static var idle: NSImage? { make("record.circle", description: "SparkleRecorder") }
    static var recording: NSImage? { make("record.circle.fill", description: "SparkleRecorder — recording", color: .systemRed) }
    static var finalizing: NSImage? { make("arrow.triangle.2.circlepath.circle.fill", description: "SparkleRecorder — finishing recording", color: .systemOrange) }
    static var playing: NSImage? { make("play.circle.fill", description: "SparkleRecorder — playing", color: .systemGreen) }
}

import Cocoa
import SwiftUI
import Combine
import UniformTypeIdentifiers
import SparkleRecorderCore

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var globalClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var editorWC: EditorWindowController?
    private var hud: RecordingHUDController?
    private var countdown: CountdownOverlayController?
    private var manualPlaybackTask: Task<Void, Never>?
    private var playbackRequestGeneration: UInt64 = 0
    private var reconstructionTestActive = false
    private var recordingPreparationActive = false
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
    private var pendingRecordingStartMessage: String?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        automationRuntimeHost = LiveAutomationRuntimeHost(
            player: player,
            repository: automationRepository,
            externalSignal: .appSignals(automationSignalStore),
            manualApproval: AutomationManualApprovalPresenter.client(),
            ocrSearchRegionContext: Self.automationOCRSearchRegionContext
        )
        configureStatusItem()
        configurePopover()
        configureHUD()
        countdown = CountdownOverlayController()
        observeStateForIcon()
        observeSemanticRecordingStatus()
        observeLibraryForHotkeys()
        observeLibrarySelectionForInitialEventLoad()
        observeAccessibilityRevocation()
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
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        if recorder.isRecording {
            button.image = SparkleIcons.recording
            button.title = state.recordingHUDMode == .menuBar ? recordingMenuBarTitle : " REC"
            button.setAccessibilityLabel(recordingMenuBarAccessibilityLabel)
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
        popover.animates = !recorder.isRecording
        popover.contentSize = recorder.isRecording
            ? NSSize(width: 320, height: 276)
            : NSSize(width: 400, height: 540)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !recorder.isRecording {
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
    func cancelRecording() {
        guard recorder.isRecording else { return }
        recorder.cancelRecording()
        recorder.clearAll()
        recorderLoadedMacroID = nil
        // Restore the previously-active macro (if any) into the recorder buffer
        // so we don't leave the editor pointing at nothing.
        if let m = library.currentMacro {
            loadMacroEventsIntoRecorder(m.id)
        }
        hud?.hide()
        state.statusMessage = "Recording discarded."
        SoundController.shared.play(.error)
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
                self?.refreshIgnoredKeyCodes()
            }
            .store(in: &cancellables)
        // Global-hotkey changes go through reapplyHotkeys() explicitly from the
        // settings UI — no state-wide sink needed.
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

    /// If macOS Accessibility is revoked while a recording is live, the event tap
    /// goes dead but our UI would keep "recording" forever. Stop cleanly, keep the
    /// partial capture in the buffer (no silent auto-save), and tell the user.
    private func observeAccessibilityRevocation() {
        state.$accessibilityGranted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self, !granted, self.recorder.isRecording else { return }
                self.recorder.stopRecording()
                self.hud?.hide()
                self.state.statusMessage = "Recording stopped — Accessibility permission was revoked."
                SoundController.shared.play(.error)
            }
            .store(in: &cancellables)
    }

    private func registerAllHotkeys() {
        registerGlobalHotkeys()
        refreshPerMacroHotkeys()
        refreshIgnoredKeyCodes()
    }

    private func registerGlobalHotkeys() {
        for id in globalHotkeyIDs { HotkeyManager.shared.unregister(id) }
        globalHotkeyIDs.removeAll()

        let recordH: () -> Void = { [weak self] in self?.toggleRecording() }
        let stopH:   () -> Void = { [weak self] in self?.stopAll() }
        let playH:   () -> Void = { [weak self] in
            guard let self = self else { return }
            if self.player.isPlaying { self.stopAll() } else { self.play() }
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
                if self.player.isPlaying {
                    self.stopAll()
                } else {
                    self.playMacroByID(macroID)
                }
            }) {
                perMacroHotkeyIDs[id] = macroID
            }
        }
    }

    private func refreshIgnoredKeyCodes() {
        var ignore: Set<UInt16> = [
            UInt16(state.recordHotkey.keyCode),
            UInt16(state.stopHotkey.keyCode),
            UInt16(state.playHotkey.keyCode),
        ]
        for macro in library.macros {
            if let hk = macro.hotkey {
                ignore.insert(UInt16(hk.keyCode))
            }
        }
        recorder.ignoredKeyCodes = ignore
    }

    func reapplyHotkeys() {
        registerGlobalHotkeys()
        refreshPerMacroHotkeys()
        refreshIgnoredKeyCodes()
    }

    // MARK: - Library glue

    private func loadInitialMacroIntoRecorder() {
        if let m = library.currentMacro {
            loadMacroEventsIntoRecorder(m.id)
        }
    }

    func selectMacro(_ id: UUID) {
        persistCurrentMacroIfNeeded()
        library.select(id: id)
        if let m = library.currentMacro {
            state.statusMessage = "Loading \(m.name)..."
            loadMacroEventsIntoRecorder(m.id, statusName: m.name)
        }
    }

    private func loadMacroEventsIntoRecorder(_ id: UUID, statusName: String? = nil) {
        guard !recorder.isRecording else { return }
        guard recorderLoadedMacroID != id, recorderLoadingMacroID != id else { return }

        recorderLoadingMacroID = id
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.recorderLoadingMacroID == id {
                    self.recorderLoadingMacroID = nil
                }
            }

            do {
                let events = try await self.library.loadEvents(for: id)
                guard self.library.currentMacroID == id else { return }
                self.recorder.loadEvents(events)
                self.recorderLoadedMacroID = id
                if let statusName {
                    self.state.statusMessage = "Loaded \(statusName)."
                }
            } catch {
                if let statusName {
                    self.state.statusMessage = "Failed to load \(statusName)."
                }
            }
        }
    }

    func renameMacro(_ id: UUID, to name: String) {
        library.rename(id: id, to: name)
    }

    func duplicateMacro(_ id: UUID) {
        library.duplicate(id: id)
    }

    func deleteMacro(_ id: UUID) {
        // Only reload the recorder buffer when the CURRENT macro was deleted;
        // otherwise we'd wipe unsaved editor edits to an unrelated macro.
        let wasCurrent = (id == library.currentMacroID)
        library.delete(id: id)
        if wasCurrent {
            if let m = library.currentMacro {
                Task {
                    if let evs = try? await library.loadEvents(for: m.id) {
                        recorder.loadEvents(evs)
                    }
                }
            } else {
                recorder.clearAll()
            }
        }
    }

    func deleteMacros(_ ids: Set<UUID>) {
        let wasCurrent = library.currentMacroID.map { ids.contains($0) } ?? false
        library.deleteMany(ids: ids)
        if wasCurrent {
            if let m = library.currentMacro {
                Task {
                    if let evs = try? await library.loadEvents(for: m.id) {
                        recorder.loadEvents(evs)
                    }
                }
            } else {
                recorder.clearAll()
            }
        }
    }

    func setMacroLoops(_ id: UUID, to loops: Int) {
        library.setLoops(id: id, loops: loops)
    }

    func setMacroSpeed(_ id: UUID, to speed: Double) {
        library.setSpeed(id: id, speed: speed)
    }

    func setMacroIcon(_ id: UUID, to icon: String?) {
        library.setIcon(id: id, icon: icon)
    }

    func setMacroAccent(_ id: UUID, to color: String?) {
        library.setAccent(id: id, accent: color)
    }

    func setMacroHotkey(_ id: UUID, to hotkey: HotkeyBinding?) {
        library.setHotkey(id: id, hotkey: hotkey)
        refreshPerMacroHotkeys()
        refreshIgnoredKeyCodes()
    }

    func toggleFavorite(_ id: UUID) {
        library.toggleFavorite(id: id)
    }

    func addTag(_ id: UUID, _ tag: String) {
        library.addTag(id: id, tag)
    }

    func removeTag(_ id: UUID, _ tag: String) {
        library.removeTag(id: id, tag)
    }

    func setMacroNotes(_ id: UUID, to notes: String) {
        library.setNotes(id: id, notes: notes)
    }

    func setChain(_ id: UUID, to target: UUID?) {
        library.setChainTo(id: id, target: target)
    }

    func bindCurrentWindow(to id: UUID) {
        do {
            let capture = WindowSurfaceCapture()
            let surface = try capture.captureFrontmostWindow()
            library.setSurface(id: id, surface: surface)
            state.statusMessage = "Bound to \(surface.appName ?? "active window")."
            SoundController.shared.play(.tick)
        } catch {
            state.statusMessage = "Binding failed: \(error.localizedDescription)"
            SoundController.shared.play(.error)
        }
    }

    func clearWindowBinding(for id: UUID) {
        library.setSurface(id: id, surface: nil)
        state.statusMessage = "Cleared window binding."
        SoundController.shared.play(.tick)
    }

    private func persistCurrentMacroIfNeeded() {
        // Never persist while a recording is live: the buffer holds the partial
        // in-flight recording, and writing it over the selected macro destroys it.
        guard !recorder.isRecording else { return }
        guard let id = library.currentMacroID, recorderLoadedMacroID == id, recorderLoadingMacroID == nil else { return }
        library.updateEvents(id: id, events: recorder.events)
    }

    // MARK: - Actions

    func toggleRecording() {
        if manualPlaybackTask != nil { stopAll() }
        // A second press during the countdown means "never mind".
        if let countdown, countdown.isActive {
            countdown.cancel()
            state.statusMessage = "Recording cancelled."
            return
        }
        if recorder.isRecording {
            recorder.stopRecording()
            let count = recorder.eventCount
            if count > 0 {
                let newMacro = library.add(events: recorder.events, loops: state.loops)
                recorderLoadedMacroID = newMacro.id
                if !recorder.activeSurfaces.isEmpty {
                    library.setSurfaces(id: newMacro.id, surfaces: recorder.activeSurfaces)
                } else if let surface = recordedSurface {
                    library.setSurface(id: newMacro.id, surface: surface)
                }
                pendingSemanticRecordingMacroID = newMacro.id
                attachSemanticRecordingIfFinished(recorder.semanticRecordingStatus)
                state.statusMessage = "Saved \(newMacro.name) · \(count) events."
                SoundController.shared.play(.recordStop)
            } else {
                state.statusMessage = "No events captured."
                // Don't leave an empty buffer that a later persist would write
                // over the selected macro — restore it.
                if let m = library.currentMacro {
                    Task {
                        if let evs = try? await library.loadEvents(for: m.id) {
                            recorder.loadEvents(evs)
                        }
                    }
                }
            }
            hud?.hide()
        } else {
            beginRecordingFlow()
        }
    }

    /// Wraps the actual recording start with an optional countdown.
    private func beginRecordingFlow() {
        guard !reconstructionTestActive, !recordingPreparationActive else { return }
        recordingPreparationActive = true
        if player.isPlaying { player.stop() }
        persistCurrentMacroIfNeeded()

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingPreparationActive = false }
            await self.prepareSemanticRecordingAndContinue()
        }
    }

    private func prepareSemanticRecordingAndContinue() async {
        pendingRecordingStartMessage = nil
        state.semanticRecordingPreflightPresentation = nil
        guard state.semanticRecordingEnabled else {
            closePopoverForRecording()
            startRecordingAfterPreflight()
            return
        }

        state.statusMessage = "Checking visual recording permissions…"
        let result = await SemanticRecordingPreflightClient.live.evaluate()
        let presentation = SemanticRecordingPreflightPresenter.presentation(for: result)
        state.semanticRecordingPreflightPresentation = presentation

        guard presentation.canStart else {
            state.statusMessage = "Visual recording blocked: \(semanticRecordingIssueSummary(result.blockingIssues))"
            SoundController.shared.play(.error)
            showSettingsWindow()
            return
        }

        if presentation.status == .degraded {
            pendingRecordingStartMessage = "Recording with limited visual context."
        }
        closePopoverForRecording()
        startRecordingAfterPreflight()
    }

    private func closePopoverForRecording() {
        if popover.isShown { popover.performClose(nil) }
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
        let semanticCaptureTarget = SemanticRecordingCaptureTargetMapper.target(
            surface: recordedSurface
        )
        
        let ok = recorder.startRecording(
            semanticRecordingEnabled: state.semanticRecordingEnabled,
            semanticCaptureTarget: semanticCaptureTarget
        )
        if ok {
            showRecordingHUDIfNeeded()
            state.statusMessage = pendingRecordingStartMessage ?? "Recording…"
            pendingRecordingStartMessage = nil
            SoundController.shared.play(.recordStart)
        } else {
            pendingRecordingStartMessage = nil
            state.statusMessage = "Could not start. Grant Accessibility permission."
            SoundController.shared.play(.error)
        }
    }

    func stopAll() {
        playbackRequestGeneration &+= 1
        manualPlaybackTask?.cancel()
        manualPlaybackTask = nil
        player.stop()
        countdown?.cancel()
        if recorder.isRecording {
            // F7 = "abort". Throw away the in-flight recording instead of saving.
            cancelRecording()
            return
        }
        if player.isPlaying { player.stop() }
        state.statusMessage = "Stopped."
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
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled") else {
                return
            }
            state.statusMessage = "Visual recording blocked: \(semanticRecordingIssueSummary(preflight.blockingIssues))"

        case .failed(let message):
            pendingSemanticRecordingMacroID = nil
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled") else {
                return
            }
            state.statusMessage = "Visual recording failed: \(message)"

        case .cancelled:
            pendingSemanticRecordingMacroID = nil

        case .suppressed(let message):
            pendingSemanticRecordingMacroID = nil
            guard UserDefaults.standard.bool(forKey: "semanticRecordingEnabled") else {
                return
            }
            state.statusMessage = "Visual recording suppressed: \(message)"

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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let store = RecordingBundleStore(
                    rootDirectory: bundleDirectory.deletingLastPathComponent()
                )
                let bundle = try await store.loadBundle(from: bundleDirectory)
                guard bundle.id == bundleID else {
                    return
                }
                let events = try await library.loadEvents(for: macroID)
                let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
                    for: events,
                    bundle: bundle
                )
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
                    state.statusMessage = String(
                        format: "Saved visual evidence, withheld readable text from %d event(s), and left %d event(s) for Review.",
                        summary.sanitizedEventCount,
                        summary.reviewRequiredEventCount
                    )
                } else if summary.sanitizedEventCount > 0 {
                    state.statusMessage = String(
                        format: "Saved visual evidence and withheld readable text from %d event(s).",
                        summary.sanitizedEventCount
                    )
                } else if summary.reviewRequiredEventCount > 0 {
                    state.statusMessage = String(
                        format: "Saved visual evidence. %d sensitive event(s) need Review before playable text can be changed.",
                        summary.reviewRequiredEventCount
                    )
                }
            } catch {
                state.statusMessage = "Playable text sanitization skipped: \(error.localizedDescription)"
            }
        }
    }

    private func playbackSanitizedEventsForExport(
        _ events: [RecordedEvent],
        macro: SavedMacro?
    ) async -> [RecordedEvent] {
        guard let reference = macro?.semanticRecording else {
            return events
        }

        do {
            let bundle = try await RecordingBundleStore().loadBundle(
                recordingID: reference.recordingID
            )
            let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
                for: events,
                bundle: bundle
            )
            return plan.playbackPreservingSanitizedEvents(from: events)
        } catch {
            return events
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

    private func semanticRecordingIssueSummary(
        _ issues: [SemanticRecordingPreflightIssue]
    ) -> String {
        let labels = issues.prefix(2).map(\.permission.rawValue)
        guard !labels.isEmpty else {
            return "permissions unavailable"
        }
        return labels.joined(separator: ", ")
    }

    func refreshSemanticRecordingPreflightPresentation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            state.statusMessage = "Checking visual recording permissions..."
            let result = await SemanticRecordingPreflightClient.live.evaluate()
            state.semanticRecordingPreflightPresentation = SemanticRecordingPreflightPresenter.presentation(
                for: result
            )
            if result.isReadyToStart {
                state.statusMessage = result.isDegraded
                    ? "Visual recording can continue with limited context."
                    : "Visual recording is ready."
            } else {
                state.statusMessage = "Visual recording blocked: \(semanticRecordingIssueSummary(result.blockingIssues))"
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
            state.statusMessage = String(
                format: "Cleaned up %d expired visual evidence artifact(s) and %d bundle(s).",
                deletedArtifacts,
                deletedBundles
            )
        } catch {
            state.statusMessage = "Scheduled visual evidence cleanup failed: \(error.localizedDescription)"
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
                    state.statusMessage = String(
                        format: String(localized: "Cleaned up evidence from %d run(s) and removed %d old history record(s).", table: "Automation"),
                        result.prunedArtifactRunCount,
                        result.deletedMetadataRunCount
                    )
                } else {
                    state.automationRunLastCleanupEvidenceCount = 0
                    state.automationRunLastCleanupHistoryCount = 0
                    state.automationRunLastCleanupFreedByteCount = 0
                }
                state.automationRunLastScheduledRetentionCleanupAt = decision.evaluatedAt
            } catch {
                state.statusMessage = String(
                    format: String(localized: "Run history cleanup failed: %@", table: "Automation"),
                    error.localizedDescription
                )
                NSLog("SparkleRecorder: Run history cleanup failed: \(error)")
            }
        }
    }

    func play() {
        guard !reconstructionTestActive else { return }
        play(isChained: false)
    }

    private func play(isChained: Bool) {
        guard !recorder.events.isEmpty, recorderLoadingMacroID == nil else {
            state.statusMessage = String(localized: "No loaded actions to play. Select a macro and wait for it to load.", table: "Recording")
            return
        }
        guard !player.isPlaying, manualPlaybackTask == nil, !recordingPreparationActive else { return }
        if let failure = player.playbackPermissionFailure {
            state.statusMessage = failure
            SoundController.shared.play(.error)
            showSettingsWindow()
            return
        }
        countdown?.cancel()
        if recorder.isRecording { toggleRecording() }
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
        state.statusMessage = String(localized: "Preparing playback…", table: "Recording")
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
                        self.state.statusMessage = "Playing \(snapshot.name) · ×\(snapshot.loops)…"
                        SoundController.shared.play(.playStart)
                    }
                })
                try Task.checkCancellation()
                guard self.playbackRequestGeneration == generation else { return }
                let elapsed = CFAbsoluteTimeGetCurrent() - self.playStartTime
                self.library.recordPlay(id: snapshot.id, runTime: elapsed)
                self.state.statusMessage = String(localized: "Playback finished.", table: "Recording")
                SoundController.shared.play(.playEnd)
                let chainID = self.library.macros.first(where: { $0.id == snapshot.id })?.chainTo
                if let id = chainID, let next = self.library.macros.first(where: { $0.id == id }) {
                    guard !self.chainVisited.contains(id) else {
                        self.state.statusMessage = "Chain stopped (loop detected)."
                        return
                    }
                    self.library.select(id: id)
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let events = try await self.library.loadEvents(for: id)
                            guard self.playbackRequestGeneration == generation, self.library.currentMacroID == id else { return }
                            self.recorder.loadEvents(events)
                            self.recorderLoadedMacroID = id
                            self.state.statusMessage = "Chaining to \(next.name)…"
                            self.play(isChained: true)
                        } catch { self.state.statusMessage = error.localizedDescription }
                    }
                }
            } catch {
                guard self.playbackRequestGeneration == generation else { return }
                self.state.statusMessage = Task.isCancelled
                    ? String(localized: "Playback stopped.", table: "Recording") : error.localizedDescription
                if !Task.isCancelled {
                    NSApp.unhide(nil)
                    NSApp.activate()
                    SoundController.shared.play(.error)
                }
            }
        }
    }

    func preparePlaybackContext(for macro: SavedMacro?, completion: @escaping (PlaybackContext) -> Void) {
        guard let macro = macro else {
            completion(PlaybackContext())
            return
        }

        // Return the base context immediately. Player will use WindowTracker to lazily resolve
        // the frame for each surface during playback exactly when it's needed, preventing
        // stale upfront coordinates from breaking playback if a user moves windows.
        completion(macro.playbackContext)
    }

    /// Play a specific saved macro by id (used by per-macro hotkeys + library card buttons).
    func playMacroByID(_ id: UUID) {
        guard library.macros.contains(where: { $0.id == id }), !reconstructionTestActive else { return }
        if recorder.isRecording { toggleRecording() }
        let previous = manualPlaybackTask
        stopAll()
        persistCurrentMacroIfNeeded()
        chainVisited.removeAll()
        library.select(id: id)
        let generation = playbackRequestGeneration
        Task { [weak self] in
            await previous?.value
            guard let self, self.playbackRequestGeneration == generation else { return }
            do {
                let events = try await self.library.loadEvents(for: id)
                guard self.playbackRequestGeneration == generation, self.library.currentMacroID == id else { return }
                self.recorder.loadEvents(events)
                self.recorderLoadedMacroID = id
                self.recorderLoadingMacroID = nil
                self.manualPlaybackTask = nil
                self.play()
            } catch { self.state.statusMessage = error.localizedDescription }
        }
    }

    func reconstructionReviewModel(for id: UUID) -> MacroReconstructionReviewModel {
        MacroReconstructionReviewModel(macroID: id, testMacro: { [weak self] macro in
            guard let self, !self.recorder.isRecording, !self.player.isPlaying,
                  !self.reconstructionTestActive, self.manualPlaybackTask == nil, !self.recordingPreparationActive, self.countdown?.isActive != true else {
                throw AutomationTargetApplicationPreparationFailure(message: String(
                    localized: "Stop recording or playback before previewing.", table: "Automation"))
            }
            guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
                throw AutomationTargetApplicationPreparationFailure(message: String(
                    localized: "Macro has no playable events.", table: "Automation"))
            }
            self.reconstructionTestActive = true
            defer { self.reconstructionTestActive = false }
            let client = AutomationPlayerClient.live(player: self.player, windowTracker: WindowTracker())
            let request = AutomationPlayerStartRequest(runID: UUID(), macro: macro,
                targetApplicationPolicy: macro.surfaces.isEmpty ? .doNotActivate : .launchIfNeeded,
                targetApplicationReadyDelay: 0, targetApplicationCleanupPolicy: .keepOpen,
                targetApplicationQuitTimeout: 5, targetApplicationForceQuitOnTimeout: false)
            if let failure = self.player.playbackPermissionFailure {
                throw AutomationScheduledMacroPreviewFailure(message: failure)
            }
            if macro.surfaces.isEmpty { NSApp.hide(nil) }
            defer { NSApp.unhide(nil); NSApp.activate() }
            try await AutomationScheduledMacroPreviewClient(player: client).run(request)
        }, stopTest: {}, canPublish: { [weak self] in
            guard let self else { return false }
            return !self.recorder.isRecording && !self.player.isPlaying && !self.recordingPreparationActive
                && !self.reconstructionTestActive && self.manualPlaybackTask == nil && self.countdown?.isActive != true
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
        guard !recorder.isRecording, !player.isPlaying else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "Stop recording or playback before previewing.",
                table: "Automation"
            ))
        }

        macro.events = try await library.loadEvents(for: id)
        macro.loops = 1
        guard !PlaybackPlanner.plan(events: macro.events, loops: macro.loops, speed: macro.speed).steps.isEmpty else {
            throw AutomationTargetApplicationPreparationFailure(message: String(
                localized: "Macro has no playable events.",
                table: "Automation"
            ))
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

    /// Import any supported macro file: legacy Windows `.rec`, plain-text `.txt`/`.trm`,
    /// or native `.tinyrec`/`.json`. Dispatches on extension, falling back to a
    /// content sniff so a mislabeled file still has a chance.
    func importMacro(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            // Native formats first (preserve full metadata).
            if ext == "tinyrec" || ext == "json" {
                let dec = JSONDecoder()
                if let saved = try? dec.decode(SavedMacro.self, from: data) {
                    DispatchQueue.main.async {
                        var copy = saved
                        copy.id = UUID()
                        copy.hotkey = nil
                        self.library.insert(copy)
                        self.recorder.loadEvents(copy.events)
                        self.state.statusMessage = "Imported \(copy.name)."
                    }
                    return
                }
                if let macro = try? dec.decode(Macro.self, from: data) {
                    finishImport(events: macro.events, name: url.deletingPathExtension().lastPathComponent, warning: nil)
                    return
                }
            }

            // External formats by extension.
            let result: MacroImportResult
            switch ext {
            case "rec":
                result = try LegacyRecImporter.parse(data)
            case "txt", "trm":
                guard let text = String(data: data, encoding: .utf8) else {
                    throw MacroImportError.notTextFormat("file is not UTF-8 text.")
                }
                result = try TextMacroFormat.parse(text)
            default:
                // Unknown extension — sniff: legacy Windows .rec is binary multiple-of-20;
                // otherwise try text, then JSON.
                if data.count % 20 == 0, let r = try? LegacyRecImporter.parse(data) {
                    result = r
                } else if let text = String(data: data, encoding: .utf8),
                          let r = try? TextMacroFormat.parse(text) {
                    result = r
                } else if let macro = try? JSONDecoder().decode(Macro.self, from: data) {
                    result = MacroImportResult(events: macro.events, parsed: macro.events.count, skipped: 0, warning: nil)
                } else {
                    throw MacroImportError.unreadable("Unrecognized macro file format.")
                }
            }

            finishImport(events: result.events,
                         name: url.deletingPathExtension().lastPathComponent,
                         warning: result.warning ?? (result.skipped > 0 ? result.summary : nil))
        } catch {
            DispatchQueue.main.async {
                self.state.statusMessage = "Import failed: \(error.localizedDescription)"
                SoundController.shared.play(.error)
            }
        }
    }

    private func finishImport(events: [RecordedEvent], name: String, warning: String?) {
        DispatchQueue.main.async {
            let imported = self.library.add(events: events, name: name)
            self.recorder.loadEvents(imported.events)
            self.recorderLoadedMacroID = imported.id
            if let warning {
                self.state.statusMessage = "Imported \(imported.name) — \(warning)"
            } else {
                self.state.statusMessage = "Imported \(imported.name) · \(events.count) events."
            }
        }
    }

    /// Export the current macro as a hand-editable `.txt` (TRM) file.
    func exportAsText() {
        guard !recorder.events.isEmpty else {
            state.statusMessage = "Nothing to export."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export as Text"
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
                    let events = await self.playbackSanitizedEventsForExport(
                        self.recorder.events,
                        macro: self.library.currentMacro
                    )
                    let text = TextMacroFormat.export(events)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    self.state.statusMessage = "Exported \(url.lastPathComponent)."
                } catch {
                    self.state.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Export a specific macro (by id) as a `.txt` (TRM) file.
    func exportMacroAsText(_ id: UUID) {
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(macro.name) as Text"
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
                    let events = await self.playbackSanitizedEventsForExport(
                        loadedEvents,
                        macro: macro
                    )
                    let text = TextMacroFormat.export(events)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    self.state.statusMessage = "Exported \(url.lastPathComponent)."
                } catch {
                    self.state.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.title = "Import Macro"
        panel.message = "Import a SparkleRecorder (.tinyrec), legacy Windows .rec, or text (.txt) macro."
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
            for url in panel.urls { self.importMacro(at: url) }
        }
    }

    func exportAsScript() {
        guard !recorder.events.isEmpty else {
            state.statusMessage = "Nothing to export."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export as Shell Script"
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
                        payload = current
                        payload.events = await self.playbackSanitizedEventsForExport(
                            self.recorder.events,
                            macro: current
                        )
                    } else {
                        payload = SavedMacro(
                            name: self.defaultMacroName(),
                            events: self.recorder.events
                        )
                    }
                    payload.hotkey = nil
                    payload.chainTo = nil
                    let json = try JSONEncoder().encode(payload)
                    let exec = Bundle.main.executablePath ?? "/Applications/SparkleRecorder.app/Contents/MacOS/SparkleRecorder"
                    let macroLine = json.base64EncodedString()
                    let script = """
                    #!/bin/bash
                    # SparkleRecorder self-running macro
                    EXEC="\(exec)"
                    if [ ! -x "$EXEC" ]; then
                        echo "SparkleRecorder binary not found at $EXEC. Please install SparkleRecorder."
                        exit 1
                    fi
                    TMP=$(mktemp -t tinyrec).json
                    echo "\(macroLine)" | base64 -D > "$TMP"
                    "$EXEC" --play "$TMP"
                    rm -f "$TMP"
                    """
                    try script.write(to: url, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                    self.state.statusMessage = "Exported \(url.lastPathComponent)."
                } catch {
                    self.state.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Export a specific macro (from card menu).
    func exportMacroToFile(_ id: UUID) {
        guard let macro = library.macros.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(macro.name)"
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
                    var payload = macro
                    let loadedEvents = try await self.loadedEventsForExport(macro: macro)
                    payload.events = await self.playbackSanitizedEventsForExport(
                        loadedEvents,
                        macro: macro
                    )
                    let enc = JSONEncoder()
                    enc.outputFormatting = [.prettyPrinted]
                    let data = try enc.encode(payload)
                    try data.write(to: url)
                    self.state.statusMessage = "Exported \(url.lastPathComponent)."
                } catch {
                    self.state.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func persistEdits() {
        persistCurrentMacroIfNeeded()
        state.statusMessage = "Saved."
    }

    private func defaultMacroName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "macro-" + f.string(from: Date())
    }

    // MARK: - Editor

    func openEditor() {
        if popover.isShown { popover.performClose(nil) }
        if editorWC == nil {
            let view = EditorView(controller: self)
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
            state.statusMessage = "Menu-bar only. Click the menu-bar icon to open SparkleRecorder."
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
    func showMainWindow() { showMainWindowHandler?() }

    func showAutomationWorkspace() {
        state.automationWorkspaceDestination = nil
        state.workspace = .automation
        if popover.isShown { popover.performClose(nil) }
        showMainWindow()
    }

    func showAutomationWorkspace(workflowID: UUID, taskID: UUID? = nil) {
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
        let applicationURL = isApplicationBundle
            ? bundleURL
            : (Bundle.main.executableURL ?? bundleURL)
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            isApplicationBundle
                ? "sleep 0.5; /usr/bin/open \"$1\""
                : "sleep 0.5; exec \"$1\"",
            "sparklerecorder-relaunch",
            applicationURL.path,
        ]

        do {
            try relauncher.run()
            NSApp.terminate(nil)
        } catch {
            state.statusMessage = String(
                format: String(localized: "Could not relaunch SparkleRecorder: %@", table: "Settings"),
                error.localizedDescription
            )
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

    /// Called from applicationWillTerminate so Cmd-Q never loses work:
    /// a live recording is stopped and saved, pending editor edits persist.
    func prepareForTermination() {
        automationRuntimeHost?.stop()
        countdown?.cancel()
        if player.isPlaying { player.stop() }
        if recorder.isRecording {
            recorder.stopRecording()
            if recorder.eventCount > 0 {
                library.add(events: recorder.events, loops: state.loops)
            }
        } else {
            persistCurrentMacroIfNeeded()
        }
        library.save()
    }

    func openAccessibilityPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenCapturePrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationPrefs() {
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
    static var playing: NSImage? { make("play.circle.fill", description: "SparkleRecorder — playing", color: .systemGreen) }
}

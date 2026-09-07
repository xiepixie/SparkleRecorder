import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

private enum MacroLibraryTestFailure: Error, LocalizedError {
    case failed

    var errorDescription: String? { "Synthetic repository failure" }
}

private actor CrossMacroPersistenceProbe {
    private var firstStarted = false
    private var secondStarted = false
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstReleased = false

    func persist(id: UUID, firstID: UUID, secondID: UUID) async {
        if id == firstID {
            firstStarted = true
            let waiters = firstStartWaiters
            firstStartWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            guard !firstReleased else { return }
            await withCheckedContinuation { continuation in
                firstReleaseWaiters.append(continuation)
            }
        } else if id == secondID {
            secondStarted = true
        }
    }

    func waitUntilFirstStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiters.append(continuation)
        }
    }

    func didStartSecond() -> Bool { secondStarted }

    func releaseFirst() {
        firstReleased = true
        let waiters = firstReleaseWaiters
        firstReleaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private actor MacroPersistenceProbe {
    private(set) var metadata: [UUID: SavedMacro] = [:]
    private(set) var events: [UUID: [RecordedEvent]] = [:]
    private var metadataWriteNames: [String] = []

    func saveMetadata(_ macro: SavedMacro) {
        metadata[macro.id] = macro
        metadataWriteNames.append(macro.name)
    }

    func saveEvents(_ value: [RecordedEvent], id: UUID) {
        events[id] = value
    }

    func metadata(for id: UUID) -> SavedMacro? { metadata[id] }
    func events(for id: UUID) -> [RecordedEvent]? { events[id] }
    func writeNames(suffixedBy suffix: String) -> [String] {
        metadataWriteNames.filter { $0.hasSuffix(suffix) }
    }
    func order(for id: UUID) -> Int? { metadata[id]?.libraryOrder }
    func metadataWriteCount() -> Int { metadataWriteNames.count }
}

@Suite("User Flow Integrity Tests")
struct UserFlowIntegrityTests {
    @Test("Hotkey identity includes modifiers")
    func hotkeyIdentityIncludesModifiers() {
        let optionR = HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048)
        let commandR = HotkeyBinding(keyCode: 15, name: "⌘R", modifiers: 256)
        let secondOptionR = HotkeyBinding(keyCode: 15, name: "Option-R", modifiers: 2048)

        #expect(!HotkeyConflictPolicy.conflicts(optionR, commandR))
        #expect(HotkeyConflictPolicy.conflicts(optionR, secondOptionR))
    }

    @Test("Input sessions lock app windows and macro-library interactions before input begins")
    func inputSessionsLockForegroundInteractions() {
        let idle = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )
        #expect(!AppInputSessionInteractionLock.protectsMacroLibrary(idle))
        #expect(!AppInputSessionInteractionLock.protectsAppWindows(idle))

        let recordingPreparation = AppInputSessionActivity(
            recordingFlowActive: true,
            isRecording: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )
        #expect(AppInputSessionInteractionLock.protectsMacroLibrary(recordingPreparation))
        #expect(AppInputSessionInteractionLock.protectsAppWindows(recordingPreparation))

        let recordingFinalization = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            recordingFinalizationActive: true,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )
        #expect(AppInputSessionInteractionLock.protectsMacroLibrary(recordingFinalization))
        #expect(!AppInputSessionInteractionLock.protectsAppWindows(recordingFinalization))
        #expect(recordingFinalization.blocksForegroundInputStart)

        let playbackPreparation = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            manualPlaybackActive: true,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false
        )
        #expect(AppInputSessionInteractionLock.protectsMacroLibrary(playbackPreparation))
        #expect(AppInputSessionInteractionLock.protectsAppWindows(playbackPreparation))

        let reconstructionTest = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: true
        )
        let automationPreparation = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            manualPlaybackActive: false,
            playbackTargetReserved: true,
            isPlaying: false,
            reconstructionTestActive: false
        )
        #expect(AppInputSessionInteractionLock.protectsAppWindows(reconstructionTest))
        #expect(AppInputSessionInteractionLock.protectsAppWindows(automationPreparation))
        #expect(AppInputSessionInteractionLock.protectsMacroLibrary(automationPreparation))

        let screenPicking = AppInputSessionActivity(
            recordingFlowActive: false,
            isRecording: false,
            manualPlaybackActive: false,
            playbackTargetReserved: false,
            isPlaying: false,
            reconstructionTestActive: false,
            auxiliaryCaptureActive: true
        )
        #expect(screenPicking.ownsInputOrCaptureTarget)
        #expect(AppInputSessionInteractionLock.protectsAppWindows(screenPicking))
        #expect(AppInputSessionInteractionLock.protectsMacroLibrary(screenPicking))
    }

    @Test("Language relaunch request preserves bundle and executable launch modes")
    func languageRelaunchRequestBuildsDeferredProcess() {
        let appURL = URL(fileURLWithPath: "/Applications/SparkleRecorder.app")
        let appRequest = ApplicationRelaunchRequest(
            applicationURL: appURL,
            isApplicationBundle: true
        )
        let appProcess = appRequest.makeProcess()
        #expect(appProcess.executableURL?.path == "/bin/sh")
        #expect(appProcess.arguments?.last == appURL.path)
        #expect(appProcess.arguments?[1].contains("/usr/bin/open") == true)

        let executableURL = URL(fileURLWithPath: "/tmp/SparkleRecorder")
        let executableRequest = ApplicationRelaunchRequest(
            applicationURL: executableURL,
            isApplicationBundle: false
        )
        let executableProcess = executableRequest.makeProcess()
        #expect(executableProcess.arguments?.last == executableURL.path)
        #expect(executableProcess.arguments?[1].contains("exec") == true)
    }

    @Test("Screen Recording is optional until visual evidence is enabled")
    func screenRecordingFollowsEnabledFeature() {
        let actionOnly = RecordingPermissionReadiness(
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            screenCaptureGranted: false,
            visualEvidenceEnabled: false
        )
        let withVisualEvidence = RecordingPermissionReadiness(
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            screenCaptureGranted: false,
            visualEvidenceEnabled: true
        )
        let fullyGranted = RecordingPermissionReadiness(
            accessibilityGranted: true,
            inputMonitoringGranted: true,
            screenCaptureGranted: true,
            visualEvidenceEnabled: true
        )

        #expect(actionOnly.canRecordInputs)
        #expect(actionOnly.canReplay)
        #expect(actionOnly.canRecordAndReplay)
        #expect(!actionOnly.shouldStopActiveRecording)
        #expect(actionOnly.allEnabledFeaturesReady)
        #expect(actionOnly.evidenceMode == .actionsOnly)
        #expect(withVisualEvidence.canRecordAndReplay)
        #expect(!withVisualEvidence.allEnabledFeaturesReady)
        #expect(withVisualEvidence.evidenceMode == .visualEvidenceBlocked)
        #expect(fullyGranted.allEnabledFeaturesReady)
        #expect(fullyGranted.evidenceMode == .actionsAndVisualEvidence)

        let playbackPermissionRevoked = RecordingPermissionReadiness(
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            screenCaptureGranted: true,
            visualEvidenceEnabled: false
        )
        #expect(playbackPermissionRevoked.canRecordInputs)
        #expect(!playbackPermissionRevoked.canReplay)
        #expect(!playbackPermissionRevoked.shouldStopActiveRecording)

        let inputMonitoringRevoked = RecordingPermissionReadiness(
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            screenCaptureGranted: true,
            visualEvidenceEnabled: false
        )
        #expect(!inputMonitoringRevoked.canRecordInputs)
        #expect(inputMonitoringRevoked.canReplay)
        #expect(inputMonitoringRevoked.shouldStopActiveRecording)
    }

    @Test("Standalone macro transfer removes library-local references")
    func standaloneMacroTransferRemovesLocalReferences() {
        let sourceID = UUID()
        let chainID = UUID()
        let recordingID = UUID()
        let source = SavedMacro(
            id: sourceID,
            name: "Portable",
            events: [],
            hotkey: HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048),
            chainTo: chainID,
            semanticRecording: MacroSemanticRecordingReference(
                recordingID: recordingID,
                bundleRelativePath: "SemanticRecordings/\(recordingID.uuidString)",
                manifestRelativePath: "SemanticRecordings/\(recordingID.uuidString)/manifest.json",
                eventCount: 3
            )
        )

        let exported = SavedMacroStandaloneTransfer.exportedPayload(from: source, events: [])
        #expect(exported.id == sourceID)
        #expect(exported.libraryOrder == nil)
        #expect(exported.chainTo == nil)
        #expect(exported.semanticRecording == nil)
        #expect(exported.hotkey == source.hotkey)

        let importedID = UUID()
        let imported = SavedMacroStandaloneTransfer.importedCopy(from: source, id: importedID)
        #expect(imported.id == importedID)
        #expect(imported.libraryOrder == nil)
        #expect(imported.hotkey == nil)
        #expect(imported.chainTo == nil)
        #expect(imported.semanticRecording == nil)
    }

    @Test("Automation deep links wait for the workflow and degrade missing tasks safely")
    func automationWorkspaceNavigation() {
        let workflowID = UUID()
        let task = AutomationTask(name: "Run", kind: .delay(1))
        let workflow = AutomationWorkflow(id: workflowID, name: "Flow", tasks: [task])

        let missingWorkflow = AutomationWorkspaceNavigation.resolve(
            AutomationWorkspaceDestination(workflowID: workflowID, taskID: task.id),
            workflows: []
        )
        #expect(missingWorkflow == nil)

        let taskResolution = AutomationWorkspaceNavigation.resolve(
            AutomationWorkspaceDestination(workflowID: workflowID, taskID: task.id),
            workflows: [workflow]
        )
        #expect(taskResolution?.workflowID == workflowID)
        #expect(taskResolution?.selection == .task(task.id))

        let missingTaskResolution = AutomationWorkspaceNavigation.resolve(
            AutomationWorkspaceDestination(workflowID: workflowID, taskID: UUID()),
            workflows: [workflow]
        )
        #expect(missingTaskResolution?.workflowID == workflowID)
        #expect(missingTaskResolution?.selection == .workflow)
    }

    @MainActor
    @Test("Library repairs a saved selection that no longer exists")
    func libraryRepairsMissingSavedSelection() async throws {
        let firstID = UUID()
        let first = SavedMacro(id: firstID, name: "First", events: [])
        let staleID = UUID()
        let previousSelection = UserDefaults.standard.string(forKey: "currentMacroID")
        defer {
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: "currentMacroID")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentMacroID")
            }
        }
        UserDefaults.standard.set(staleID.uuidString, forKey: "currentMacroID")

        let client = MacroRepositoryClient(
            loadAllManifests: { [first] },
            loadEvents: { _ in [] },
            saveMetadata: { _ in },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        #expect(library.currentMacroID == firstID)
    }

    @MainActor
    @Test("Library persistence preserves mutation order even when older writes are slower")
    func libraryPersistenceIsSerial() async {
        let macroID = UUID()
        let source = SavedMacro(id: macroID, name: "Source", events: [])
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [source] },
            loadEvents: { _ in [] },
            saveMetadata: { macro in
                if macro.name == "First edit" {
                    try? await Task.sleep(for: .milliseconds(40))
                }
                if macro.name.hasSuffix("edit") {
                    await probe.saveMetadata(macro)
                }
            },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.rename(id: macroID, to: "First edit")
        library.rename(id: macroID, to: "Second edit")
        await library.flushPendingPersistence()

        #expect(await probe.writeNames(suffixedBy: "edit") == ["First edit", "Second edit"])
    }

    @MainActor
    @Test("Slow persistence for one macro does not block another macro")
    func libraryPersistenceIsScopedPerMacro() async {
        let firstID = UUID()
        let secondID = UUID()
        let first = SavedMacro(id: firstID, name: "First", events: [])
        let second = SavedMacro(id: secondID, name: "Second", events: [])
        let probe = CrossMacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [first, second] },
            loadEvents: { _ in [] },
            saveMetadata: { macro in
                await probe.persist(id: macro.id, firstID: firstID, secondID: secondID)
            },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.save()
        await probe.waitUntilFirstStarts()
        // No wall-clock wait: yielding lets the independently queued second
        // Macro make progress while the first Macro remains deliberately blocked.
        for _ in 0..<8 { await Task.yield() }
        #expect(await probe.didStartSecond())

        await probe.releaseFirst()
        await library.flushPendingPersistence()
    }

    @MainActor
    @Test("Saving an already ordered Library does not rewrite unchanged macro metadata")
    func unchangedLibraryOrderDoesNotRewriteMetadata() async {
        let firstID = UUID()
        let secondID = UUID()
        let first = SavedMacro(id: firstID, name: "First", events: [], libraryOrder: 0)
        let second = SavedMacro(id: secondID, name: "Second", events: [], libraryOrder: 1)
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [first, second] },
            loadEvents: { _ in [] },
            saveMetadata: { macro in await probe.saveMetadata(macro) },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.save()
        await library.flushPendingPersistence()

        #expect(await probe.metadataWriteCount() == 0)
    }

    @MainActor
    @Test("Library drag order is persisted into macro metadata")
    func libraryOrderPersists() async {
        let firstID = UUID()
        let secondID = UUID()
        let first = SavedMacro(id: firstID, name: "First", events: [])
        let second = SavedMacro(id: secondID, name: "Second", events: [])
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [first, second] },
            loadEvents: { _ in [] },
            saveMetadata: { macro in await probe.saveMetadata(macro) },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.move(id: secondID, before: firstID)
        await library.flushPendingPersistence()

        #expect(await probe.order(for: secondID) == 0)
        #expect(await probe.order(for: firstID) == 1)
    }

    @Test("Repository reload respects persisted Library order")
    func repositoryReloadRespectsLibraryOrder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderOrderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MacroRepository(appSupportURL: root)

        var first = SavedMacro(name: "First", events: [])
        first.libraryOrder = 1
        var second = SavedMacro(name: "Second", events: [])
        second.libraryOrder = 0
        try await repository.saveMetadata(first)
        try await repository.saveEvents([], for: first.id)
        try await repository.saveMetadata(second)
        try await repository.saveEvents([], for: second.id)

        let reloaded = try await repository.loadAllManifests()
        #expect(reloaded.map(\.id) == [second.id, first.id])
    }

    @MainActor
    @Test("Macro hotkeys only replace an exact key and modifier chord")
    func macroHotkeysUseExactChord() async {
        let firstID = UUID()
        let secondID = UUID()
        let optionR = HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048)
        let commandR = HotkeyBinding(keyCode: 15, name: "⌘R", modifiers: 256)
        let first = SavedMacro(id: firstID, name: "First", events: [], hotkey: optionR)
        let second = SavedMacro(id: secondID, name: "Second", events: [])
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [first, second] },
            loadEvents: { _ in [] },
            saveMetadata: { macro in await probe.saveMetadata(macro) },
            saveEvents: { events, id in await probe.saveEvents(events, id: id) },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.setHotkey(id: secondID, hotkey: commandR)
        #expect(library.macros.first(where: { $0.id == firstID })?.hotkey == optionR)
        #expect(library.macros.first(where: { $0.id == secondID })?.hotkey == commandR)

        library.setHotkey(id: secondID, hotkey: optionR)
        #expect(library.macros.first(where: { $0.id == firstID })?.hotkey == nil)
        #expect(library.macros.first(where: { $0.id == secondID })?.hotkey == optionR)

        try? await Task.sleep(for: .milliseconds(10))
        #expect(await probe.metadata(for: firstID)?.hotkey == nil)
    }

    @MainActor
    @Test("Macro duplication awaits the full event snapshot before reporting success")
    func macroDuplicationAwaitsFullEventSnapshot() async throws {
        let sourceID = UUID()
        let sourceEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 20, y: 30),
            RecordedEvent.make(.leftMouseUp, time: 0.2, x: 20, y: 30),
        ]
        var source = SavedMacro(id: sourceID, name: "Source", events: [])
        source.favorite = true
        source.playCount = 9
        source.lastPlayedAt = Date(timeIntervalSince1970: 10)
        source.totalRunTime = 42
        source.hotkey = HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048)
        let sourceSnapshot = source
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [sourceSnapshot] },
            loadEvents: { id in id == sourceID ? sourceEvents : [] },
            saveMetadata: { macro in await probe.saveMetadata(macro) },
            saveEvents: { events, id in await probe.saveEvents(events, id: id) },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        let copy = try #require(try await library.duplicate(id: sourceID))
        await library.flushPendingPersistence()

        #expect(copy.id != sourceID)
        #expect(copy.name == "Source copy")
        #expect(copy.events == sourceEvents)
        #expect(!copy.favorite)
        #expect(copy.playCount == 0)
        #expect(copy.lastPlayedAt == nil)
        #expect(copy.totalRunTime == 0)
        #expect(copy.hotkey == nil)
        #expect(await probe.events(for: copy.id) == sourceEvents)
    }

    @MainActor
    @Test("Macro duplication failure leaves the Library unchanged")
    func macroDuplicationFailureLeavesLibraryUnchanged() async {
        let source = SavedMacro(name: "Source", events: [])
        let client = MacroRepositoryClient(
            loadAllManifests: { [source] },
            loadEvents: { _ in throw MacroLibraryTestFailure.failed },
            saveMetadata: { _ in },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        await #expect(throws: MacroLibraryTestFailure.self) {
            _ = try await library.duplicate(id: source.id)
        }

        #expect(library.macros.map(\.id) == [source.id])
        #expect(library.issue == .readMacro("Synthetic repository failure"))
    }

    @MainActor
    @Test("Macro chaining reports invalid targets instead of silently ignoring them")
    func macroChainingReportsInvalidTargets() async {
        let first = SavedMacro(name: "First", events: [])
        let second = SavedMacro(name: "Second", events: [])
        let client = MacroRepositoryClient(
            loadAllManifests: { [first, second] },
            loadEvents: { _ in [] },
            saveMetadata: { _ in },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        #expect(library.setChainTo(id: first.id, target: second.id) == .applied)
        #expect(library.setChainTo(id: first.id, target: first.id) == .selfReference)
        #expect(library.setChainTo(id: second.id, target: first.id) == .cycle)
        #expect(library.setChainTo(id: first.id, target: UUID()) == .targetMissing)
        #expect(library.setChainTo(id: UUID(), target: second.id) == .sourceMissing)
        #expect(library.setChainTo(id: first.id, target: nil) == .applied)
        #expect(library.macros.first(where: { $0.id == first.id })?.chainTo == nil)
    }

    @MainActor
    @Test("Macro library surfaces repository load failures")
    func macroLibrarySurfacesLoadFailures() async {
        let client = MacroRepositoryClient(
            loadAllManifests: { throw MacroLibraryTestFailure.failed },
            loadEvents: { _ in [] },
            saveMetadata: { _ in },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        #expect(library.issue == .loadLibrary("Synthetic repository failure"))
    }

    @MainActor
    @Test("Macro library surfaces queued persistence failures")
    func macroLibrarySurfacesPersistenceFailures() async {
        let macro = SavedMacro(name: "Persist", events: [])
        let client = MacroRepositoryClient(
            loadAllManifests: { [macro] },
            loadEvents: { _ in [] },
            saveMetadata: { _ in throw MacroLibraryTestFailure.failed },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        library.rename(id: macro.id, to: "Changed")
        await library.flushPendingPersistence()

        #expect(library.issue == .saveChanges("Synthetic repository failure"))
    }

    @MainActor
    @Test("Termination-sensitive persistence waits for events and metadata")
    func immediatePersistenceWaitsForRepositoryWrites() async {
        let macroID = UUID()
        let event = RecordedEvent.make(.leftMouseDown, time: 0.25, x: 10, y: 20)
        let macro = SavedMacro(id: macroID, name: "Persist me", events: [])
        let probe = MacroPersistenceProbe()
        let client = MacroRepositoryClient(
            loadAllManifests: { [macro] },
            loadEvents: { _ in [] },
            saveMetadata: { saved in await probe.saveMetadata(saved) },
            saveEvents: { events, id in await probe.saveEvents(events, id: id) },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
        let library = MacroLibrary(client: client)
        await library.load()

        await library.persistEventsAndMetadataImmediately(id: macroID, events: [event])

        #expect(await probe.events(for: macroID) == [event])
        #expect(await probe.metadata(for: macroID)?.eventCount == 1)
    }
}

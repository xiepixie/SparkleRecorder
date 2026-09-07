import Combine
import AppKit
import SwiftUI
import Foundation
import os
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro reconstruction review") @MainActor
struct MacroReconstructionReviewTests {
    private func fixture() throws -> (URL, MacroRepository, SavedMacro, MacroCandidateDocument) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let event = RecordedEvent(kind: .mouseMoved, time: 0, x: 10, y: 20, keyCode: 0, flags: 0,
                                  mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        let source = SavedMacro(name: "Review", events: [event])
        let revision = try MacroCandidateIdentity.revision(of: source)
        let sourceActions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        let targets = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: "candidate")
        return (root, MacroRepository(appSupportURL: root), source,
                MacroCandidateDocument(macro: source, sourceRevision: revision, coverage: zip(sourceActions, targets).map {
                    MacroCandidateCoverage(sourceActionID: $0.0.id, candidateActionIDs: [$0.1.id], reason: "Preserved source motion")
                }))
    }

    @Test("Action-only reconstruction never advertises frames to AI")
    func actionOnlyEvidenceCapabilityIsExplicit() async throws {
        let (root, repo, source, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)

        let model = MacroReconstructionReviewModel(
            macroID: source.id,
            repository: repo,
            testMacro: { _ in },
            stopTest: {},
            onRevision: { _ in }
        )
        await model.reload(loadEvidence: false)

        #expect(model.evidenceMode == .actionsOnly)
        #expect(!model.canIncludeVisualEvidence)
    }

    @Test("Linked but unavailable evidence stays distinct from action-only recording")
    func unavailableLinkedEvidenceIsExplicit() async throws {
        let (root, repo, source, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var linked = source
        let recordingID = UUID()
        linked.semanticRecording = MacroSemanticRecordingReference(
            recordingID: recordingID,
            bundleRelativePath: "SemanticRecordings/\(recordingID.uuidString)",
            manifestRelativePath: "SemanticRecordings/\(recordingID.uuidString)/manifest.json",
            eventCount: linked.events.count
        )
        try await repo.saveMetadata(linked)
        try await repo.saveEvents(linked.events, for: linked.id)

        let model = MacroReconstructionReviewModel(
            macroID: linked.id,
            repository: repo,
            testMacro: { _ in },
            stopTest: {},
            onRevision: { _ in }
        )
        await model.reload(loadEvidence: false)

        #expect(model.evidenceMode == .visualEvidenceUnavailable)
        #expect(!model.canIncludeVisualEvidence)
    }

    @Test("Accepted edits keep per-action video alignment through retained source coverage")
    func acceptedEditsKeepPartialVideoAlignment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MacroRepository(appSupportURL: root)
        let recordingID = UUID()
        let segmentID = UUID()
        var sourceEvents = TestFixtures.clickPair(downTime: 0, upTime: 0.05, x: 100, y: 100)
        sourceEvents += TestFixtures.clickPair(downTime: 0.20, upTime: 0.25, x: 300, y: 220)
        var source = SavedMacro(
            name: "Partial alignment",
            events: sourceEvents,
            semanticRecording: MacroSemanticRecordingReference(
                recordingID: recordingID,
                bundleRelativePath: MacroSemanticRecordingReference.defaultBundleRelativePath(recordingID: recordingID),
                manifestRelativePath: MacroSemanticRecordingReference.defaultManifestRelativePath(recordingID: recordingID),
                eventCount: sourceEvents.count
            )
        )
        try await repository.saveMetadata(source)
        try await repository.saveEvents(source.events, for: source.id)

        let sourceRevision = try MacroCandidateIdentity.revision(of: source)
        let sourceActions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: sourceRevision)
        var editedEvents = source.events
        editedEvents[0].x += 12
        editedEvents[1].x += 12
        var candidateMacro = source
        candidateMacro.events = editedEvents
        let candidateActions = try MacroActionReconstructor.reconstruct(events: editedEvents, sourceRevision: "candidate")
        let document = MacroCandidateDocument(
            macro: candidateMacro,
            sourceRevision: sourceRevision,
            coverage: zip(sourceActions, candidateActions).map { sourceAction, candidateAction in
                MacroCandidateCoverage(
                    sourceActionID: sourceAction.id,
                    disposition: .preserved,
                    candidateActionIDs: [candidateAction.id],
                    reason: "Mapped from recorded source"
                )
            }
        )
        let candidate = try await repository.importCandidate(document, for: source.id)
        let run = try await repository.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repository.recordCandidateTest(run, succeeded: true)
        source = try await repository.acceptCandidate(candidateID: candidate.id, for: source.id)

        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 100,
            sessionEndTime: 2,
            sourceEvents: sourceEvents.enumerated().map { index, event in
                RecordingSourceEventTime(
                    sourceEventIndex: index,
                    sourcePlaybackTime: event.time,
                    sessionTime: 1 + event.time
                )
            },
            clockSegments: [
                RecordingVideoClockSegment(
                    id: segmentID.uuidString,
                    anchors: [
                        RecordingVideoClockAnchor(recordingTime: 1, videoTime: 0),
                        RecordingVideoClockAnchor(recordingTime: 2, videoTime: 1)
                    ],
                    maximumError: 0
                )
            ],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: sourceEvents)
        )
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            videoSegments: [
                RecordingVideoSegment(
                    id: segmentID,
                    artifactRef: try RecordingArtifactRef("video/recording.mov"),
                    startTime: 0,
                    duration: 1
                )
            ],
            reconstructionProvenance: provenance
        )
        let reviewState = SemanticRecordingReviewState(
            sourceName: source.name,
            bundleDirectory: nil,
            loadedAt: Date(),
            bundle: bundle,
            suggestions: [],
            validationIssues: [],
            artifactStatuses: [:]
        )
        let model = MacroReconstructionReviewModel(
            macroID: source.id,
            repository: repository,
            testMacro: { _ in },
            stopTest: {},
            loadEvidence: { _, _ in reviewState },
            onRevision: { _ in }
        )
        await model.reload()

        #expect(model.sourceActions.count == 2)
        #expect(model.hasAlignedVideo)
        #expect(model.videoAlignmentQualityByActionID[model.sourceActions[0].id] == .coverageMapped)
        #expect(model.videoAlignmentQualityByActionID[model.sourceActions[1].id] == .exactSource)
        model.selectAction(model.sourceActions[0].id, candidate: false)
        #expect(model.statusMessage.isEmpty)
    }

    @Test("Edited legacy macro without retained source reports the real video alignment blocker")
    func editedLegacyMacroExplainsMissingLineage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MacroRepository(appSupportURL: root)
        let recordingID = UUID()
        let segmentID = UUID()
        let recordedEvents = [RecordedEvent.make(.leftMouseDown, time: 0, x: 100, y: 100)]
        var currentEvents = recordedEvents
        currentEvents[0].x = 180
        let source = SavedMacro(
            name: "Edited legacy",
            events: currentEvents,
            semanticRecording: MacroSemanticRecordingReference(
                recordingID: recordingID,
                bundleRelativePath: MacroSemanticRecordingReference.defaultBundleRelativePath(recordingID: recordingID),
                manifestRelativePath: MacroSemanticRecordingReference.defaultManifestRelativePath(recordingID: recordingID),
                eventCount: recordedEvents.count
            )
        )
        try await repository.saveMetadata(source)
        try await repository.saveEvents(source.events, for: source.id)
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 100,
            sessionEndTime: 1,
            sourceEvents: [RecordingSourceEventTime(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 0.1)],
            clockSegments: [
                RecordingVideoClockSegment(
                    id: segmentID.uuidString,
                    anchors: [
                        RecordingVideoClockAnchor(recordingTime: 0, videoTime: 0),
                        RecordingVideoClockAnchor(recordingTime: 1, videoTime: 1)
                    ],
                    maximumError: 0
                )
            ],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: recordedEvents)
        )
        let reviewState = SemanticRecordingReviewState(
            sourceName: source.name,
            bundleDirectory: nil,
            loadedAt: Date(),
            bundle: SemanticRecordingBundle(
                id: recordingID,
                videoSegments: [
                    RecordingVideoSegment(
                        id: segmentID,
                        artifactRef: try RecordingArtifactRef("video/recording.mov"),
                        startTime: 0,
                        duration: 1
                    )
                ],
                reconstructionProvenance: provenance
            ),
            suggestions: [],
            validationIssues: [],
            artifactStatuses: [:]
        )
        let model = MacroReconstructionReviewModel(
            macroID: source.id,
            repository: repository,
            testMacro: { _ in },
            stopTest: {},
            loadEvidence: { _, _ in reviewState },
            onRevision: { _ in }
        )
        await model.reload()

        #expect(model.videoAlignmentState == .sourceChangedWithoutLineage)
        #expect(!model.hasAlignedVideo)
    }

    @Test func successfulObservedTestEnablesAcceptanceAndRestore() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        var observed: SavedMacro?
        var published: SavedMacro?
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { observed = $0 }, stopTest: {}, onRevision: { published = $0 })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        try #require(model.selectedCandidate != nil, Comment(rawValue: model.errorMessage ?? "No candidate"))
        #expect(!model.canAccept)
        await model.testSelected()
        #expect(observed?.events == source.events)
        #expect(model.canAccept)
        await model.acceptSelected()
        #expect(published?.id == source.id)
        #expect(!model.canAccept)
        await model.restoreOriginal()
        #expect(try await repo.loadMacro(for: source.id).events == source.events)
    }

    @Test("Successful test reports the real remaining acceptance gate")
    func successfulTestReportsUncertaintyGate() async throws {
        let (root, repo, source, originalDocument) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        var document = originalDocument
        document.coverage[0].disposition = .unresolved
        document.uncertainActionIDs = [document.coverage[0].sourceActionID]
        let model = MacroReconstructionReviewModel(
            macroID: source.id,
            repository: repo,
            testMacro: { _ in },
            stopTest: {},
            onRevision: { _ in }
        )
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        await model.testSelected()

        #expect(model.hasSuccessfulTestForSelectedCandidate)
        #expect(!model.canAccept)
        #expect(model.acceptanceBlockedReason == String(
            localized: "Review and acknowledge the candidate's unresolved actions before accepting it.",
            table: "EditorUX"
        ))

        model.confirmUncertainties = true
        #expect(model.canAccept)
        #expect(model.acceptanceBlockedReason.isEmpty)
    }

    @Test func failureAndCandidateChangeCannotReuseSuccessfulUIReceipt() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let shouldFail = OSAllocatedUnfairLock(initialState: false)
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in
                if shouldFail.withLock({ $0 }) { throw CancellationError() }
            }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        try #require(model.selectedCandidate != nil, Comment(rawValue: model.errorMessage ?? "No candidate"))
        await model.testSelected()
        #expect(model.canAccept)
        shouldFail.withLock { $0 = true }
        await model.testSelected()
        #expect(!model.canAccept)
        #expect(model.errorMessage != nil)
        await model.importDocument(document)
        try #require(model.selectedCandidate != nil, Comment(rawValue: model.errorMessage ?? "No candidate"))
        #expect(!model.canAccept)
        #expect(try await repo.loadMacro(for: source.id).events == source.events)
    }
    @Test func stoppingDuringPreparationCannotEarnSuccessEvenIfAdapterReturns() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let entered = AsyncStream<Void>.makeStream()
        var resume: CheckedContinuation<Void, Never>?
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in
                await withCheckedContinuation { continuation in
                    resume = continuation
                    entered.continuation.yield(())
                }
            }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        let task = Task { await model.testSelected() }
        for await _ in entered.stream { break }
        model.cancelTest()
        resume?.resume()
        await task.value
        #expect(!model.canAccept)
        #expect(model.errorMessage != nil)
        let id = try #require(model.selectedCandidateID)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: id, for: source.id)
        }
    }

    /// Optional local visual QA. It renders only temporary fixture data offscreen.
    @Test func renderReviewFixturesWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["SPARKLE_RECONSTRUCTION_SNAPSHOT_DIR"] else { return }
        let (root, repo, source, originalDocument) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var events: [RecordedEvent] = []
        for i in 0..<25 {
            events.append(RecordedEvent(kind: i % 3 == 0 ? .leftMouseDown : (i % 3 == 1 ? .mouseMoved : .keyDown),
                                        time: Double(i) * 0.4, x: Double(100 + i * 5), y: Double(150 + i * 3),
                                        keyCode: 36, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0))
        }
        let richSource = SavedMacro(name: "收菜", events: events)
        try await repo.saveMetadata(richSource)
        try await repo.saveEvents(richSource.events, for: richSource.id)

        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared

        // Snapshot 1: Empty state in Dark mode (reproducing user's scenario before candidate import)
        let emptyModel = MacroReconstructionReviewModel(macroID: richSource.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await emptyModel.reload(loadEvidence: false)

        let viewEmpty = NSHostingView(rootView: MacroReconstructionSheet(model: emptyModel).preferredColorScheme(.dark).background(Color(nsColor: .windowBackgroundColor)))
        let windowEmpty = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 980, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        windowEmpty.appearance = NSAppearance(named: .darkAqua)
        windowEmpty.contentView = viewEmpty
        windowEmpty.displayIfNeeded()
        viewEmpty.frame = CGRect(x: 0, y: 0, width: 980, height: 820)
        viewEmpty.layoutSubtreeIfNeeded()
        viewEmpty.displayIfNeeded()
        let bitmapEmpty = try #require(viewEmpty.bitmapImageRepForCachingDisplay(in: viewEmpty.bounds))
        viewEmpty.cacheDisplay(in: viewEmpty.bounds, to: bitmapEmpty)
        let dataEmpty = try #require(bitmapEmpty.representation(using: .png, properties: [:]))
        try dataEmpty.write(to: output.appendingPathComponent("reconstruction-empty-dark.png"))

        // Snapshot 2: With candidate imported in Light mode
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        var document = originalDocument
        document.summary = "Keep the demonstrated pointer movement. No additional actions or waits are introduced."
        document.model = "Local review fixture"
        await model.importDocument(document)
        let view = NSHostingView(rootView: MacroReconstructionSheet(model: model).preferredColorScheme(.light).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 980, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.displayIfNeeded()
        view.frame = CGRect(x: 0, y: 0, width: 980, height: 820)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("reconstruction-review.png"))
    }

    @Test func idleVideoTicksDoNotPublishUnchangedReviewState() throws {
        let (root, repo, source, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        for i in 0..<1_000 { model.updateVideoPosition(Double(i) / 10, segmentID: "missing") }
        #expect(changes == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test func importFileAcceptsReconstructionPackageDirectory() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let package = root.appendingPathComponent("reconstruction-package", isDirectory: true)
        _ = try MacroReconstructionPackage.export(source: source, to: package)
        try MacroCandidateAuthoringProjection.encode(document)
            .write(to: package.appendingPathComponent("candidate.json"))

        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importFile(at: package)

        #expect(model.errorMessage == nil)
        #expect(model.selectedCandidate != nil)
        #expect(!model.isBusy)
    }

    @Test func importResetsCorrectionSelectionAndFileErrorsRemainRecoverable() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        model.selectAction(try #require(model.candidateActions.first).id, candidate: true)
        model.correctedText = "stale correction"
        await model.importDocument(document)
        #expect(model.selectedActionID == nil)
        #expect(model.correctedText.isEmpty)
        let selection = model.selectedCandidateID
        await model.importFile(at: root.appendingPathComponent("missing.json"))
        #expect(!model.isBusy)
        #expect(model.errorMessage != nil)
        #expect(model.selectedCandidateID == selection)
        #expect(model.candidateRows.map(\.id) == model.candidateActions.map(\.id))
        #expect(model.sourceRows.map(\.id) == model.sourceActions.map(\.id))
        await model.selectCandidate(nil)
        #expect(model.candidateRows.isEmpty)
        #expect(model.candidateActions.isEmpty)
        #expect(!model.isBusy)
    }

    @Test func reloadedSourceChangesDisableStaleCandidateBeforePlayback() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        var starts = 0
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in starts += 1 }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        var changed = source.events
        changed[0].x += 10
        try await repo.saveEvents(changed, for: source.id)
        await model.reload(loadEvidence: false)
        #expect(model.isSelectedCandidateStale)
        await model.testSelected()
        #expect(starts == 0)
        #expect(!model.canAccept)
    }

    @Test func failedProjectionReloadRetainsAConsistentVisibleSnapshot() async throws {
        let (root, repo, source, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        let oldRows = model.sourceRows.map(\.id)
        var invalid = source.events
        invalid[0].time = -1
        try await repo.saveEvents(invalid, for: source.id)
        await model.reload(loadEvidence: false)
        #expect(model.errorMessage != nil)
        #expect(model.source?.events == source.events)
        #expect(model.sourceRows.map(\.id) == oldRows)
        #expect(!model.isBusy)
    }

}

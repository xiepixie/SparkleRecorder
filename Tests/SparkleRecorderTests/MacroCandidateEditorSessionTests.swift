import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro candidate editor session") @MainActor
struct MacroCandidateEditorSessionTests {
    private func fixture() async throws -> (URL, MacroRepository, SavedMacro, MacroStoredCandidate) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0, x: 10, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 0.05, x: 10, y: 20)
        ]
        events.indices.forEach { events[$0].surfaceId = TestFixtures.surfaceId }
        let source = SavedMacro(
            name: "Candidate edit",
            events: events,
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface()]
        )
        let repository = MacroRepository(appSupportURL: root)
        try await repository.saveMetadata(source)
        try await repository.saveEvents(events, for: source.id)
        let revision = try MacroCandidateIdentity.revision(of: source)
        let sourceAction = try #require(
            MacroActionReconstructor.reconstruct(events: events, sourceRevision: revision).first
        )
        let candidateAction = try #require(
            MacroActionReconstructor.reconstruct(events: events, sourceRevision: "candidate").first
        )
        let document = MacroCandidateDocument(
            macro: source,
            sourceRevision: revision,
            coverage: [
                MacroCandidateCoverage(
                    sourceActionID: sourceAction.id,
                    disposition: .preserved,
                    candidateActionIDs: [candidateAction.id],
                    reason: "Preserved"
                )
            ]
        )
        let candidate = try await repository.importCandidate(document, for: source.id)
        return (root, repository, source, candidate)
    }

    @Test("Editing a tested version creates a new untested candidate and leaves accepted macro untouched")
    func editedCandidateNeedsRetest() async throws {
        let (root, repository, source, candidate) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try await repository.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repository.recordCandidateTest(run, succeeded: true)

        var saved: MacroStoredCandidate?
        let session = MacroCandidateEditorSession(
            candidate: candidate,
            repository: repository,
            onSaved: { saved = $0 }
        )
        var edited = candidate.macro.events
        edited[0].x = 120
        edited[1].x = 120
        session.updateEvents(edited)

        #expect(await session.save())
        let newCandidate = try #require(saved)
        #expect(newCandidate.id != candidate.id)
        #expect(newCandidate.macro.events[0].x == 120)
        #expect(try await repository.loadMacro(for: source.id).events == source.events)

        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repository.acceptCandidate(candidateID: newCandidate.id, for: source.id)
        }

        let oldAccepted = try await repository.acceptCandidate(candidateID: candidate.id, for: source.id)
        #expect(oldAccepted.events == source.events)
    }

    @Test("App-owned target window rebinding remains valid through test and acceptance")
    func localSurfaceRebindingRemainsSupported() async throws {
        let (root, repository, source, candidate) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let rebound = TestFixtures.surface(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "ChatGPT",
            recordedFrame: RectValue(x: 20, y: 40, width: 1200, height: 800),
            recordedContentFrame: RectValue(x: 20, y: 40, width: 1200, height: 800)
        )
        var saved: MacroStoredCandidate?
        let session = MacroCandidateEditorSession(
            candidate: candidate,
            repository: repository,
            onSaved: { saved = $0 }
        )
        #expect(session.rebindSurface(TestFixtures.surfaceId, to: rebound))

        #expect(await session.save())
        let localCandidate = try #require(saved)
        #expect(localCandidate.authoringOrigin == .localCandidateEditor)
        #expect(localCandidate.macro.surfaces[TestFixtures.surfaceId] == rebound)

        let run = try await repository.prepareCandidateTest(candidateID: localCandidate.id, for: source.id)
        try await repository.recordCandidateTest(run, succeeded: true)
        let accepted = try await repository.acceptCandidate(candidateID: localCandidate.id, for: source.id)
        #expect(accepted.surfaces[TestFixtures.surfaceId] == rebound)
    }

    @Test("Multi-surface rebinding changes only the requested Playback Surface")
    func multiSurfaceRebindingPreservesOtherSurfaces() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MacroRepository(appSupportURL: root)
        let first = TestFixtures.surface(appName: "First", bundleIdentifier: "app.first", windowTitle: "First")
        let second = TestFixtures.surface(appName: "Second", bundleIdentifier: "app.second", windowTitle: "Second")
        var events = TestFixtures.clickPair(downTime: 0, upTime: 0.05, x: 10, y: 20)
            + TestFixtures.clickPair(downTime: 0.2, upTime: 0.25, x: 30, y: 40)
        events[0].surfaceId = "surface-1"
        events[1].surfaceId = "surface-1"
        events[2].surfaceId = "surface-2"
        events[3].surfaceId = "surface-2"
        let source = SavedMacro(
            name: "Two surfaces",
            events: events,
            surfaces: ["surface-1": first, "surface-2": second]
        )
        try await repository.saveMetadata(source)
        try await repository.saveEvents(events, for: source.id)
        let revision = try MacroCandidateIdentity.revision(of: source)
        let sourceActions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: revision)
        let candidateActions = try MacroActionReconstructor.reconstruct(
            events: events,
            sourceRevision: MacroCandidateCapabilities.current.candidateActionRevision
        )
        let document = MacroCandidateDocument(
            macro: source,
            sourceRevision: revision,
            coverage: zip(sourceActions, candidateActions).map {
                MacroCandidateCoverage(sourceActionID: $0.0.id, candidateActionIDs: [$0.1.id], reason: "Preserved")
            }
        )
        let candidate = try await repository.importCandidate(document, for: source.id)
        let rebound = TestFixtures.surface(appName: "Second new", bundleIdentifier: "app.second", windowTitle: "Second new")
        var saved: MacroStoredCandidate?
        let session = MacroCandidateEditorSession(candidate: candidate, repository: repository) { saved = $0 }

        #expect(session.rebindSurface("surface-2", to: rebound))
        #expect(session.draftMacro.surfaces["surface-1"] == first)
        #expect(session.draftMacro.surfaces["surface-2"] == rebound)
        #expect(!session.removeSurface("surface-1"))
        #expect(session.draftMacro.surfaces.count == 2)
        #expect(await session.save())

        let stored = try #require(saved)
        #expect(stored.macro.surfaces["surface-1"] == first)
        #expect(stored.macro.surfaces["surface-2"] == rebound)
        #expect(stored.macro.events.map(\.surfaceId) == events.map(\.surfaceId))
    }

    @Test("Candidate editor can add a surface and explicitly move selected events before removing the old one")
    func candidateSurfaceAssignmentIsExplicit() async throws {
        let (root, repository, _, candidate) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MacroCandidateEditorSession(candidate: candidate, repository: repository) { _ in }
        let addedID = session.addSurface(TestFixtures.surface(appName: "Second"))

        #expect(addedID != TestFixtures.surfaceId)
        #expect(session.draftMacro.surfaces[addedID] != nil)
        #expect(!session.removeSurface(TestFixtures.surfaceId))
        #expect(session.assignSurface(addedID, toEventIndices: Array(session.draftMacro.events.indices)))
        #expect(session.removeSurface(TestFixtures.surfaceId))
        #expect(session.draftMacro.surfaces.keys.sorted() == [addedID])
        #expect(session.draftMacro.events.allSatisfy { $0.surfaceId == addedID })
    }

    @Test("Returning without edits preserves the exact tested candidate")
    func unchangedDraftPreservesCandidateIdentity() async throws {
        let (root, repository, _, candidate) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var saved: MacroStoredCandidate?
        let session = MacroCandidateEditorSession(
            candidate: candidate,
            repository: repository,
            onSaved: { saved = $0 }
        )

        #expect(await session.save())
        #expect(saved?.id == candidate.id)
        #expect(try await repository.listCandidates(for: candidate.macro.id).count == 1)
    }
}

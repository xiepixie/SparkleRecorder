import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro candidate repository")
struct MacroCandidateRepositoryTests {
    private func fixture() throws -> (URL, MacroRepository, SavedMacro, MacroCandidateDocument) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = SavedMacro(name: "Original", events: [event(0)])
        var proposed = source
        proposed.events = [event(1)]
        let revision = try MacroCandidateIdentity.revision(of: source)
        let sourceActions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        let targets = try MacroActionReconstructor.reconstruct(events: proposed.events, sourceRevision: "candidate")
        let document = MacroCandidateDocument(macro: proposed, sourceRevision: revision, summary: "Move later", coverage: sourceActions.map {
            MacroCandidateCoverage(sourceActionID: $0.id, disposition: .preserved, candidateActionIDs: targets.map(\.id), reason: "Preserved motion")
        })
        return (root, MacroRepository(appSupportURL: root), source, document)
    }

    private func event(_ time: Double) -> RecordedEvent {
        RecordedEvent(kind: .mouseMoved, time: time, x: 10, y: 20, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
    }

    @Test func continuousSourceGetsOneBoundedTestWithoutChangingAcceptedLoopSettings() async throws {
        let (root, repo, original, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var source = original
        source.loops = 0
        source.chainTo = UUID()
        let revision = try MacroCandidateIdentity.revision(of: source)
        let actions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        let targets = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: "candidate")
        let document = MacroCandidateDocument(macro: source, sourceRevision: revision, coverage: zip(actions, targets).map {
            .init(sourceActionID: $0.0.id, candidateActionIDs: [$0.1.id], reason: "Preserved")
        })
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        let run = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        #expect(run.macro.loops == 1)
        #expect(run.macro.chainTo == nil)
        #expect(run.executionDigest != run.normalizedDigest)
        try await repo.recordCandidateTest(run, succeeded: true)
        let accepted = try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        #expect(accepted.loops == 0)
        #expect(accepted.chainTo == source.chainTo)
    }

    @Test func revisionIdentityIsEncodedAsOneSafeSourceFilename() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(document.sourceRevision.contains("/"))
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        _ = try await repo.importCandidate(document, for: source.id)
        let storeURL = repo.packageURL(for: source.id).appendingPathComponent("reconstruction")
        let sources = try FileManager.default.contentsOfDirectory(at: storeURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("source-") }
        #expect(sources.count == 1)
        let retained = try JSONDecoder().decode(SavedMacro.self, from: Data(contentsOf: #require(sources.first)))
        #expect(retained.events == source.events)
    }

    @Test func retainedSourceRevisionCanBeReloadedForEvidenceLineage() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        _ = try await repo.importCandidate(document, for: source.id)

        let revision = try MacroCandidateIdentity.revision(of: source)
        #expect(try await repo.loadRetainedSource(revision: revision, for: source.id) == source)
        #expect(try await repo.loadRetainedSource(revision: "missing", for: source.id) == nil)
    }

    @Test func playbackLoadsWholeSnapshotWithoutSplitFallback() async throws {
        let id = UUID()
        let expected = SavedMacro(id: id, name: "Pinned", events: [event(3)], speed: 2)
        var client = repositoryClient(manifests: [])
        client.loadAllManifests = { throw MacroCandidateStoreError.staleSource }
        client.loadEvents = { _ in throw MacroCandidateStoreError.staleSource }
        client.loadSnapshot = { requestedID in requestedID == id ? expected : nil }
        #expect(try await client.loadPinnedMacro(id) == expected)
        #expect(try await client.loadPinnedMacro(UUID()) == nil)
    }

    @Test func olderRepositoryClientsRetainSplitLoadCompatibility() async throws {
        let macro = SavedMacro(name: "Legacy fake", events: [event(2)])
        var manifest = macro
        manifest.events = []
        var client = repositoryClient(manifests: [manifest])
        client.loadEvents = { _ in macro.events }
        #expect(try await client.loadPinnedMacro(macro.id) == macro)
        #expect(try await client.loadPinnedMacro(UUID()) == nil)
    }

    private func repositoryClient(manifests: [SavedMacro]) -> MacroRepositoryClient {
        MacroRepositoryClient(loadAllManifests: { manifests }, loadEvents: { _ in [] },
            saveMetadata: { _ in }, saveEvents: { _, _ in }, deleteMacro: { _ in },
            packageURL: { _ in URL(fileURLWithPath: "/unused-fixture") }, saveRunEvidence: { _, _, _ in })
    }

    @Test func requiresSuccessfulBoundTestAndPreservesMetadata() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
        let run = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repo.recordCandidateTest(run, succeeded: true)
        var edited = source
        edited.notes = "Keep notes"
        edited.playCount = 42
        edited.hotkey = HotkeyBinding(keyCode: 96, name: "F5")
        try await repo.saveMetadata(edited)
        let accepted = try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        #expect(accepted.events == document.macro.events)
        #expect(accepted.notes == edited.notes)
        #expect(accepted.playCount == 42)
        #expect(accepted.hotkey == edited.hotkey)
        #expect(accepted.id == source.id)
        let restarted = MacroRepository(appSupportURL: root)
        #expect(try await restarted.loadMacro(for: source.id) == accepted)
        let restored = try await restarted.restoreOriginal(for: source.id)
        #expect(restored.events == source.events)
        #expect(restored.notes == edited.notes)
        #expect(try await restarted.loadCandidate(candidateID: candidate.id, for: source.id).macro.events == document.macro.events)
    }

    @Test func testTokensAreConsumedAndUncertaintiesRequireAcknowledgement() async throws {
        let (root, repo, source, initial) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        var document = initial
        document.uncertainActionIDs = [try #require(MacroActionReconstructor.reconstruct(
            events: document.macro.events, sourceRevision: "candidate").first).id]
        let candidate = try await repo.importCandidate(document, for: source.id)
        let first = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        let second = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        await #expect(throws: MacroCandidateStoreError.invalidTestToken) {
            try await repo.recordCandidateTest(first, succeeded: true)
        }
        try await repo.recordCandidateTest(second, succeeded: true)
        await #expect(throws: MacroCandidateStoreError.invalidTestToken) {
            try await repo.recordCandidateTest(second, succeeded: true)
        }
        await #expect(throws: MacroCandidateStoreError.confirmationRequired) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
        let storeURL = repo.packageURL(for: source.id).appendingPathComponent("reconstruction")
        let originalURL = storeURL.appendingPathComponent("original.json")
        let candidateURL = storeURL.appendingPathComponent("candidate-\(candidate.id.uuidString).json")
        let originalBytes = try Data(contentsOf: originalURL)
        let candidateBytes = try Data(contentsOf: candidateURL)
        let accepted = try await repo.acceptCandidate(candidateID: candidate.id, for: source.id, confirmUncertainties: true)
        #expect(accepted.events == document.macro.events)
        _ = try await repo.restoreOriginal(for: source.id)
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try Data(contentsOf: candidateURL) == candidateBytes)
    }

    @Test func legacyStoredCandidateDefaultsToExternalSurfaceAuthority() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        let candidateURL = repo.packageURL(for: source.id)
            .appendingPathComponent("reconstruction/candidate-\(candidate.id.uuidString).json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: candidateURL)) as? [String: Any])
        object.removeValue(forKey: "authoringOrigin")
        try JSONSerialization.data(withJSONObject: object).write(to: candidateURL, options: .atomic)

        let reloaded = try await repo.loadCandidate(candidateID: candidate.id, for: source.id)
        #expect(reloaded.authoringOrigin == .externalAuthoring)
    }

    @Test func legacyCapabilityReceiptRequiresANewTest() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        let run = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repo.recordCandidateTest(run, succeeded: true)
        let receiptURL = repo.packageURL(for: source.id).appendingPathComponent("reconstruction/test-\(candidate.id.uuidString).json")
        var receipt = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
        #expect(receipt["capabilityVersion"] as? String == MacroCandidateCapabilities.current.version)
        receipt["capabilityVersion"] = "macro-candidate/v3"
        try JSONSerialization.data(withJSONObject: receipt).write(to: receiptURL, options: .atomic)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
    }

    @Test func staleSourceAndFailedRetestBlockAcceptance() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        let run = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repo.recordCandidateTest(run, succeeded: true)
        let retry = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repo.recordCandidateTest(retry, succeeded: false)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
        try await repo.saveEvents([event(2)], for: source.id)
        await #expect(throws: MacroCandidateStoreError.staleSource) {
            try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        }
    }

    @Test func publicationFailureLeavesRecoverableWholeRevisionAndEditsStayVisible() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let candidate = try await repo.importCandidate(document, for: source.id)
        let run = try await repo.prepareCandidateTest(candidateID: candidate.id, for: source.id)
        try await repo.recordCandidateTest(run, succeeded: true)
        await repo.setCandidatePublicationFault(.beforePointer)
        await #expect(throws: MacroCandidateStoreError.injectedPublicationFailure) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
        #expect(try await repo.loadEvents(for: source.id) == source.events)
        await repo.setCandidatePublicationFault(.afterPointer)
        await #expect(throws: MacroCandidateStoreError.injectedPublicationFailure) {
            try await repo.acceptCandidate(candidateID: candidate.id, for: source.id)
        }
        let restarted = MacroRepository(appSupportURL: root)
        #expect(try await restarted.loadEvents(for: source.id) == document.macro.events)
        var metadata = try await restarted.loadMacro(for: source.id)
        metadata.notes = "After accept"
        metadata.speed = 2
        try await restarted.saveMetadata(metadata)
        try await restarted.saveEvents([event(3)], for: source.id)
        #expect(try await restarted.loadEvents(for: source.id) == [event(3)])
        let manifest = try #require(try await restarted.loadAllManifests().first)
        #expect(manifest.notes == "After accept")
        #expect(manifest.speed == 2)
        #expect(manifest.duration == 3)
        #expect(manifest.events.isEmpty)
        #expect(try await restarted.restoreOriginal(for: source.id).events == source.events)
    }
}

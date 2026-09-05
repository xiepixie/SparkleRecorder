import AppKit
import SwiftUI
import Foundation
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

    @Test func failureAndCandidateChangeCannotReuseSuccessfulUIReceipt() async throws {
        let (root, repo, source, document) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        var shouldFail = false
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in if shouldFail { throw CancellationError() } }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        await model.importDocument(document)
        try #require(model.selectedCandidate != nil, Comment(rawValue: model.errorMessage ?? "No candidate"))
        await model.testSelected()
        #expect(model.canAccept)
        shouldFail = true
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
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let model = MacroReconstructionReviewModel(macroID: source.id, repository: repo,
            testMacro: { _ in }, stopTest: {}, onRevision: { _ in })
        await model.reload(loadEvidence: false)
        var document = originalDocument
        document.summary = "Keep the demonstrated pointer movement. No additional actions or waits are introduced."
        document.model = "Local review fixture"
        await model.importDocument(document)
        _ = NSApplication.shared
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
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent("reconstruction-review.png"))
    }

}

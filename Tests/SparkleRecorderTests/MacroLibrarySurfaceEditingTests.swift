import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

private actor MacroSurfacePersistenceProbe {
    private var saved: [SavedMacro] = []
    func record(_ macro: SavedMacro) { saved.append(macro) }
    func last() -> SavedMacro? { saved.last }
}

@Suite("Macro library surface editing") @MainActor
struct MacroLibrarySurfaceEditingTests {
    private func client(source: SavedMacro, probe: MacroSurfacePersistenceProbe) -> MacroRepositoryClient {
        MacroRepositoryClient(
            loadAllManifests: { [source] },
            loadEvents: { _ in source.events },
            saveMetadata: { macro in await probe.record(macro) },
            saveEvents: { _, _ in },
            deleteMacro: { _ in },
            packageURL: { _ in FileManager.default.temporaryDirectory },
            saveRunEvidence: { _, _, _ in }
        )
    }

    @Test("Accepted Macro editor rebinds one surface without collapsing the surface set")
    func rebindPreservesOtherSurfaces() async throws {
        let first = TestFixtures.surface(appName: "First")
        let second = TestFixtures.surface(appName: "Second")
        let rebound = TestFixtures.surface(appName: "Second rebound")
        var events = TestFixtures.clickPair() + TestFixtures.clickPair(downTime: 0.2, upTime: 0.25)
        events[0].surfaceId = "surface-1"
        events[1].surfaceId = "surface-1"
        events[2].surfaceId = "surface-2"
        events[3].surfaceId = "surface-2"
        var source = SavedMacro(
            name: "Multi surface",
            events: events,
            surfaces: ["surface-1": first, "surface-2": second]
        )
        source.refreshCachesFromEvents()
        let probe = MacroSurfacePersistenceProbe()
        let library = MacroLibrary(client: client(source: source, probe: probe))
        await library.load()
        library.updateEvents(id: source.id, events: events)

        #expect(library.rebindSurface(id: source.id, surfaceID: "surface-2", surface: rebound))
        #expect(library.currentMacro?.surfaces["surface-1"] == first)
        #expect(library.currentMacro?.surfaces["surface-2"] == rebound)
        #expect(!library.removeSurface(id: source.id, surfaceID: "surface-1"))

        await library.flushPendingPersistence(for: source.id)
        #expect(await probe.last()?.surfaces["surface-1"] == first)
        #expect(await probe.last()?.surfaces["surface-2"] == rebound)
    }

    @Test("Manifest-only state never treats missing loaded events as an unused surface")
    func unloadedManifestFailsClosedOnRemoval() async {
        var source = SavedMacro(
            name: "Manifest only",
            events: [],
            surfaces: ["surface-1": TestFixtures.surface(appName: "Bound")]
        )
        source.cachedEventCount = 2
        let probe = MacroSurfacePersistenceProbe()
        let library = MacroLibrary(client: client(source: source, probe: probe))
        await library.load()

        #expect(!library.removeSurface(id: source.id, surfaceID: "surface-1"))
        #expect(library.currentMacro?.surfaces["surface-1"] != nil)
    }
}

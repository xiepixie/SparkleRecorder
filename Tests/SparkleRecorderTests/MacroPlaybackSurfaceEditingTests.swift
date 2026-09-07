import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro playback surface editing")
struct MacroPlaybackSurfaceEditingTests {
    @Test("Rebinding one surface preserves all other surface identities")
    func rebindIsPerSurface() throws {
        let first = TestFixtures.surface(appName: "One", bundleIdentifier: "app.one", windowTitle: "One")
        let second = TestFixtures.surface(appName: "Two", bundleIdentifier: "app.two", windowTitle: "Two")
        let rebound = TestFixtures.surface(appName: "Two New", bundleIdentifier: "app.two", windowTitle: "Two New")
        let surfaces = ["surface-1": first, "surface-2": second]

        let result = try MacroPlaybackSurfaceEditing.rebind(
            surfaceID: "surface-2",
            to: rebound,
            in: surfaces
        )

        #expect(result["surface-1"] == first)
        #expect(result["surface-2"] == rebound)
        #expect(result.count == 2)
    }

    @Test("Referenced surfaces cannot be removed until actions are reassigned")
    func referencedSurfaceRemovalFailsClosed() throws {
        var events = TestFixtures.clickPair()
        events.indices.forEach { events[$0].surfaceId = "surface-2" }
        let surfaces = [
            "surface-1": TestFixtures.surface(appName: "One"),
            "surface-2": TestFixtures.surface(appName: "Two")
        ]

        #expect(throws: MacroPlaybackSurfaceEditingError.surfaceStillReferenced(surfaceID: "surface-2", eventCount: 2)) {
            try MacroPlaybackSurfaceEditing.remove(
                surfaceID: "surface-2",
                from: surfaces,
                events: events
            )
        }
    }

    @Test("Explicit action reassignment makes an unused surface removable")
    func assignThenRemove() throws {
        var events = TestFixtures.clickPair()
        events.indices.forEach { events[$0].surfaceId = "surface-1" }
        let first = TestFixtures.surface(appName: "One")
        let second = TestFixtures.surface(appName: "Two")
        let surfaces = ["surface-1": first, "surface-2": second]

        let reassigned = try MacroPlaybackSurfaceEditing.assign(
            surfaceID: "surface-2",
            toEventIndices: events.indices,
            in: events,
            surfaces: surfaces
        )
        let result = try MacroPlaybackSurfaceEditing.remove(
            surfaceID: "surface-1",
            from: surfaces,
            events: reassigned
        )

        #expect(reassigned.allSatisfy { $0.surfaceId == "surface-2" })
        #expect(result == ["surface-2": second])
    }

    @Test("Adding surfaces allocates a stable unused surface ID without touching existing entries")
    func addUsesStableID() {
        let first = TestFixtures.surface(appName: "One")
        let third = TestFixtures.surface(appName: "Three")
        let added = TestFixtures.surface(appName: "Added")
        let surfaces = ["surface-1": first, "surface-3": third]

        let result = MacroPlaybackSurfaceEditing.add(added, to: surfaces)

        #expect(result.surfaceID == "surface-2")
        #expect(result.surfaces["surface-1"] == first)
        #expect(result.surfaces["surface-2"] == added)
        #expect(result.surfaces["surface-3"] == third)
    }

    @Test("Effective editor surface never guesses in a multi-surface Macro")
    func effectiveSurfaceIsUniqueOrExplicit() throws {
        let surface = TestFixtures.surface()
        let surfaces = ["surface-1": surface, "surface-2": surface]
        var events = TestFixtures.clickPair()

        #expect(try MacroPlaybackSurfaceEditing.effectiveSurfaceID(
            in: events,
            eventIndices: events.indices,
            surfaces: surfaces
        ) == nil)

        events.indices.forEach { events[$0].surfaceId = "surface-2" }
        #expect(try MacroPlaybackSurfaceEditing.effectiveSurfaceID(
            in: events,
            eventIndices: events.indices,
            surfaces: surfaces
        ) == "surface-2")

        events.indices.forEach { events[$0].surfaceId = nil }
        #expect(try MacroPlaybackSurfaceEditing.effectiveSurfaceID(
            in: events,
            eventIndices: events.indices,
            surfaces: ["surface-1": surface]
        ) == "surface-1")
    }

    @Test("Surface ordering keeps numeric surface IDs intuitive")
    func numericOrdering() {
        let surface = TestFixtures.surface()
        let surfaces = [
            "other": surface,
            "surface-10": surface,
            "surface-2": surface,
            "surface-1": surface
        ]
        #expect(MacroPlaybackSurfaceEditing.orderedSurfaceIDs(surfaces) == [
            "surface-1", "surface-2", "surface-10", "other"
        ])
    }
}

import Testing
@testable import SparkleRecorderCore

@Suite("Surface Matcher Tests")
struct SurfaceMatcherTests {
    @Test("Moved window with same title keeps the same surface id")
    func movedWindowWithSameTitleKeepsSameSurfaceId() {
        let matcher = SurfaceMatcher()
        let original = TestFixtures.surface(
            bundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Notes.txt",
            recordedFrame: RectValue(x: 100, y: 100, width: 640, height: 480)
        )
        let moved = TestFixtures.surface(
            bundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Notes.txt",
            recordedFrame: RectValue(x: 840, y: 420, width: 640, height: 480)
        )

        let matchedId = matcher.match(moved, against: ["surface-1": original])

        #expect(matchedId == "surface-1")
    }

    @Test("Registry updates frame instead of allocating when window moves")
    func registryUpdatesFrameInsteadOfAllocatingWhenWindowMoves() throws {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        let original = TestFixtures.surface(
            bundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Notes.txt",
            recordedFrame: RectValue(x: 100, y: 100, width: 640, height: 480)
        )
        let moved = TestFixtures.surface(
            bundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Notes.txt",
            recordedFrame: RectValue(x: 840, y: 420, width: 640, height: 480)
        )

        #expect(registry.update(eventKind: .mouseMoved, trackedActiveSurface: original, surfaceMatcher: matcher) == "surface-1")
        #expect(registry.update(eventKind: .mouseMoved, trackedActiveSurface: moved, surfaceMatcher: matcher) == "surface-1")

        let stored = try #require(registry.activeSurfaces["surface-1"])
        #expect(stored.recordedFrame == moved.recordedFrame)
        #expect(registry.activeSurfaces.count == 1)
    }

    @Test("Single known app window allows title drift")
    func singleKnownAppWindowAllowsTitleDrift() {
        let matcher = SurfaceMatcher()
        let original = TestFixtures.surface(
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Loading...",
            recordedFrame: RectValue(x: 100, y: 100, width: 900, height: 700)
        )
        let renamed = TestFixtures.surface(
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Example Domain",
            recordedFrame: RectValue(x: 120, y: 130, width: 900, height: 700)
        )

        let matchedId = matcher.match(renamed, against: ["surface-1": original])

        #expect(matchedId == "surface-1")
    }

    @Test("Multiple same app windows require title identity")
    func multipleSameAppWindowsRequireTitleIdentity() {
        let matcher = SurfaceMatcher()
        let surfaces = [
            "surface-1": TestFixtures.surface(
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Inbox",
                recordedFrame: RectValue(x: 100, y: 100, width: 900, height: 700)
            ),
            "surface-2": TestFixtures.surface(
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Docs",
                recordedFrame: RectValue(x: 1120, y: 100, width: 900, height: 700)
            )
        ]
        let renamed = TestFixtures.surface(
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Calendar",
            recordedFrame: RectValue(x: 130, y: 120, width: 900, height: 700)
        )

        let matchedId = matcher.match(renamed, against: surfaces)

        #expect(matchedId == nil)
    }

    @Test("Duplicate titles choose closest surface deterministically")
    func duplicateTitlesChooseClosestSurfaceDeterministically() {
        let matcher = SurfaceMatcher()
        let surfaces = [
            "surface-1": TestFixtures.surface(
                bundleIdentifier: "com.example.Editor",
                windowTitle: "Untitled",
                recordedFrame: RectValue(x: 100, y: 100, width: 700, height: 500)
            ),
            "surface-2": TestFixtures.surface(
                bundleIdentifier: "com.example.Editor",
                windowTitle: "Untitled",
                recordedFrame: RectValue(x: 900, y: 100, width: 700, height: 500)
            )
        ]
        let movedNearSecond = TestFixtures.surface(
            bundleIdentifier: "com.example.Editor",
            windowTitle: "Untitled",
            recordedFrame: RectValue(x: 920, y: 130, width: 700, height: 500)
        )

        let matches = matcher.scoredMatches(for: movedNearSecond, against: surfaces)

        #expect(matches.first?.id == "surface-2")
        #expect(matches.map(\.id) == ["surface-2", "surface-1"])
    }
}

import Testing
@testable import SparkleRecorderCore

@Suite("Playback Context Refresher Tests")
struct PlaybackContextRefresherTests {
    @Test("Full refresh replaces stale frame caches")
    func fullRefreshReplacesStaleFrameCaches() {
        let surface = TestFixtures.surface()
        var context = PlaybackContext(
            surfaces: [
                TestFixtures.surfaceId: surface,
                "stale": TestFixtures.surface()
            ],
            currentSurfaceFrames: [
                "stale": RectValue(x: 1, y: 1, width: 10, height: 10)
            ],
            currentContentFrames: [
                "stale": RectValue(x: 1, y: 3, width: 10, height: 8)
            ],
            currentTitleBarHeights: ["stale": 2]
        )

        PlaybackContextRefresher.refresh(
            &context,
            with: [
                TestFixtures.surfaceId: PlaybackSurfaceFrameResolution(
                    outerFrame: RectValue(x: 200, y: 300, width: 900, height: 700),
                    contentFrame: RectValue(x: 200, y: 336, width: 900, height: 664)
                )
            ]
        )

        #expect(context.currentSurfaceFrames[TestFixtures.surfaceId] == RectValue(x: 200, y: 300, width: 900, height: 700))
        #expect(context.currentContentFrames[TestFixtures.surfaceId] == RectValue(x: 200, y: 336, width: 900, height: 664))
        #expect(context.currentTitleBarHeights[TestFixtures.surfaceId] == 36)
        #expect(context.currentSurfaceFrames["stale"] == nil)
        #expect(context.currentContentFrames["stale"] == nil)
        #expect(context.currentTitleBarHeights["stale"] == nil)
    }

    @Test("Lazy refresh preserves existing surfaces and ignores unknown ids")
    func lazyRefreshPreservesExistingSurfaces() {
        let secondaryId = "secondary"
        var context = PlaybackContext(
            surfaces: [
                TestFixtures.surfaceId: TestFixtures.surface(),
                secondaryId: TestFixtures.surface(windowTitle: "Secondary")
            ],
            currentSurfaceFrames: [
                TestFixtures.surfaceId: RectValue(x: 100, y: 100, width: 800, height: 600)
            ],
            currentContentFrames: [
                TestFixtures.surfaceId: RectValue(x: 100, y: 128, width: 800, height: 572)
            ],
            currentTitleBarHeights: [TestFixtures.surfaceId: 28]
        )

        PlaybackContextRefresher.refresh(
            &context,
            with: [
                secondaryId: PlaybackSurfaceFrameResolution(
                    outerFrame: RectValue(x: 500, y: 100, width: 640, height: 480),
                    contentFrame: RectValue(x: 500, y: 124, width: 640, height: 456)
                ),
                "missing": PlaybackSurfaceFrameResolution(
                    outerFrame: RectValue(x: 0, y: 0, width: 1, height: 1),
                    contentFrame: RectValue(x: 0, y: 0, width: 1, height: 1)
                )
            ],
            resetExisting: false
        )

        #expect(context.currentSurfaceFrames[TestFixtures.surfaceId] == RectValue(x: 100, y: 100, width: 800, height: 600))
        #expect(context.currentSurfaceFrames[secondaryId] == RectValue(x: 500, y: 100, width: 640, height: 480))
        #expect(context.currentContentFrames[secondaryId] == RectValue(x: 500, y: 124, width: 640, height: 456))
        #expect(context.currentTitleBarHeights[secondaryId] == 24)
        #expect(context.currentSurfaceFrames["missing"] == nil)
    }
}

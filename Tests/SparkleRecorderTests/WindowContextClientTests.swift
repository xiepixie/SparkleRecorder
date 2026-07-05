import Testing
@testable import SparkleRecorderCore

@Suite("Window Context Client Tests")
struct WindowContextClientTests {
    @Test("Fake client refreshes context without system window APIs")
    func fakeClientRefreshesContext() {
        let surface = TestFixtures.surface()
        var context = PlaybackContext(
            surfaces: [TestFixtures.surfaceId: surface],
            currentSurfaceFrames: ["stale": RectValue(x: 0, y: 0, width: 10, height: 10)]
        )
        let client = WindowContextClient(
            resolveFrameResolutions: { surfaces in
                guard surfaces[TestFixtures.surfaceId] != nil else { return [:] }
                return [
                    TestFixtures.surfaceId: PlaybackSurfaceFrameResolution(
                        outerFrame: RectValue(x: 240, y: 180, width: 960, height: 640),
                        contentFrame: RectValue(x: 240, y: 212, width: 960, height: 608)
                    )
                ]
            },
            activateSurface: { _ in }
        )

        let resolved = client.refreshResolvedFrames(in: &context)

        #expect(resolved == [TestFixtures.surfaceId])
        #expect(context.currentSurfaceFrames[TestFixtures.surfaceId] == RectValue(x: 240, y: 180, width: 960, height: 640))
        #expect(context.currentContentFrames[TestFixtures.surfaceId] == RectValue(x: 240, y: 212, width: 960, height: 608))
        #expect(context.currentTitleBarHeights[TestFixtures.surfaceId] == 32)
        #expect(context.currentSurfaceFrames["stale"] == nil)
    }

    @Test("None client resets cached frames and resolves nothing")
    func noneClientResetsCachedFrames() {
        var context = TestFixtures.playbackContext()

        let resolved = WindowContextClient.none.refreshResolvedFrames(in: &context)

        #expect(resolved.isEmpty)
        #expect(context.currentSurfaceFrames.isEmpty)
        #expect(context.currentContentFrames.isEmpty)
        #expect(context.currentTitleBarHeights.isEmpty)
    }

    @Test("Client lazy refresh can target one surface")
    func lazyRefreshTargetsOneSurface() {
        let secondaryId = "secondary"
        var context = PlaybackContext(
            surfaces: [
                TestFixtures.surfaceId: TestFixtures.surface(),
                secondaryId: TestFixtures.surface(windowTitle: "Secondary")
            ],
            currentSurfaceFrames: [
                TestFixtures.surfaceId: RectValue(x: 100, y: 100, width: 800, height: 600)
            ]
        )
        let client = WindowContextClient(
            resolveFrameResolutions: { surfaces in
                guard surfaces[secondaryId] != nil else { return [:] }
                return [
                    secondaryId: PlaybackSurfaceFrameResolution(
                        outerFrame: RectValue(x: 520, y: 120, width: 700, height: 500),
                        contentFrame: RectValue(x: 520, y: 148, width: 700, height: 472)
                    )
                ]
            },
            activateSurface: { _ in }
        )

        let resolved = client.refreshResolvedFrames(
            in: &context,
            surfaces: [secondaryId: context.surfaces[secondaryId]!],
            resetExisting: false
        )

        #expect(resolved == [secondaryId])
        #expect(context.currentSurfaceFrames[TestFixtures.surfaceId] == RectValue(x: 100, y: 100, width: 800, height: 600))
        #expect(context.currentSurfaceFrames[secondaryId] == RectValue(x: 520, y: 120, width: 700, height: 500))
    }
}

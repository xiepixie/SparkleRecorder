import Testing
@testable import SparkleRecorderCore

@Suite("Playback locator fallback")
struct PlaybackLocatorFallbackTests {
    @Test("Content-normalized fallback follows the current content frame")
    func normalizedFallbackUsesCurrentContentFrame() throws {
        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.surfaceId = "main"
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .locatorOnly
        event.textAnchor = TextAnchor(
            text: "Target",
            observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10),
            coordinateFallbackContentNormalized: PointValue(x: 0.5, y: 0.5)
        )
        let context = PlaybackContext(
            surfaces: ["main": TestFixtures.surface(recordedFrame: RectValue(x: 0, y: 0, width: 400, height: 300))],
            currentSurfaceFrames: ["main": RectValue(x: 100, y: 80, width: 400, height: 320)],
            currentContentFrames: ["main": RectValue(x: 100, y: 120, width: 400, height: 280)]
        )

        let point = try PlaybackLocatorFallback.resolve(
            event: event,
            surfaceId: "main",
            context: context
        ).get()

        #expect(point.x == 300)
        #expect(point.y == 260)
    }

    @Test("Unchanged window rejects a mismatched normalized fallback from text picking")
    func unchangedWindowRejectsMismatchedNormalizedFallback() throws {
        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.surfaceId = "main"
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .locatorOnly
        event.textAnchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(
                x: 17.81149231939898,
                y: 194.67545492616694,
                width: 89.88864550514828,
                height: 19.126630217655354
            ),
            searchRegion: RectValue(
                x: 0,
                y: 114.67545492616694,
                width: 227.70013782454723,
                height: 179.12663021765536
            ),
            coordinateFallback: PointValue(
                x: 62.75581507197312,
                y: 204.23877003499462
            ),
            observedContentNormalizedFrame: RectValue(
                x: 0.008663177198151255,
                y: 0.10116914019506096,
                width: 0.04372015831962465,
                height: 0.015155808413356064
            ),
            searchContentNormalizedRegion: RectValue(
                x: 0,
                y: 0.03777769803975193,
                width: 0.1107490942726397,
                height: 0.14193869272397414
            ),
            coordinateFallbackContentNormalized: PointValue(
                x: 0.030523256357963578,
                y: 0.108747044401739
            )
        )
        let window = RectValue(x: 0, y: 39, width: 2056, height: 1290)
        let surface = TestFixtures.surface(recordedFrame: window)
        let context = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": window],
            currentContentFrames: ["main": window]
        )

        let point = try PlaybackLocatorFallback.resolve(
            event: event,
            surfaceId: "main",
            context: context
        ).get()

        #expect(abs(point.x - 62.75581507197312) < 0.0001)
        #expect(abs(point.y - 204.23877003499462) < 0.0001)
    }

    @Test("Invalid explicit fallback does not bypass ordinary point resolution")
    func invalidExplicitFallbackUsesPointResolver() throws {
        var event = RecordedEvent.make(.leftMouseDown, time: 0, x: 150, y: 180)
        event.surfaceId = "main"
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .normalizedPreferred
        event.contentNormalizedX = 0.25
        event.contentNormalizedY = 0.5
        event.textAnchor = TextAnchor(
            text: "Target",
            observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10),
            coordinateFallback: PointValue(x: 10_000, y: 10_000)
        )
        let surface = TestFixtures.surface(recordedFrame: RectValue(x: 0, y: 0, width: 400, height: 300))
        let context = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": RectValue(x: 100, y: 80, width: 400, height: 320)],
            currentContentFrames: ["main": RectValue(x: 100, y: 120, width: 400, height: 280)]
        )

        let point = try PlaybackLocatorFallback.resolve(
            event: event,
            surfaceId: "main",
            context: context
        ).get()

        #expect(point.x == 200)
        #expect(point.y == 260)
    }
}

import Testing
@testable import SparkleRecorderCore

@Suite("Point resolver geometry fallback")
struct PointResolverGeometryFallbackTests {
    @Test("Full-window content geometry round-trips recorded Chrome coordinates without vertical drift")
    func fullWindowContentGeometryHasNoVerticalDrift() throws {
        let frame = RectValue(x: 0, y: 39, width: 2056, height: 1290)
        let surface = PlaybackSurface(
            bundleIdentifier: "com.google.Chrome",
            recordedFrame: frame,
            recordedContentFrame: frame,
            contentElementRole: "AXGroup"
        )
        let context = PlaybackContext(
            surfaces: ["surface-1": surface],
            currentSurfaceFrames: ["surface-1": frame],
            currentContentFrames: ["surface-1": frame],
            currentTitleBarHeights: ["surface-1": 0]
        )
        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.x = 995.1328125
        event.y = 673.5
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .normalizedPreferred
        event.surfaceId = "surface-1"
        event.windowNormalizedX = 0.4840140138618677
        event.windowNormalizedY = 0.49186046511627907
        event.contentNormalizedX = 0.4840140138618677
        event.contentNormalizedY = 0.49186046511627907

        let point = try PointResolver().resolve(event, context: context).get()

        #expect(abs(point.x - event.x) < 0.000_001)
        #expect(abs(point.y - event.y) < 0.000_001)
    }

    @Test("Window-local playback reuses recorded content inset when live content metadata is missing")
    func recordedContentInsetIsStableFallback() throws {
        let surface = PlaybackSurface(
            recordedFrame: RectValue(x: 100, y: 100, width: 800, height: 600),
            recordedContentFrame: RectValue(x: 100, y: 130, width: 800, height: 570)
        )
        let context = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": RectValue(x: 300, y: 200, width: 900, height: 700)]
        )
        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .windowLocalPreferred
        event.surfaceId = "main"
        event.windowLocalX = 20
        event.windowLocalY = 40

        let point = try PointResolver().resolve(event, context: context).get()

        #expect(point.x == 320)
        #expect(point.y == 270)
    }

    @Test("Fullscreen surface source keeps zero title-bar fallback without AppKit lookup")
    func fullscreenFallbackUsesZeroInset() throws {
        let surface = PlaybackSurface(
            recordedFrame: RectValue(x: 0, y: 0, width: 1200, height: 800),
            contentFrameSource: CoordinateMapper.ResolvedContentFrame.Source.fallbackOuterFrame.rawValue
        )
        let context = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": RectValue(x: 200, y: 100, width: 1200, height: 800)]
        )
        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .windowLocalPreferred
        event.surfaceId = "main"
        event.windowLocalX = 50
        event.windowLocalY = 60

        let point = try PointResolver().resolve(event, context: context).get()

        #expect(point.x == 250)
        #expect(point.y == 160)
    }
}

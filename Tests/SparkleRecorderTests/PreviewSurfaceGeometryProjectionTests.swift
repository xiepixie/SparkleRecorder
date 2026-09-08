import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Preview Surface Geometry Projection Tests")
struct PreviewSurfaceGeometryProjectionTests {
    @Test("Unavailable Playback Surface is fitted into the preview canvas center")
    func unavailableSurfaceUsesCenteredPreviewFrame() {
        let recordedWindow = RectValue(x: 120, y: 80, width: 1200, height: 900)
        let recordedContent = RectValue(x: 120, y: 108, width: 1200, height: 872)
        let canvas = RectValue(x: 0, y: 0, width: 1440, height: 900)

        let projection = PreviewSurfaceGeometryProjection.centered(
            recordedWindowFrame: recordedWindow,
            recordedContentFrame: recordedContent,
            in: canvas
        )

        #expect(abs(projection.windowFrame.x - 312) < 0.0001)
        #expect(abs(projection.windowFrame.y - 144) < 0.0001)
        #expect(abs(projection.windowFrame.width - 816) < 0.0001)
        #expect(abs(projection.windowFrame.height - 612) < 0.0001)
        #expect(abs(projection.contentFrame.y - 163.04) < 0.0001)
        #expect(abs(projection.contentFrame.height - 592.96) < 0.0001)
    }

    @Test("Unavailable Playback Surface gives ordinary coordinate actions a simulated preview context")
    func unavailableSurfaceProjectsOrdinaryCoordinateAction() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            recordedFrame: RectValue(x: 100, y: 80, width: 1000, height: 700),
            recordedContentFrame: RectValue(x: 100, y: 108, width: 1000, height: 672)
        )
        let liveContext = PlaybackContext(
            surfaces: ["main": surface],
            coordinateMode: .boundWindowOffset
        )
        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 1,
            x: 350,
            y: 310,
            mouseButton: 0,
            clickCount: 1
        )
        click.surfaceId = "main"
        click.coordinateBinding = .targetWindow
        click.coordinateStrategy = .normalizedPreferred
        click.contentNormalizedX = 0.25
        click.contentNormalizedY = 0.30

        let resolver = PointResolver()
        guard case .failure(.missingWindowFrame("main")) = resolver.resolve(click, context: liveContext) else {
            Issue.record("The live-only context should reproduce the missing ordinary-click preview")
            return
        }

        let projection = PreviewSurfaceGeometryProjection.fillingUnavailableSurfaces(
            in: liveContext,
            canvas: RectValue(x: 0, y: 0, width: 1400, height: 900)
        )
        let simulated = try #require(projection.simulatedSurfaces["main"])
        let resolved = try resolver.resolve(click, context: projection.context).get()

        #expect(abs(resolved.x - (simulated.contentFrame.x + simulated.contentFrame.width * 0.25)) < 0.000_001)
        #expect(abs(resolved.y - (simulated.contentFrame.y + simulated.contentFrame.height * 0.30)) < 0.000_001)
        #expect(simulated.windowFrame.cgRect.contains(resolved))
    }

    @Test("Legacy unbound coordinate action with a known surface follows the simulated window")
    func legacyUnboundCoordinateActionUsesSimulatedKnownSurface() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            recordedFrame: RectValue(x: 900, y: 500, width: 1000, height: 700),
            recordedContentFrame: RectValue(x: 900, y: 528, width: 1000, height: 672)
        )
        let liveContext = PlaybackContext(
            surfaces: ["main": surface],
            coordinateMode: .boundWindowOffset
        )
        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 1,
            x: 1650,
            y: 1000,
            mouseButton: 0,
            clickCount: 1
        )
        click.surfaceId = "main"
        click.coordinateBinding = nil

        let projection = PreviewSurfaceGeometryProjection.fillingUnavailableSurfaces(
            in: liveContext,
            canvas: RectValue(x: 0, y: 0, width: 1400, height: 900)
        )
        let simulated = try #require(projection.simulatedSurfaces["main"])
        let resolver = PointResolver()

        let liveOnly = try resolver.resolve(click, context: liveContext).get()
        let simulatedPoint = try resolver.resolve(click, context: projection.context).get()

        #expect(liveOnly == CGPoint(x: 1650, y: 1000))
        #expect(simulated.windowFrame.cgRect.contains(simulatedPoint))
        #expect(simulatedPoint != liveOnly)
    }

    @Test("Global-screen coordinate action ignores simulated Playback Surface geometry")
    func globalScreenActionIgnoresSimulatedSurface() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            recordedFrame: RectValue(x: 900, y: 500, width: 1000, height: 700),
            recordedContentFrame: RectValue(x: 900, y: 528, width: 1000, height: 672)
        )
        let context = PlaybackContext(
            surfaces: ["main": surface],
            coordinateMode: .boundWindowOffset
        )
        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 1,
            x: 120,
            y: 140,
            mouseButton: 0,
            clickCount: 1
        )
        click.surfaceId = "main"
        click.coordinateBinding = .globalScreen

        let projection = PreviewSurfaceGeometryProjection.fillingUnavailableSurfaces(
            in: context,
            canvas: RectValue(x: 0, y: 0, width: 1400, height: 900)
        )
        let resolved = try PointResolver().resolve(click, context: projection.context).get()

        #expect(resolved == CGPoint(x: 120, y: 140))
    }

    @Test("Available Playback Surface is never replaced by simulated preview geometry")
    func availableSurfaceRemainsLiveInPreviewContext() throws {
        let surface = PlaybackSurface(
            appName: "Example",
            recordedFrame: RectValue(x: 100, y: 80, width: 1000, height: 700),
            recordedContentFrame: RectValue(x: 100, y: 108, width: 1000, height: 672)
        )
        let liveFrame = RectValue(x: 420, y: 160, width: 900, height: 640)
        let liveContent = RectValue(x: 420, y: 188, width: 900, height: 612)
        let liveContext = PlaybackContext(
            surfaces: ["main": surface],
            currentSurfaceFrames: ["main": liveFrame],
            currentContentFrames: ["main": liveContent],
            coordinateMode: .boundWindowOffset
        )

        let projection = PreviewSurfaceGeometryProjection.fillingUnavailableSurfaces(
            in: liveContext,
            canvas: RectValue(x: 0, y: 0, width: 1400, height: 900)
        )

        #expect(projection.simulatedSurfaces.isEmpty)
        #expect(projection.context.currentSurfaceFrames["main"] == liveFrame)
        #expect(projection.context.currentContentFrames["main"] == liveContent)
    }

    @Test("Unavailable Playback Surface projects both normalized and legacy text geometry into the simulated window")
    func unavailableSurfaceProjectsTextAnchorIntoSimulatedWindow() {
        let recordedWindow = RectValue(x: 100, y: 100, width: 1000, height: 700)
        let recordedContent = RectValue(x: 100, y: 128, width: 1000, height: 672)
        let canvas = RectValue(x: 0, y: 0, width: 1400, height: 900)
        let preview = PreviewSurfaceGeometryProjection.centered(
            recordedWindowFrame: recordedWindow,
            recordedContentFrame: recordedContent,
            in: canvas
        )
        let normalizedAnchor = TextAnchor(
            text: "A long target label that must remain attached to the search condition",
            observedFrame: RectValue(x: 300, y: 260, width: 200, height: 40),
            searchRegion: RectValue(x: 220, y: 210, width: 420, height: 180),
            coordinateFallback: PointValue(x: 400, y: 280),
            observedContentNormalizedFrame: RectValue(x: 0.2, y: 0.2, width: 0.2, height: 0.06),
            searchContentNormalizedRegion: RectValue(x: 0.12, y: 0.12, width: 0.42, height: 0.28),
            coordinateFallbackContentNormalized: PointValue(x: 0.3, y: 0.24)
        )

        let normalized = PreviewSurfaceGeometryProjection.resolveTextAnchor(
            normalizedAnchor,
            recordedWindowFrame: recordedWindow,
            preview: preview
        )
        #expect(normalized.observedFrame != nil)
        #expect(normalized.searchRegion != nil)
        #expect(normalized.coordinateFallback != nil)
        #expect(preview.windowFrame.cgRect.contains(normalized.observedFrame!.cgRect))
        #expect(preview.windowFrame.cgRect.contains(normalized.searchRegion!.cgRect))

        let legacyAnchor = TextAnchor(
            text: "Legacy",
            observedFrame: RectValue(x: 300, y: 260, width: 200, height: 40),
            searchRegion: RectValue(x: 220, y: 210, width: 420, height: 180),
            coordinateFallback: PointValue(x: 400, y: 280)
        )
        let legacy = PreviewSurfaceGeometryProjection.resolveTextAnchor(
            legacyAnchor,
            recordedWindowFrame: recordedWindow,
            preview: preview
        )
        #expect(legacy.observedFrame != legacyAnchor.observedFrame)
        #expect(preview.windowFrame.cgRect.contains(legacy.observedFrame!.cgRect))
        #expect(preview.windowFrame.cgRect.contains(legacy.searchRegion!.cgRect))
    }

    @Test("Simulated coordinate-action drag delta scales back to recorded window geometry")
    func simulatedCoordinateDragDeltaMapsBackToRecordedWindow() {
        let delta = PreviewSurfaceGeometryProjection.recordedDelta(
            dx: 40,
            dy: -24,
            recordedWindowFrame: RectValue(x: 100, y: 80, width: 1200, height: 900),
            previewWindowFrame: RectValue(x: 300, y: 140, width: 800, height: 600)
        )

        #expect(abs(delta.width - 60) < 0.000_001)
        #expect(abs(delta.height + 36) < 0.000_001)
    }

    @Test("Simulated preview edits map back to recorded content geometry")
    func simulatedPreviewEditsMapBackToRecordedContentGeometry() {
        let recordedContent = RectValue(x: 100, y: 120, width: 800, height: 580)
        let previewContent = RectValue(x: 300, y: 240, width: 400, height: 290)
        let previewRect = RectValue(x: 380, y: 327, width: 160, height: 58)
        let previewPoint = PointValue(x: 500, y: 414)

        let rect = PreviewSurfaceGeometryProjection.recordedRect(
            from: previewRect,
            previewContentFrame: previewContent,
            recordedContentFrame: recordedContent
        )
        let point = PreviewSurfaceGeometryProjection.recordedPoint(
            from: previewPoint,
            previewContentFrame: previewContent,
            recordedContentFrame: recordedContent
        )

        #expect(abs(rect.normalized.x - 0.2) < 0.000_001)
        #expect(abs(rect.normalized.y - 0.3) < 0.000_001)
        #expect(abs(rect.normalized.width - 0.4) < 0.000_001)
        #expect(abs(rect.normalized.height - 0.2) < 0.000_001)
        #expect(rect.absolute == RectValue(x: 260, y: 294, width: 320, height: 116))
        #expect(point.normalized == PointValue(x: 0.5, y: 0.6))
        #expect(point.absolute == PointValue(x: 500, y: 468))
    }
}

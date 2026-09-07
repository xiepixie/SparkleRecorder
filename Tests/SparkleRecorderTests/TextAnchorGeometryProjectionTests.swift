import Testing
@testable import SparkleRecorderCore

@Suite("Text anchor geometry projection")
struct TextAnchorGeometryProjectionTests {
    @Test("Content-normalized text geometry follows current content position and size")
    func normalizedGeometryTracksCurrentContentFrame() throws {
        let anchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegion: RectValue(x: 1, y: 2, width: 300, height: 200),
            coordinateFallback: PointValue(x: 25, y: 40),
            observedContentNormalizedFrame: RectValue(x: 0.10, y: 0.20, width: 0.15, height: 0.10),
            searchContentNormalizedRegion: RectValue(x: 0.05, y: 0.10, width: 0.40, height: 0.30),
            coordinateFallbackContentNormalized: PointValue(x: 0.175, y: 0.25)
        )
        let content = RectValue(x: 400, y: 200, width: 1000, height: 800)

        let resolved = TextAnchorGeometryProjection.resolve(anchor, contentFrame: content)

        #expect(resolved.observedFrame == RectValue(x: 500, y: 360, width: 150, height: 80))
        #expect(resolved.searchRegion == RectValue(x: 450, y: 280, width: 400, height: 240))
        #expect(resolved.coordinateFallback == PointValue(x: 575, y: 400))
    }

    @Test("Legacy absolute geometry remains available when no current content frame exists")
    func absoluteGeometryIsCompatibilityFallback() throws {
        let anchor = TextAnchor(
            text: "Ready",
            observedFrame: RectValue(x: 100, y: 120, width: 80, height: 24),
            searchRegion: RectValue(x: 50, y: 80, width: 260, height: 120),
            coordinateFallback: PointValue(x: 140, y: 132),
            observedContentNormalizedFrame: RectValue(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
            searchContentNormalizedRegion: RectValue(x: 0.05, y: 0.05, width: 0.4, height: 0.2),
            coordinateFallbackContentNormalized: PointValue(x: 0.2, y: 0.15)
        )

        let resolved = TextAnchorGeometryProjection.resolve(anchor, contentFrame: nil)

        #expect(resolved.observedFrame == anchor.observedFrame)
        #expect(resolved.searchRegion == anchor.searchRegion)
        #expect(resolved.coordinateFallback == anchor.coordinateFallback)
    }

    @Test("Normalized-only search region resolves without an absolute compatibility region")
    func normalizedOnlySearchRegionResolves() throws {
        let anchor = TextAnchor(
            text: "ChatGPT",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0),
            searchContentNormalizedRegion: RectValue(x: 0, y: 0.05, width: 0.3, height: 0.2)
        )
        let content = RectValue(x: 200, y: 100, width: 1200, height: 900)

        let resolved = TextAnchorGeometryProjection.resolve(anchor, contentFrame: content)

        #expect(resolved.searchRegion == RectValue(x: 200, y: 145, width: 360, height: 180))
    }

    @Test("Normalized-only geometry does not project against a missing content frame")
    func normalizedOnlyGeometryNeedsCurrentContentFrame() throws {
        let anchor = TextAnchor(
            text: "ChatGPT",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0),
            searchContentNormalizedRegion: RectValue(x: 0, y: 0.05, width: 0.3, height: 0.2),
            coordinateFallbackContentNormalized: PointValue(x: 0.15, y: 0.15)
        )

        let resolved = TextAnchorGeometryProjection.resolve(anchor, contentFrame: nil)

        #expect(resolved.searchRegion == nil)
        #expect(resolved.coordinateFallback == nil)
    }

    @Test("Unchanged window falls back to absolute text geometry when normalized geometry was authored against a different content frame")
    func unchangedWindowRejectsMismatchedNormalizedGeometry() throws {
        let anchor = TextAnchor(
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
        let unchangedWindow = RectValue(x: 0, y: 39, width: 2056, height: 1290)
        let liveContent = unchangedWindow

        let resolved = TextAnchorGeometryProjection.resolve(
            anchor,
            contentFrame: liveContent,
            recordedWindowFrame: unchangedWindow,
            currentWindowFrame: unchangedWindow
        )

        #expect(resolved.observedFrame == anchor.observedFrame)
        #expect(resolved.searchRegion == anchor.searchRegion)
        #expect(resolved.coordinateFallback == anchor.coordinateFallback)
    }

    @Test("Moved window keeps content-normalized text geometry authoritative")
    func movedWindowKeepsNormalizedGeometry() throws {
        let anchor = TextAnchor(
            text: "New chat",
            observedFrame: RectValue(x: 20, y: 200, width: 90, height: 20),
            coordinateFallback: PointValue(x: 65, y: 210),
            observedContentNormalizedFrame: RectValue(x: 0.01, y: 0.10, width: 0.05, height: 0.02),
            coordinateFallbackContentNormalized: PointValue(x: 0.03, y: 0.11)
        )
        let recordedWindow = RectValue(x: 0, y: 39, width: 1000, height: 800)
        let currentWindow = RectValue(x: 300, y: 140, width: 1000, height: 800)
        let currentContent = RectValue(x: 300, y: 168, width: 1000, height: 772)

        let resolved = TextAnchorGeometryProjection.resolve(
            anchor,
            contentFrame: currentContent,
            recordedWindowFrame: recordedWindow,
            currentWindowFrame: currentWindow
        )

        #expect(resolved.observedFrame == RectValue(x: 310, y: 245.2, width: 50, height: 15.44))
        #expect(abs((resolved.coordinateFallback?.x ?? 0) - 330) < 0.0001)
        #expect(abs((resolved.coordinateFallback?.y ?? 0) - 252.92) < 0.0001)
    }

    @Test("Empty legacy observed frame stays absent instead of becoming a fake target")
    func emptyObservedFrameIsAbsent() throws {
        let anchor = TextAnchor(
            text: "Loaded",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )

        let resolved = TextAnchorGeometryProjection.resolve(anchor, contentFrame: nil)

        #expect(resolved.observedFrame == nil)
        #expect(resolved.searchRegion == nil)
        #expect(resolved.coordinateFallback == nil)
    }
}

import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Locator Cache Tests")
struct PlaybackLocatorCacheTests {
    @Test("Locator cache key includes text matching geometry and fallback data")
    func locatorCacheKeyIncludesAnchorIdentity() {
        var event = TestFixtures.clickEvent(time: 1.0, surfaceId: TestFixtures.surfaceId)
        event.textAnchor = TextAnchor(
            text: "Submit",
            matchMode: .exact,
            observedFrame: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegion: RectValue(x: 50, y: 60, width: 70, height: 80),
            coordinateFallback: PointValue(x: 90, y: 100)
        )

        let key = PlaybackLocatorCacheKey.key(for: event, surfaceId: TestFixtures.surfaceId)

        #expect(key == "main|Submit|exact|10.0000,20.0000,30.0000,40.0000|50.0000,60.0000,70.0000,80.0000|90.0000,100.0000")
    }

    @Test("Locator cache prefers content-normalized anchor fields")
    func locatorCacheKeyPrefersContentNormalizedFields() {
        var event = TestFixtures.clickEvent(time: 1.0, surfaceId: TestFixtures.surfaceId)
        event.textAnchor = TextAnchor(
            text: "Submit",
            observedFrame: RectValue(x: 10, y: 20, width: 30, height: 40),
            searchRegion: RectValue(x: 50, y: 60, width: 70, height: 80),
            coordinateFallback: PointValue(x: 90, y: 100),
            observedContentNormalizedFrame: RectValue(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            searchContentNormalizedRegion: RectValue(x: 0.5, y: 0.6, width: 0.7, height: 0.8),
            coordinateFallbackContentNormalized: PointValue(x: 0.9, y: 1.0)
        )

        let key = PlaybackLocatorCacheKey.key(for: event, surfaceId: TestFixtures.surfaceId)

        #expect(key == "main|Submit|contains|0.1000,0.2000,0.3000,0.4000|0.5000,0.6000,0.7000,0.8000|0.9000,1.0000")
    }

    @Test("Locator cache only reuses matching entries within same loop and time window")
    func locatorCacheOnlyReusesMatchingEntries() {
        let cache = PlaybackLocatorCache()
        let point = CGPoint(x: 12, y: 34)

        cache.store(point: point, for: "anchor", loopIndex: 1, eventTime: 3.0)

        #expect(cache.point(for: "anchor", loopIndex: 1, eventTime: 3.9) == point)
        #expect(cache.point(for: "anchor", loopIndex: 1, eventTime: 4.1) == nil)
        #expect(cache.point(for: "anchor", loopIndex: 2, eventTime: 3.5) == nil)
        #expect(cache.point(for: "other", loopIndex: 1, eventTime: 3.5) == nil)
        #expect(cache.point(for: nil, loopIndex: 1, eventTime: 3.5) == nil)
    }

    @Test("Locator cache ignores nil keys when storing")
    func locatorCacheIgnoresNilKeyStores() {
        let cache = PlaybackLocatorCache()

        cache.store(point: CGPoint(x: 1, y: 2), for: nil, loopIndex: 1, eventTime: 1)

        #expect(cache.point(for: "anchor", loopIndex: 1, eventTime: 1) == nil)
    }
}

import CoreGraphics
import Testing
@testable import SparkleRecorder

@Suite("Text picker anchor geometry")
struct TextPickerAnchorBuilderTests {
    @Test("Window capture writes content-normalized geometry")
    func windowCaptureWritesContentNormalizedGeometry() throws {
        let contentFrame = CGRect(x: 0, y: 39, width: 2056, height: 1290)
        let observed = CGRect(x: 17.77, y: 193.43, width: 89.98, height: 19.61)
        let search = CGRect(x: 0, y: 155.1, width: 329.75, height: 179.61)
        let fallback = CGPoint(x: observed.midX, y: observed.midY)

        let anchor = TextPickerAnchorBuilder.makeAnchor(
            text: "New chat",
            observedScreenRect: observed,
            searchScreenRect: search,
            fallback: fallback,
            contentFrame: contentFrame
        )

        let normalized = try #require(anchor.observedContentNormalizedFrame)
        #expect(abs(normalized.y - ((observed.minY - contentFrame.minY) / contentFrame.height)) < 0.000_001)
        let fallbackNormalized = try #require(anchor.coordinateFallbackContentNormalized)
        #expect(abs(fallbackNormalized.y - ((fallback.y - contentFrame.minY) / contentFrame.height)) < 0.000_001)
    }

    @Test("Display fallback never masquerades as content-normalized geometry")
    func displayFallbackKeepsOnlyAbsoluteGeometry() {
        let observed = CGRect(x: 17.77, y: 193.43, width: 89.98, height: 19.61)
        let search = CGRect(x: 0, y: 113.38, width: 227.72, height: 179.4)
        let fallback = CGPoint(x: 62.76, y: 203.08)

        let anchor = TextPickerAnchorBuilder.makeAnchor(
            text: "New chat",
            observedScreenRect: observed,
            searchScreenRect: search,
            fallback: fallback,
            contentFrame: nil
        )

        #expect(anchor.observedFrame == .init(observed))
        #expect(anchor.coordinateFallback == .init(fallback))
        #expect(anchor.observedContentNormalizedFrame == nil)
        #expect(anchor.searchContentNormalizedRegion == nil)
        #expect(anchor.coordinateFallbackContentNormalized == nil)
    }
}

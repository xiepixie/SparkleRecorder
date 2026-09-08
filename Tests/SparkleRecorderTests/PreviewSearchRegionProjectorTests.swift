import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Preview Search Region Projector Tests")
struct PreviewSearchRegionProjectorTests {
    private let minimumSize = CGSize(width: 44, height: 30)

    @Test("Moving a search region stays inside Playback Surface bounds")
    func moveClampsToBounds() {
        let adjusted = PreviewSearchRegionProjector.adjusted(
            original: CGRect(x: 100, y: 100, width: 200, height: 100),
            handle: .move,
            translation: CGSize(width: 200, height: 200),
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            minimumSize: minimumSize
        )

        #expect(adjusted == CGRect(x: 200, y: 200, width: 200, height: 100))
    }

    @Test("Corner resize preserves the minimum editable search region")
    func resizePreservesMinimumSize() {
        let adjusted = PreviewSearchRegionProjector.adjusted(
            original: CGRect(x: 100, y: 100, width: 200, height: 100),
            handle: .topLeft,
            translation: CGSize(width: 500, height: 500),
            bounds: nil,
            minimumSize: minimumSize
        )

        #expect(adjusted == CGRect(x: 256, y: 170, width: 44, height: 30))
    }

    @Test("Corner resize cannot extend beyond Playback Surface bounds")
    func resizeClampsToBounds() {
        let adjusted = PreviewSearchRegionProjector.adjusted(
            original: CGRect(x: 100, y: 100, width: 200, height: 100),
            handle: .bottomRight,
            translation: CGSize(width: 500, height: 500),
            bounds: CGRect(x: 0, y: 0, width: 350, height: 260),
            minimumSize: minimumSize
        )

        #expect(adjusted == CGRect(x: 100, y: 100, width: 250, height: 160))
    }

    @Test("A Playback Surface smaller than the normal minimum still produces a valid region")
    func tinyBoundsRemainValid() {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 15)
        let adjusted = PreviewSearchRegionProjector.adjusted(
            original: bounds,
            handle: .bottomRight,
            translation: CGSize(width: -500, height: -500),
            bounds: bounds,
            minimumSize: minimumSize
        )

        #expect(adjusted == bounds)
        #expect(adjusted.width >= 0)
        #expect(adjusted.height >= 0)
    }
}

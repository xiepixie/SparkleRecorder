import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Stats Tests")
struct RecordingStatsTests {
    struct KindCase: Sendable {
        var kind: RecordedEvent.Kind
        var expected: RecordingStats
    }

    @Test(
        "Individual raw event kinds count toward the expected live HUD buckets",
        arguments: [
            KindCase(kind: .leftMouseDown, expected: RecordingStats(clicks: 1)),
            KindCase(kind: .rightMouseDown, expected: RecordingStats(clicks: 1)),
            KindCase(kind: .otherMouseDown, expected: RecordingStats(clicks: 1)),
            KindCase(kind: .leftMouseUp, expected: .zero),
            KindCase(kind: .keyDown, expected: RecordingStats(keys: 1)),
            KindCase(kind: .keyUp, expected: .zero),
            KindCase(kind: .flagsChanged, expected: .zero),
            KindCase(kind: .scrollWheel, expected: RecordingStats(scrolls: 1)),
            KindCase(kind: .leftMouseDragged, expected: RecordingStats(drags: 1)),
            KindCase(kind: .rightMouseDragged, expected: RecordingStats(drags: 1)),
            KindCase(kind: .otherMouseDragged, expected: RecordingStats(drags: 1)),
        ]
    )
    func individualKindsCountExpectedBuckets(_ testCase: KindCase) {
        let event = RecordedEvent.make(testCase.kind, time: 0, x: 10, y: 20)

        #expect(RecordingStats.summarize([event]) == testCase.expected)
    }

    @Test("Stats summarize and merge event batches")
    func statsSummarizeAndMergeEventBatches() {
        let firstBatch = [
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 10, y: 20),
            RecordedEvent.make(.keyDown, time: 0.2, x: 10, y: 20),
            RecordedEvent.make(.scrollWheel, time: 0.3, x: 10, y: 20),
        ]
        let secondBatch = [
            RecordedEvent.make(.leftMouseDragged, time: 0.4, x: 12, y: 22),
            RecordedEvent.make(.rightMouseDown, time: 0.5, x: 12, y: 22),
        ]

        var stats = RecordingStats.summarize(firstBatch)
        stats.merge(RecordingStats.summarize(secondBatch))

        #expect(stats == RecordingStats(clicks: 2, keys: 1, scrolls: 1, drags: 1))
    }
}

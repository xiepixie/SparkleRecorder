import Testing
@testable import SparkleRecorderCore

@Suite("Text anchor match ranking")
struct TextAnchorMatchRankingTests {
    @Test("Exact matching rejects partial OCR text while contains accepts it")
    func exactVersusContains() {
        let candidate = TextAnchorMatchCandidate(
            text: "New chat button",
            normalizedBounds: RectValue(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
            confidence: 0.9
        )
        var anchor = TextAnchor(
            text: "New chat",
            matchMode: .exact,
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        let frame = RectValue(x: 100, y: 200, width: 1_000, height: 500)

        #expect(TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: [candidate],
            detectionFrame: frame,
            observedFrame: nil
        ) == nil)

        anchor.matchMode = .contains
        let match = TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: [candidate],
            detectionFrame: frame,
            observedFrame: nil
        )
        #expect(match?.recognizedText == "New chat button")
        #expect(match?.screenFrame == RectValue(x: 200, y: 300, width: 200, height: 50))
        #expect(match?.center == PointValue(x: 300, y: 325))
    }

    @Test("Observed position can outrank a more confident distant duplicate")
    func observedPositionBreaksDuplicateTie() {
        let anchor = TextAnchor(
            text: "Continue",
            matchMode: .exact,
            observedFrame: RectValue(x: 100, y: 100, width: 120, height: 40)
        )
        let candidates = [
            TextAnchorMatchCandidate(
                text: "Continue",
                normalizedBounds: RectValue(x: 0.1, y: 0.1, width: 0.12, height: 0.04),
                confidence: 0.3
            ),
            TextAnchorMatchCandidate(
                text: "Continue",
                normalizedBounds: RectValue(x: 0.8, y: 0.8, width: 0.12, height: 0.04),
                confidence: 1.0
            )
        ]
        let frame = RectValue(x: 0, y: 0, width: 1_000, height: 1_000)

        let match = TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: candidates,
            detectionFrame: frame,
            observedFrame: anchor.observedFrame
        )

        #expect(match?.screenFrame.x == 100)
        #expect(match?.screenFrame.y == 100)
    }

    @Test("Occurrence hint uses visual top-to-bottom then left-to-right order")
    func occurrenceHintUsesVisualOrder() {
        let candidates = [
            TextAnchorMatchCandidate(text: "Item", normalizedBounds: RectValue(x: 0.7, y: 0.1, width: 0.1, height: 0.05), confidence: 0.9),
            TextAnchorMatchCandidate(text: "Item", normalizedBounds: RectValue(x: 0.2, y: 0.4, width: 0.1, height: 0.05), confidence: 0.9),
            TextAnchorMatchCandidate(text: "Item", normalizedBounds: RectValue(x: 0.1, y: 0.1, width: 0.1, height: 0.05), confidence: 0.9)
        ]
        let frame = RectValue(x: 0, y: 0, width: 1_000, height: 1_000)
        let anchor = TextAnchor(
            text: "Item",
            matchMode: .exact,
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0),
            occurrenceHint: 2
        )

        let match = TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: candidates,
            detectionFrame: frame,
            observedFrame: nil
        )

        #expect(match?.screenFrame.x == 700)
        #expect(match?.screenFrame.y == 100)
    }

    @Test("Contains mode keeps bounded fuzzy OCR tolerance")
    func fuzzyContainsTolerance() {
        let anchor = TextAnchor(
            text: "Settings",
            matchMode: .contains,
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        let frame = RectValue(x: 0, y: 0, width: 100, height: 100)
        let near = TextAnchorMatchCandidate(
            text: "Settinys",
            normalizedBounds: RectValue(x: 0.1, y: 0.1, width: 0.5, height: 0.2),
            confidence: 0.8
        )
        let far = TextAnchorMatchCandidate(
            text: "Unrelated",
            normalizedBounds: RectValue(x: 0.1, y: 0.1, width: 0.5, height: 0.2),
            confidence: 1.0
        )

        #expect(TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: [near],
            detectionFrame: frame,
            observedFrame: nil
        ) != nil)
        #expect(TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: [far],
            detectionFrame: frame,
            observedFrame: nil
        ) == nil)
    }
}

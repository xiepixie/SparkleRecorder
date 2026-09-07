import Foundation

public struct TextAnchorMatchCandidate: Equatable, Sendable {
    public var text: String
    public var normalizedBounds: RectValue
    public var confidence: Double

    public init(text: String, normalizedBounds: RectValue, confidence: Double) {
        self.text = text
        self.normalizedBounds = normalizedBounds
        self.confidence = confidence
    }
}

public struct ResolvedTextAnchorMatch: Equatable, Sendable {
    public var recognizedText: String
    public var screenFrame: RectValue
    public var confidence: Double

    public init(recognizedText: String, screenFrame: RectValue, confidence: Double) {
        self.recognizedText = recognizedText
        self.screenFrame = screenFrame
        self.confidence = confidence
    }

    public var center: PointValue {
        PointValue(
            x: screenFrame.x + screenFrame.width / 2,
            y: screenFrame.y + screenFrame.height / 2
        )
    }
}

/// Pure text-target ranking used after OCR has produced normalized candidates.
/// Matching policy lives in Core so click, wait and verify semantics can be tested
/// without ScreenCaptureKit or Vision.
public enum TextAnchorMatchRanking {
    public static func bestMatch(
        anchor: TextAnchor,
        candidates: [TextAnchorMatchCandidate],
        detectionFrame: RectValue,
        observedFrame: RectValue?
    ) -> ResolvedTextAnchorMatch? {
        let targetText = anchor.text.lowercased()
        guard !targetText.isEmpty else { return nil }

        let observed = observedFrame.flatMap { frame in
            frame.width > 0 && frame.height > 0 ? frame : nil
        }
        let diagonal = max(1, hypot(detectionFrame.width, detectionFrame.height))
        var ranked: [(match: ResolvedTextAnchorMatch, score: Double)] = []

        for candidate in candidates {
            let similarity = similarity(
                candidate: candidate.text.lowercased(),
                target: targetText,
                mode: anchor.matchMode
            )
            guard similarity > 0 else { continue }

            let screenFrame = RectValue(
                x: detectionFrame.x + candidate.normalizedBounds.x * detectionFrame.width,
                y: detectionFrame.y + candidate.normalizedBounds.y * detectionFrame.height,
                width: candidate.normalizedBounds.width * detectionFrame.width,
                height: candidate.normalizedBounds.height * detectionFrame.height
            )

            var distanceScore = 0.5
            if let observed {
                let dx = (screenFrame.x + screenFrame.width / 2) - (observed.x + observed.width / 2)
                let dy = (screenFrame.y + screenFrame.height / 2) - (observed.y + observed.height / 2)
                distanceScore = max(0, 1 - hypot(dx, dy) / diagonal)
            }

            let score = similarity * 0.6
                + distanceScore * 0.3
                + candidate.confidence * 0.1
            ranked.append((
                ResolvedTextAnchorMatch(
                    recognizedText: candidate.text,
                    screenFrame: screenFrame,
                    confidence: candidate.confidence
                ),
                score
            ))
        }

        guard !ranked.isEmpty else { return nil }
        if let hint = anchor.occurrenceHint {
            let positionOrdered = ranked.sorted {
                let lhs = $0.match.screenFrame
                let rhs = $1.match.screenFrame
                if abs(lhs.y - rhs.y) > 4 {
                    return lhs.y < rhs.y
                }
                return lhs.x < rhs.x
            }
            let zeroBased = hint > 0 ? hint - 1 : hint
            if positionOrdered.indices.contains(zeroBased) {
                return positionOrdered[zeroBased].match
            }
        }

        return ranked.max { $0.score < $1.score }?.match
    }

    private static func similarity(candidate: String, target: String, mode: TextMatchMode) -> Double {
        switch mode {
        case .exact:
            return candidate == target ? 1 : 0
        case .contains:
            if candidate.contains(target) {
                return min(1, Double(target.count) / Double(max(target.count, candidate.count)) + 0.4)
            }
            let maximumLength = max(candidate.count, target.count, 1)
            let score = 1 - Double(levenshtein(candidate, target)) / Double(maximumLength)
            return score >= 0.65 ? score : 0
        }
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}

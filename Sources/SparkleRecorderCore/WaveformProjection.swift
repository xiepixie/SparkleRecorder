import Foundation

public struct WaveformBar: Identifiable, Equatable, Codable, Sendable {
    public let id: Int
    public let kind: RecordedEvent.Kind
    public let positionFraction: Double
    public let isImpact: Bool

    public init(id: Int, kind: RecordedEvent.Kind, positionFraction: Double, isImpact: Bool) {
        self.id = id
        self.kind = kind
        self.positionFraction = positionFraction
        self.isImpact = isImpact
    }
}

public enum WaveformProjection {
    public static func indexedBars(from events: [RecordedEvent]) -> [WaveformBar] {
        guard !events.isEmpty else { return [] }
        let count = max(1, events.count)
        return events.enumerated().map { index, event in
            WaveformBar(
                id: index,
                kind: event.kind,
                positionFraction: Double(index) / Double(count),
                isImpact: isImpact(event.kind)
            )
        }
    }

    public static func timedBars(
        from events: [RecordedEvent],
        maxBars: Int,
        duration: TimeInterval? = nil
    ) -> [WaveformBar] {
        guard !events.isEmpty, maxBars > 0 else { return [] }

        let samples = TimelineProjection.sampleEvents(from: events, maxSamples: maxBars)
        let fallbackDuration = events.last?.time ?? 0
        let effectiveDuration = max(duration ?? fallbackDuration, fallbackDuration, 0.000_001)

        return samples.map { sample in
            let fraction = max(0, min(1, sample.event.time / effectiveDuration))
            return WaveformBar(
                id: sample.id,
                kind: sample.event.kind,
                positionFraction: fraction,
                isImpact: isImpact(sample.event.kind)
            )
        }
    }

    public static func isImpact(_ kind: RecordedEvent.Kind) -> Bool {
        switch kind {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return false
        default:
            return true
        }
    }
}

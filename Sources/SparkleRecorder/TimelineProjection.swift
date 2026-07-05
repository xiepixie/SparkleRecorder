import Foundation

public struct TimelineSampledEvent: Identifiable, Equatable, Sendable {
    public let id: Int
    public let event: RecordedEvent

    public init(id: Int, event: RecordedEvent) {
        self.id = id
        self.event = event
    }
}

public enum TimelineProjection {
    public static func sampleEvents(
        from events: [RecordedEvent],
        maxSamples: Int = 800
    ) -> [TimelineSampledEvent] {
        guard !events.isEmpty, maxSamples > 0 else { return [] }
        guard events.count > maxSamples else {
            return events.enumerated().map { TimelineSampledEvent(id: $0.offset, event: $0.element) }
        }
        guard maxSamples > 1 else {
            return [TimelineSampledEvent(id: 0, event: events[0])]
        }

        let step = Double(events.count - 1) / Double(maxSamples - 1)
        return (0..<maxSamples).map { sampleIndex in
            let eventIndex = min(events.count - 1, Int((Double(sampleIndex) * step).rounded(.down)))
            return TimelineSampledEvent(id: eventIndex, event: events[eventIndex])
        }
    }

    public static func selectedTimeRange(
        selection: Set<UUID>,
        groups: [ActionGroup]
    ) -> (start: TimeInterval, end: TimeInterval)? {
        guard !selection.isEmpty else { return nil }

        var start = TimeInterval.greatestFiniteMagnitude
        var end = -TimeInterval.greatestFiniteMagnitude
        var found = false

        for group in groups where selection.contains(group.id) {
            start = min(start, group.startTime)
            end = max(end, group.endTime)
            found = true
        }

        guard found else { return nil }
        return (start, end)
    }

    public static func nearestGroup(
        to time: TimeInterval,
        groups: [ActionGroup]
    ) -> ActionGroup? {
        guard let first = groups.first else { return nil }

        var bestGroup = first
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for group in groups {
            let distance = min(abs(group.startTime - time), abs(group.endTime - time))
            if distance < bestDistance {
                bestDistance = distance
                bestGroup = group
            }
        }

        return bestGroup
    }

    public static func selection(
        dragStartFraction: Double,
        dragEndFraction: Double,
        totalDuration: TimeInterval,
        groups: [ActionGroup]
    ) -> Set<UUID> {
        guard totalDuration > 0 else { return [] }

        let clampedStart = max(0, min(1, dragStartFraction))
        let clampedEnd = max(0, min(1, dragEndFraction))
        let lowerTime = min(clampedStart, clampedEnd) * totalDuration
        let upperTime = max(clampedStart, clampedEnd) * totalDuration

        let contained = groups.filter { group in
            group.startTime >= lowerTime && group.endTime <= upperTime
        }

        if !contained.isEmpty {
            return Set(contained.map(\.id))
        }

        let targetTime = ((clampedStart + clampedEnd) / 2) * totalDuration
        guard let nearest = nearestGroup(to: targetTime, groups: groups) else { return [] }
        return [nearest.id]
    }
}

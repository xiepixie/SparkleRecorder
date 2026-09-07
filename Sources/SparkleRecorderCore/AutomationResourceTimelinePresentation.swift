import Foundation

public struct AutomationResourceTimelinePresentation: Equatable, Sendable {
    public var items: [AutomationResourceTimelineItem]
    public var conflictIDs: Set<UUID>

    public init(
        items: [AutomationResourceTimelineItem],
        conflictIDs: Set<UUID>
    ) {
        self.items = items
        self.conflictIDs = conflictIDs
    }

    public static func make(
        items: [AutomationResourceTimelineItem]
    ) -> AutomationResourceTimelinePresentation {
        let sortedItems = items.sorted(by: timelineOrder)
        return AutomationResourceTimelinePresentation(
            items: sortedItems,
            conflictIDs: conflictIDs(in: sortedItems)
        )
    }

    private struct ResourceState {
        var latestStart: (id: UUID, date: Date)?
        var longestActive: (id: UUID, end: Date)?
    }

    private static func timelineOrder(
        _ left: AutomationResourceTimelineItem,
        _ right: AutomationResourceTimelineItem
    ) -> Bool {
        let leftStart = timelineStart(for: left) ?? .distantPast
        let rightStart = timelineStart(for: right) ?? .distantPast
        if leftStart == rightStart {
            if left.title == right.title {
                return left.id.uuidString < right.id.uuidString
            }
            return left.title < right.title
        }
        return leftStart < rightStart
    }

    private static func conflictIDs(
        in items: [AutomationResourceTimelineItem]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        var resourceStates: [String: ResourceState] = [:]

        for item in items {
            guard let interval = interval(for: item) else {
                continue
            }

            for resourceKey in Set(item.resourceKeys ?? []) {
                var state = resourceStates[resourceKey] ?? ResourceState()

                if let latestStart = state.latestStart,
                   interval.start.timeIntervalSince(latestStart.date) < 1 {
                    result.insert(latestStart.id)
                    result.insert(item.id)
                }

                if let longestActive = state.longestActive,
                   longestActive.end > interval.start {
                    result.insert(longestActive.id)
                    result.insert(item.id)
                }

                state.latestStart = (item.id, interval.start)
                if let longestActive = state.longestActive {
                    if interval.end >= longestActive.end {
                        state.longestActive = (item.id, interval.end)
                    }
                } else {
                    state.longestActive = (item.id, interval.end)
                }
                resourceStates[resourceKey] = state
            }
        }

        return result
    }

    private static func interval(
        for item: AutomationResourceTimelineItem
    ) -> (start: Date, end: Date)? {
        guard let start = timelineStart(for: item) else {
            return nil
        }
        if item.status == .running {
            return (start, .distantFuture)
        }
        return (start, max(start, item.completedAt ?? start))
    }

    private static func timelineStart(
        for item: AutomationResourceTimelineItem
    ) -> Date? {
        item.startedAt
            ?? item.earliestStartAt
            ?? item.scheduledAt
            ?? item.createdAt
            ?? item.completedAt
    }
}

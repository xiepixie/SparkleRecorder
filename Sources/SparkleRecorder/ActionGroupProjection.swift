import Foundation

public enum ActionGroupProjection {
    public static func groups(
        from events: [RecordedEvent],
        liveDuration: TimeInterval?,
        hidesMouseMoves: Bool,
        smartMergeGestures: Bool
    ) -> [ActionGroup] {
        var options = EventGroupingOptions()
        options.disableGrouping = !smartMergeGestures

        let groups = EventGrouper(options: options).group(events, liveDuration: liveDuration)
        guard hidesMouseMoves else { return groups }
        return groups.filter { $0.kind != .mouseMove }
    }

    public static func firstGroup(
        containingEventIn eventIndexRange: Range<Int>,
        groups: [ActionGroup]
    ) -> ActionGroup? {
        groups.first(where: { group in
            group.eventIndices.contains { eventIndexRange.contains($0) }
        })
    }

    public static func firstWaitGroup(
        start: TimeInterval,
        end: TimeInterval,
        tolerance: TimeInterval = 0.02,
        groups: [ActionGroup]
    ) -> ActionGroup? {
        groups.first(where: { group in
            group.kind == .wait &&
            abs(group.startTime - start) <= tolerance &&
            abs(group.endTime - end) <= tolerance
        }) ?? groups.last(where: { group in
            group.kind == .wait && abs(group.endTime - end) <= tolerance
        })
    }

    public static func firstBehaviorGroup(
        id: BehaviorGroupID,
        groups: [ActionGroup]
    ) -> ActionGroup? {
        groups.first(where: { $0.behaviorGroupID == id })
    }
}

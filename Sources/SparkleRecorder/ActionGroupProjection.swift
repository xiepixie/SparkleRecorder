import Foundation

public struct ActionGroupSelectionSnapshot: Equatable, Sendable {
    public var groupIDs: [UUID]
    public var eventIndices: [Int]
    public var containsBehavior: Bool

    public init(groupIDs: [UUID] = [], eventIndices: [Int] = [], containsBehavior: Bool = false) {
        self.groupIDs = groupIDs
        self.eventIndices = eventIndices
        self.containsBehavior = containsBehavior
    }

    public var isEmpty: Bool {
        groupIDs.isEmpty
    }

    public var canBindBehavior: Bool {
        eventIndices.count >= 2
    }
}

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

    public static func selectionSnapshot(
        groups: [ActionGroup],
        selectedGroupIDs: Set<UUID>,
        events: [RecordedEvent]
    ) -> ActionGroupSelectionSnapshot {
        guard !selectedGroupIDs.isEmpty else {
            return ActionGroupSelectionSnapshot()
        }

        var groupIDs: [UUID] = []
        var eventIndices: [Int] = []
        var containsBehavior = false

        for group in groups where selectedGroupIDs.contains(group.id) {
            groupIDs.append(group.id)
            eventIndices.append(contentsOf: group.eventIndices)

            if group.behaviorGroupID != nil {
                containsBehavior = true
                continue
            }

            if group.eventIndices.contains(where: { index in
                events.indices.contains(index) && events[index].behaviorGroupID != nil
            }) {
                containsBehavior = true
            }
        }

        eventIndices.sort()
        return ActionGroupSelectionSnapshot(
            groupIDs: groupIDs,
            eventIndices: eventIndices,
            containsBehavior: containsBehavior
        )
    }
}

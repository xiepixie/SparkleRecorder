import Foundation

public enum BehaviorBindReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case needsTwoRecordedActions
    case nonContiguousRecordedActions
    case containsBehavior

    public var canBind: Bool {
        self == .ready
    }
}

public struct ActionGroupSelectionSnapshot: Equatable, Sendable {
    public var groupIDs: [UUID]
    public var eventIndices: [Int]
    public var eventBackedGroupCount: Int
    public var eventBackedSelectionIsContiguous: Bool
    public var containsBehavior: Bool

    public init(
        groupIDs: [UUID] = [],
        eventIndices: [Int] = [],
        eventBackedGroupCount: Int? = nil,
        eventBackedSelectionIsContiguous: Bool = true,
        containsBehavior: Bool = false
    ) {
        self.groupIDs = groupIDs
        self.eventIndices = eventIndices
        self.eventBackedGroupCount = eventBackedGroupCount ?? (eventIndices.isEmpty ? 0 : groupIDs.count)
        self.eventBackedSelectionIsContiguous = eventBackedSelectionIsContiguous
        self.containsBehavior = containsBehavior
    }

    public var isEmpty: Bool {
        groupIDs.isEmpty
    }

    public var behaviorBindReadiness: BehaviorBindReadiness {
        guard !groupIDs.isEmpty else { return .noSelection }
        guard !containsBehavior else { return .containsBehavior }
        guard eventBackedGroupCount >= 2 else { return .needsTwoRecordedActions }
        guard eventBackedSelectionIsContiguous else { return .nonContiguousRecordedActions }
        return .ready
    }

    public var canBindBehavior: Bool {
        behaviorBindReadiness.canBind
    }
}

public enum TextTargetReadiness: String, Codable, Equatable, Sendable {
    case notTextTarget
    case missingAnchor
    case missingText
    case ready

    public var isReady: Bool {
        self == .ready
    }

    public var needsUserTarget: Bool {
        self == .missingAnchor || self == .missingText
    }
}

public enum ActionPreviewAffordance: String, Codable, Equatable, Sendable {
    case none
    case inputPoint
    case inputPath
    case pointSequence
    case textClickTarget
    case waitTextRegion
    case waitTextGoneRegion
    case verifyTextRegion

    public var showsClickPulse: Bool {
        switch self {
        case .inputPoint, .textClickTarget:
            return true
        default:
            return false
        }
    }

    public var showsLocatorFallbackPoint: Bool {
        self == .textClickTarget
    }

    public var showsConditionRegion: Bool {
        switch self {
        case .waitTextRegion, .waitTextGoneRegion, .verifyTextRegion:
            return true
        default:
            return false
        }
    }

    public var showsTargetRegionLabel: Bool {
        switch self {
        case .textClickTarget, .waitTextRegion, .waitTextGoneRegion, .verifyTextRegion:
            return true
        default:
            return false
        }
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

    public static func eventIndices(
        matching eventsToMatch: [RecordedEvent],
        in events: [RecordedEvent]
    ) -> Set<Int> {
        guard !eventsToMatch.isEmpty else { return [] }

        var remaining = eventsToMatch
        var indices = Set<Int>()
        for (index, event) in events.enumerated() {
            guard let matchIndex = remaining.firstIndex(of: event) else { continue }
            indices.insert(index)
            remaining.remove(at: matchIndex)
            if remaining.isEmpty { break }
        }
        return indices
    }

    public static func firstGroup(
        matching eventsToMatch: [RecordedEvent],
        in events: [RecordedEvent],
        groups: [ActionGroup]
    ) -> ActionGroup? {
        let indices = eventIndices(matching: eventsToMatch, in: events)
        guard !indices.isEmpty else { return nil }
        return groups.first(where: { group in
            group.eventIndices.contains { indices.contains($0) }
        })
    }

    public static func groups(
        containingEventIndices eventIndices: Set<Int>,
        groups: [ActionGroup]
    ) -> [ActionGroup] {
        guard !eventIndices.isEmpty else { return [] }
        return groups.filter { group in
            group.eventIndices.contains { eventIndices.contains($0) }
        }
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
        var eventBackedGroupCount = 0
        var eventBackedOrdinal = 0
        var selectedEventBackedOrdinals: [Int] = []
        var containsBehavior = false

        for group in groups {
            let isEventBacked = !group.eventIndices.isEmpty
            defer {
                if isEventBacked {
                    eventBackedOrdinal += 1
                }
            }

            guard selectedGroupIDs.contains(group.id) else { continue }
            groupIDs.append(group.id)
            eventIndices.append(contentsOf: group.eventIndices)
            if isEventBacked {
                eventBackedGroupCount += 1
                selectedEventBackedOrdinals.append(eventBackedOrdinal)
            }

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
        let eventBackedSelectionIsContiguous: Bool = {
            guard selectedEventBackedOrdinals.count > 1,
                  let first = selectedEventBackedOrdinals.first,
                  let last = selectedEventBackedOrdinals.last else {
                return true
            }
            return (last - first + 1) == selectedEventBackedOrdinals.count
        }()
        return ActionGroupSelectionSnapshot(
            groupIDs: groupIDs,
            eventIndices: eventIndices,
            eventBackedGroupCount: eventBackedGroupCount,
            eventBackedSelectionIsContiguous: eventBackedSelectionIsContiguous,
            containsBehavior: containsBehavior
        )
    }

    public static func textTargetGroups(
        groups: [ActionGroup],
        selectedGroupIDs: Set<UUID>,
        events: [RecordedEvent],
        includesCoordinateClickCandidates: Bool = true
    ) -> [ActionGroup] {
        groups.filter { group in
            selectedGroupIDs.contains(group.id) &&
            isTextTargetGroup(
                group,
                events: events,
                includesCoordinateClickCandidates: includesCoordinateClickCandidates
            )
        }
    }

    public static func isTextTargetGroup(
        _ group: ActionGroup,
        events: [RecordedEvent],
        includesCoordinateClickCandidates: Bool = true
    ) -> Bool {
        if editsSemanticTextTarget(group.kind) { return true }
        guard canUseLocatorStrategy(group.kind) else { return false }

        let hasEvent = group.eventIndices.contains { events.indices.contains($0) }
        if group.textAnchor != nil { return hasEvent }
        if group.eventIndices.contains(where: { index in
            guard events.indices.contains(index) else { return false }
            let event = events[index]
            return event.coordinateStrategy == .locatorOnly || event.textAnchor != nil
        }) {
            return true
        }

        return includesCoordinateClickCandidates &&
            hasEvent &&
            canBecomeTextClickTarget(group.kind)
    }

    public static func textTargetReadiness(
        for group: ActionGroup,
        events: [RecordedEvent],
        includesCoordinateClickCandidates: Bool = false
    ) -> TextTargetReadiness {
        guard isTextTargetGroup(
            group,
            events: events,
            includesCoordinateClickCandidates: includesCoordinateClickCandidates
        ) else {
            return .notTextTarget
        }

        guard let anchor = firstTextAnchor(for: group, events: events) else {
            return .missingAnchor
        }
        return textAnchorIsReady(anchor) ? .ready : .missingText
    }

    public static func textAnchorIsReady(_ anchor: TextAnchor?) -> Bool {
        guard let anchor else { return false }
        return !anchor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func firstTextAnchor(
        for group: ActionGroup,
        events: [RecordedEvent]
    ) -> TextAnchor? {
        for index in group.eventIndices where events.indices.contains(index) {
            if let anchor = events[index].textAnchor {
                return anchor
            }
        }
        return group.textAnchor
    }

    public static func previewAffordance(
        for kind: ActionGroupKind,
        usesTextLocator: Bool = false
    ) -> ActionPreviewAffordance {
        switch kind {
        case .waitForText:
            return .waitTextRegion
        case .waitForTextGone:
            return .waitTextGoneRegion
        case .verifyText:
            return .verifyTextRegion
        case .multiPointClick:
            return .pointSequence
        case .drag:
            return .inputPath
        case .click, .doubleClick, .longPress, .repeatedClick:
            return usesTextLocator ? .textClickTarget : .inputPoint
        case .scroll, .mouseMove:
            return .inputPoint
        default:
            return .none
        }
    }

    private static func editsSemanticTextTarget(_ kind: ActionGroupKind) -> Bool {
        switch kind {
        case .waitForText, .waitForTextGone, .verifyText:
            return true
        default:
            return false
        }
    }

    private static func canUseLocatorStrategy(_ kind: ActionGroupKind) -> Bool {
        switch kind {
        case .click, .doubleClick, .repeatedClick, .longPress, .scroll:
            return true
        default:
            return false
        }
    }

    private static func canBecomeTextClickTarget(_ kind: ActionGroupKind) -> Bool {
        switch kind {
        case .click, .doubleClick, .repeatedClick, .longPress:
            return true
        default:
            return false
        }
    }
}

public enum TextClickEventFactory {
    public static func makeEvents(
        startTime: TimeInterval,
        textAnchor: TextAnchor,
        timeout: TimeInterval = 10.0,
        fallbackPolicy: LocatorFallbackPolicy = .fail,
        surfaceId: String? = nil
    ) -> [RecordedEvent] {
        let clickableAnchor = TextTargetAnchorFactory.clickableAnchor(textAnchor)
        let point = clickPoint(for: clickableAnchor)
        let down = RecordedEvent(
            kind: .leftMouseDown,
            time: startTime,
            x: point.x,
            y: point.y,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 1,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            coordinateBinding: .targetWindow,
            coordinateStrategy: .locatorOnly,
            locatorFallbackPolicy: fallbackPolicy,
            surfaceId: surfaceId,
            textAnchor: clickableAnchor,
            textTimeout: timeout
        )
        let up = RecordedEvent(
            kind: .leftMouseUp,
            time: startTime + 0.1,
            x: point.x,
            y: point.y,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 1,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            coordinateBinding: .targetWindow,
            coordinateStrategy: .locatorOnly,
            locatorFallbackPolicy: fallbackPolicy,
            surfaceId: surfaceId,
            textAnchor: clickableAnchor,
            textTimeout: timeout
        )
        return [down, up]
    }

    private static func clickPoint(for anchor: TextAnchor) -> PointValue {
        if let fallback = anchor.coordinateFallback {
            return fallback
        }
        if anchor.observedFrame.width > 0, anchor.observedFrame.height > 0 {
            return PointValue(
                x: anchor.observedFrame.x + anchor.observedFrame.width / 2,
                y: anchor.observedFrame.y + anchor.observedFrame.height / 2
            )
        }
        return PointValue(x: 100, y: 100)
    }
}

public enum TextTargetAnchorFactory {
    public static func anchor(
        existing: TextAnchor?,
        text: String,
        fallbackEvent: RecordedEvent? = nil
    ) -> TextAnchor {
        var anchor = existing ?? TextAnchor(
            text: text,
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        anchor.text = text
        return clickableAnchor(anchor, fallbackEvent: fallbackEvent)
    }

    public static func clickableAnchor(
        _ anchor: TextAnchor,
        fallbackEvent: RecordedEvent? = nil
    ) -> TextAnchor {
        var result = anchor

        if result.coordinateFallback == nil {
            if let point = absoluteFallbackPoint(from: fallbackEvent) {
                result.coordinateFallback = point
            } else if result.observedFrame.width > 0, result.observedFrame.height > 0 {
                result.coordinateFallback = PointValue(
                    x: result.observedFrame.x + result.observedFrame.width / 2,
                    y: result.observedFrame.y + result.observedFrame.height / 2
                )
            }
        }

        if result.coordinateFallbackContentNormalized == nil {
            if let point = contentNormalizedFallbackPoint(from: fallbackEvent) {
                result.coordinateFallbackContentNormalized = point
            } else if let observed = result.observedContentNormalizedFrame,
                      observed.width > 0,
                      observed.height > 0 {
                result.coordinateFallbackContentNormalized = PointValue(
                    x: observed.x + observed.width / 2,
                    y: observed.y + observed.height / 2
                )
            }
        }

        return result
    }

    private static func absoluteFallbackPoint(from event: RecordedEvent?) -> PointValue? {
        guard let event,
              isClickableFallbackEvent(event),
              event.x.isFinite,
              event.y.isFinite else {
            return nil
        }
        return PointValue(x: event.x, y: event.y)
    }

    private static func contentNormalizedFallbackPoint(from event: RecordedEvent?) -> PointValue? {
        guard let event,
              isClickableFallbackEvent(event),
              let x = event.contentNormalizedX,
              let y = event.contentNormalizedY,
              x.isFinite,
              y.isFinite else {
            return nil
        }
        return PointValue(x: x, y: y)
    }

    private static func isClickableFallbackEvent(_ event: RecordedEvent) -> Bool {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

public struct ActionGroupTextClickConversionPlan: Equatable, Sendable {
    public var sourceEventIndex: Int?
    public var insertedEvents: [RecordedEvent]
    public var eventTimeShifts: [ActionGroupEventTimeShift]
    public var liveDurationAfterConversion: TimeInterval?

    public init(
        sourceEventIndex: Int? = nil,
        insertedEvents: [RecordedEvent] = [],
        eventTimeShifts: [ActionGroupEventTimeShift] = [],
        liveDurationAfterConversion: TimeInterval? = nil
    ) {
        self.sourceEventIndex = sourceEventIndex
        self.insertedEvents = insertedEvents
        self.eventTimeShifts = eventTimeShifts
        self.liveDurationAfterConversion = liveDurationAfterConversion
    }

    public var isEmpty: Bool {
        sourceEventIndex == nil || insertedEvents.isEmpty
    }
}

public enum TextClickConversionReadiness: String, Codable, Equatable, Sendable {
    case ready
    case unsupportedAction
    case missingSourceEvent
    case sourceEventMismatch

    public var canConvert: Bool {
        self == .ready
    }
}

public enum ActionGroupTextClickConversionPlanner {
    private static let clickDuration: TimeInterval = 0.1

    public static func readiness(
        for group: ActionGroup,
        events: [RecordedEvent]
    ) -> TextClickConversionReadiness {
        guard group.kind == .waitForText else {
            return .unsupportedAction
        }
        guard let sourceIndex = group.eventIndices.first,
              events.indices.contains(sourceIndex) else {
            return .missingSourceEvent
        }
        guard events[sourceIndex].kind == .waitForText else {
            return .sourceEventMismatch
        }
        return .ready
    }

    public static func plan(
        for group: ActionGroup,
        events: [RecordedEvent],
        liveDuration: TimeInterval,
        textAnchorOverride: TextAnchor? = nil,
        textTimeoutOverride: TimeInterval? = nil,
        fallbackPolicy: LocatorFallbackPolicy = .fail
    ) -> ActionGroupTextClickConversionPlan {
        guard readiness(for: group, events: events).canConvert,
              let sourceIndex = group.eventIndices.first else {
            return ActionGroupTextClickConversionPlan()
        }

        let sourceEvent = events[sourceIndex]
        let anchor = TextTargetAnchorFactory.clickableAnchor(
            textAnchorOverride
                ?? sourceEvent.textAnchor
                ?? group.textAnchor
                ?? TextAnchor(text: "", observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)),
            fallbackEvent: sourceEvent
        )
        let insertedEvents = TextClickEventFactory.makeEvents(
            startTime: sourceEvent.time,
            textAnchor: anchor,
            timeout: textTimeoutOverride ?? sourceEvent.textTimeout ?? group.textTimeout ?? 10.0,
            fallbackPolicy: sourceEvent.locatorFallbackPolicy ?? fallbackPolicy,
            surfaceId: sourceEvent.surfaceId
        )

        let clickEndTime = insertedEvents.map(\.time).max() ?? (sourceEvent.time + clickDuration)
        let followingIndices = events.indices.filter { $0 > sourceIndex }
        let earliestFollowingTime = followingIndices.map { events[$0].time }.min()
        let shiftDelta = earliestFollowingTime.map { max(0, clickEndTime - $0) } ?? 0
        let eventTimeShifts = shiftDelta > 0
            ? [ActionGroupEventTimeShift(eventIndices: Array(followingIndices), delta: shiftDelta)]
            : []

        let liveDurationAfterConversion: TimeInterval?
        if shiftDelta > 0 {
            liveDurationAfterConversion = max(clickEndTime, liveDuration + shiftDelta)
        } else if liveDuration < clickEndTime {
            liveDurationAfterConversion = clickEndTime
        } else {
            liveDurationAfterConversion = nil
        }

        return ActionGroupTextClickConversionPlan(
            sourceEventIndex: sourceIndex,
            insertedEvents: insertedEvents,
            eventTimeShifts: eventTimeShifts,
            liveDurationAfterConversion: liveDurationAfterConversion
        )
    }
}

public struct ActionGroupDeletionPlan: Equatable, Sendable {
    public var eventTimeShifts: [ActionGroupEventTimeShift]
    public var eventIndices: [Int]
    public var subsequentShiftCutoffTime: TimeInterval?
    public var subsequentShift: TimeInterval
    public var liveDurationAfterDeletion: TimeInterval?

    public init(
        eventTimeShifts: [ActionGroupEventTimeShift] = [],
        eventIndices: [Int] = [],
        subsequentShiftCutoffTime: TimeInterval? = nil,
        subsequentShift: TimeInterval = 0,
        liveDurationAfterDeletion: TimeInterval? = nil
    ) {
        self.eventTimeShifts = eventTimeShifts
        self.eventIndices = eventIndices
        self.subsequentShiftCutoffTime = subsequentShiftCutoffTime
        self.subsequentShift = subsequentShift
        self.liveDurationAfterDeletion = liveDurationAfterDeletion
    }

    public var isEmpty: Bool {
        eventTimeShifts.isEmpty &&
            eventIndices.isEmpty &&
            subsequentShiftCutoffTime == nil &&
            liveDurationAfterDeletion == nil
    }
}

public struct ActionGroupEventTimeShift: Equatable, Sendable {
    public var eventIndices: [Int]
    public var delta: TimeInterval

    public init(eventIndices: [Int], delta: TimeInterval) {
        self.eventIndices = eventIndices
        self.delta = delta
    }
}

public struct ActionGroupPassiveWaitDuplicationPlan: Equatable, Sendable {
    public var eventTimeShifts: [ActionGroupEventTimeShift]
    public var liveDurationAfterDuplication: TimeInterval?

    public init(
        eventTimeShifts: [ActionGroupEventTimeShift] = [],
        liveDurationAfterDuplication: TimeInterval? = nil
    ) {
        self.eventTimeShifts = eventTimeShifts
        self.liveDurationAfterDuplication = liveDurationAfterDuplication
    }

    public var isEmpty: Bool {
        eventTimeShifts.isEmpty && liveDurationAfterDuplication == nil
    }
}

public struct ActionGroupPassiveWaitDurationEditPlan: Equatable, Sendable {
    public var eventTimeShifts: [ActionGroupEventTimeShift]
    public var liveDurationAfterEdit: TimeInterval?
    public var editedWaitStartTime: TimeInterval?
    public var editedWaitEndTime: TimeInterval?

    public init(
        eventTimeShifts: [ActionGroupEventTimeShift] = [],
        liveDurationAfterEdit: TimeInterval? = nil,
        editedWaitStartTime: TimeInterval? = nil,
        editedWaitEndTime: TimeInterval? = nil
    ) {
        self.eventTimeShifts = eventTimeShifts
        self.liveDurationAfterEdit = liveDurationAfterEdit
        self.editedWaitStartTime = editedWaitStartTime
        self.editedWaitEndTime = editedWaitEndTime
    }

    public var isEmpty: Bool {
        eventTimeShifts.isEmpty && liveDurationAfterEdit == nil
    }
}

public enum ActionGroupPassiveWaitDurationEditPlanner {
    public static func plan(
        for group: ActionGroup,
        events: [RecordedEvent],
        liveDuration: TimeInterval,
        newDuration: TimeInterval
    ) -> ActionGroupPassiveWaitDurationEditPlan {
        guard group.kind == .wait, newDuration.isFinite else {
            return ActionGroupPassiveWaitDurationEditPlan()
        }

        let currentDuration = max(0, group.endTime - group.startTime)
        let clampedDuration = max(0, newDuration)
        let delta = clampedDuration - currentDuration
        guard delta != 0 else {
            return ActionGroupPassiveWaitDurationEditPlan()
        }

        let affectedIndices = events.indices.filter { events[$0].time >= group.endTime }
        let eventTimeShifts = affectedIndices.isEmpty
            ? []
            : [ActionGroupEventTimeShift(eventIndices: Array(affectedIndices), delta: delta)]

        return ActionGroupPassiveWaitDurationEditPlan(
            eventTimeShifts: eventTimeShifts,
            liveDurationAfterEdit: max(0, liveDuration + delta),
            editedWaitStartTime: group.startTime,
            editedWaitEndTime: group.startTime + clampedDuration
        )
    }
}

public enum ActionGroupPassiveWaitDuplicationPlanner {
    public static func plan(
        for groups: [ActionGroup],
        events: [RecordedEvent],
        liveDuration: TimeInterval
    ) -> ActionGroupPassiveWaitDuplicationPlan {
        var waitExtensions: [(endTime: TimeInterval, duration: TimeInterval)] = []
        var trailingWaitDelta: TimeInterval = 0

        for group in groups where group.kind == .wait {
            let waitDuration = max(0, group.endTime - group.startTime)
            guard waitDuration > 0 else { continue }

            let hasEventsAfter = events.contains { $0.time >= group.endTime }
            if hasEventsAfter {
                waitExtensions.append((endTime: group.endTime, duration: waitDuration))
            } else {
                trailingWaitDelta += waitDuration
            }
        }

        let eventTimeShifts = makeEventTimeShifts(
            waitExtensions: waitExtensions,
            events: events
        )
        let totalWaitDelta = waitExtensions.reduce(trailingWaitDelta) { $0 + $1.duration }
        let liveDurationAfterDuplication = totalWaitDelta > 0
            ? liveDuration + totalWaitDelta
            : nil

        return ActionGroupPassiveWaitDuplicationPlan(
            eventTimeShifts: eventTimeShifts,
            liveDurationAfterDuplication: liveDurationAfterDuplication
        )
    }

    private static func makeEventTimeShifts(
        waitExtensions: [(endTime: TimeInterval, duration: TimeInterval)],
        events: [RecordedEvent]
    ) -> [ActionGroupEventTimeShift] {
        guard !waitExtensions.isEmpty else { return [] }

        let indexedDeltas = events.enumerated().compactMap { index, event -> (index: Int, delta: TimeInterval)? in
            let delta = waitExtensions.reduce(TimeInterval(0)) { partial, wait in
                event.time >= wait.endTime ? partial + wait.duration : partial
            }
            guard delta != 0 else { return nil }
            return (index, delta)
        }

        let grouped = Dictionary(grouping: indexedDeltas, by: \.delta)
        return grouped
            .map { delta, rows in
                ActionGroupEventTimeShift(
                    eventIndices: rows.map(\.index).sorted(),
                    delta: delta
                )
            }
            .sorted {
                ($0.eventIndices.first ?? Int.max) < ($1.eventIndices.first ?? Int.max)
            }
    }
}

public enum ActionGroupDeletionPlanner {
    public static func plan(
        for groups: [ActionGroup],
        events: [RecordedEvent],
        liveDuration: TimeInterval
    ) -> ActionGroupDeletionPlan {
        var eventIndices = Set<Int>()
        var waitShifts: [(endTime: TimeInterval, duration: TimeInterval)] = []
        var trailingWaitDelta: TimeInterval = 0

        for group in groups {
            if group.kind == .wait {
                let waitDuration = max(0, group.endTime - group.startTime)
                guard waitDuration > 0 else { continue }

                let hasEventsAfter = events.contains { $0.time >= group.endTime }
                if hasEventsAfter {
                    waitShifts.append((endTime: group.endTime, duration: waitDuration))
                } else {
                    trailingWaitDelta += waitDuration
                }
            } else {
                for index in group.eventIndices where events.indices.contains(index) {
                    eventIndices.insert(index)
                }
            }
        }

        let eventTimeShifts = makeEventTimeShifts(
            waitShifts: waitShifts,
            deletedEventIndices: eventIndices,
            events: events
        )
        let totalWaitDelta = waitShifts.reduce(trailingWaitDelta) { $0 + $1.duration }

        let shiftCutoff: TimeInterval?
        let shift: TimeInterval
        if let firstShift = waitShifts.map(\.endTime).min() {
            shiftCutoff = firstShift
            shift = -waitShifts.reduce(0) { $0 + $1.duration }
        } else {
            shiftCutoff = nil
            shift = 0
        }

        let liveDurationAfterDeletion = totalWaitDelta > 0
            ? max(0, liveDuration - totalWaitDelta)
            : nil

        return ActionGroupDeletionPlan(
            eventTimeShifts: eventTimeShifts,
            eventIndices: eventIndices.sorted(),
            subsequentShiftCutoffTime: shiftCutoff,
            subsequentShift: shift,
            liveDurationAfterDeletion: liveDurationAfterDeletion
        )
    }

    private static func makeEventTimeShifts(
        waitShifts: [(endTime: TimeInterval, duration: TimeInterval)],
        deletedEventIndices: Set<Int>,
        events: [RecordedEvent]
    ) -> [ActionGroupEventTimeShift] {
        guard !waitShifts.isEmpty else { return [] }

        let indexedDeltas = events.enumerated().compactMap { index, event -> (index: Int, delta: TimeInterval)? in
            guard !deletedEventIndices.contains(index) else { return nil }
            let delta = waitShifts.reduce(TimeInterval(0)) { partial, wait in
                event.time >= wait.endTime ? partial - wait.duration : partial
            }
            guard delta != 0 else { return nil }
            return (index, delta)
        }

        let grouped = Dictionary(grouping: indexedDeltas, by: \.delta)
        return grouped
            .map { delta, rows in
                ActionGroupEventTimeShift(
                    eventIndices: rows.map(\.index).sorted(),
                    delta: delta
                )
            }
            .sorted {
                ($0.eventIndices.first ?? Int.max) < ($1.eventIndices.first ?? Int.max)
            }
    }
}

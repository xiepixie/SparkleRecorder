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

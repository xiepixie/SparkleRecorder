import Foundation

/// Source evidence for review, not a new executable event kind. A singleton click
/// can represent only a mouse down or up; text input still refers to its raw keys.
public struct MacroReconstructedAction: Equatable, Sendable {
    public let id: String
    public let kind: ActionGroupKind
    public let sourceEventIndices: [Int]
    public let startTime: Double
    public let endTime: Double
    public let surfaceID: String?
    public let startPoint: PointValue?
    public let endPoint: PointValue?

    public init(
        id: String, kind: ActionGroupKind, sourceEventIndices: [Int],
        startTime: Double, endTime: Double, surfaceID: String? = nil,
        startPoint: PointValue? = nil, endPoint: PointValue? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceEventIndices = sourceEventIndices
        self.startTime = startTime
        self.endTime = endTime
        self.surfaceID = surfaceID
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

public enum MacroActionReconstructionError: Error, Equatable, Sendable {
    case emptySourceRevision
    case invalidTimestamp(eventIndex: Int)
    case descendingTimestamp(eventIndex: Int)
    case unsafeGroupingEvidence(eventIndex: Int)
    case invalidSourceCoverage
}

public enum MacroActionReconstructor {
    /// Policy v1 uses the default grouping thresholds and ignores editor behavior
    /// annotations. Change the version when reconstruction grouping policy changes.
    public static func reconstruct(
        events: [RecordedEvent], sourceRevision: String
    ) throws -> [MacroReconstructedAction] {
        guard !sourceRevision.isEmpty else { throw MacroActionReconstructionError.emptySourceRevision }
        for (index, event) in events.enumerated() {
            guard event.time.isFinite, event.time >= 0 else {
                throw MacroActionReconstructionError.invalidTimestamp(eventIndex: index)
            }
            if index > 0, event.time < events[index - 1].time {
                throw MacroActionReconstructionError.descendingTimestamp(eventIndex: index)
            }
            if event.kind.isMouse, !event.x.isFinite || !event.y.isFinite {
                throw MacroActionReconstructionError.unsafeGroupingEvidence(eventIndex: index)
            }
        }
        let options = EventGroupingOptions()
        let source = events.map { event in
            var copy = event
            copy.behaviorGroupID = nil
            copy.behaviorGroupName = nil
            return copy
        }
        let groups = requiresRawNumericFallback(source)
            ? rawGroups(source, options: options)
            : EventGrouper(options: options).group(source)
        var coverage = Array(repeating: 0, count: events.count)
        for group in groups {
            guard group.kind == .wait ? group.eventIndices.isEmpty : !group.eventIndices.isEmpty else {
                throw MacroActionReconstructionError.invalidSourceCoverage
            }
            for index in group.eventIndices {
                guard events.indices.contains(index), coverage[index] == 0 else {
                    throw MacroActionReconstructionError.invalidSourceCoverage
                }
                coverage[index] += 1
            }
        }
        guard coverage.allSatisfy({ $0 == 1 }) else {
            throw MacroActionReconstructionError.invalidSourceCoverage
        }

        // UTF-8 hex avoids delimiter collisions without locale-dependent formatting
        // or process-randomized hashing. IDs never depend on group UUID or summary.
        let revision = sourceRevision.utf8.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        func action(
            kind: ActionGroupKind, indices: [Int], start: Double, end: Double,
            surface: String?, startPoint: PointValue?, endPoint: PointValue?
        ) -> MacroReconstructedAction {
            let range = "\(String(start.bitPattern, radix: 16))-\(String(end.bitPattern, radix: 16))"
            let identity = indices.map(String.init).joined(separator: ",")
            return MacroReconstructedAction(
                id: "macro-action/v1/\(revision)/\(kind.rawValue)/\(identity)/\(range)",
                kind: kind, sourceEventIndices: indices, startTime: start, endTime: end,
                surfaceID: surface, startPoint: startPoint, endPoint: endPoint
            )
        }
        func project(_ group: ActionGroup, indices: [Int]) -> MacroReconstructedAction {
            let first = indices.first.map { events[$0] }
            let last = indices.last.map { events[$0] }
            // Display groups can use the beginning of their final scroll burst
            // as an endpoint. Evidence points must match the actual endpoint time.
            return action(
                kind: group.kind, indices: indices,
                start: first?.time ?? group.startTime, end: last?.time ?? group.endTime,
                surface: first?.surfaceId,
                startPoint: first.flatMap { $0.kind.isMouse ? PointValue(x: $0.x, y: $0.y) : nil },
                endPoint: last.flatMap { $0.kind.isMouse ? PointValue(x: $0.x, y: $0.y) : nil }
            )
        }
        return groups.flatMap { group in
            let surfaces = Set(group.eventIndices.map { events[$0].surfaceId })
            let keyboardKinds: Set<ActionGroupKind> = [.keyPress, .keyHold, .keyRepeat, .shortcut, .modifierHold, .textInput]
            let containsNonKey = group.eventIndices.contains { !events[$0].kind.isKey }
            if surfaces.count > 1 || (keyboardKinds.contains(group.kind) && containsNonKey) {
                // Shortcuts can consume a pointer interruption in editor grouping.
                // Raw evidence preserves that pointer and any gaps within the group.
                return rawGroups(group.eventIndices.map { events[$0] }, options: options).map { raw in
                    project(raw, indices: raw.eventIndices.map { group.eventIndices[$0] })
                }
            }
            return [project(group, indices: group.eventIndices)]
        }
    }

    private static func rawKind(_ event: RecordedEvent) -> ActionGroupKind {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp: .click
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: .drag
        case .mouseMoved: .mouseMove
        case .scrollWheel: .scroll
        case .keyDown, .keyUp, .flagsChanged: .keyPress
        case .waitForText: event.verifyMustExist == false ? .waitForTextGone : .waitForText
        case .verifyText: .verifyText
        }
    }

    /// Bound every possible aggregate, rather than reproduce the grouper's burst
    /// and segment rules. Risky but valid numbers retain singleton source evidence.
    private static func requiresRawNumericFallback(_ events: [RecordedEvent]) -> Bool {
        var positive = Array(repeating: Int32(0), count: 4)
        var negative = Array(repeating: Int32(0), count: 4)
        for event in events {
            // A click merge increments its initial OS click count once per group.
            if event.clickCount > Int64.max - Int64(events.count) { return true }
            if event.kind.isMouse,
               Int(exactly: event.x.rounded(.towardZero)) == nil || Int(exactly: event.y.rounded(.towardZero)) == nil {
                return true
            }
            guard event.kind == .scrollWheel else { continue }
            let values = [event.scrollDeltaX, event.scrollDeltaY,
                          event.scrollPayload?.lineDeltaX ?? 0, event.scrollPayload?.lineDeltaY ?? 0]
            for (index, value) in values.enumerated() {
                if value >= 0 {
                    let result = positive[index].addingReportingOverflow(value)
                    if result.overflow { return true }
                    positive[index] = result.partialValue
                } else {
                    let result = negative[index].addingReportingOverflow(value)
                    if result.overflow { return true }
                    negative[index] = result.partialValue
                }
            }
        }
        return false
    }

    private static func rawGroups(_ events: [RecordedEvent], options: EventGroupingOptions) -> [ActionGroup] {
        var groups: [ActionGroup] = []
        for (index, event) in events.enumerated() {
            if index > 0, event.time - events[index - 1].time > options.waitThreshold {
                groups.append(ActionGroup(kind: .wait, eventIndices: [], startTime: events[index - 1].time,
                                          endTime: event.time, summary: ""))
            }
            groups.append(ActionGroup(
                kind: rawKind(event), eventIndices: [index], startTime: event.time, endTime: event.time,
                startPoint: event.kind.isMouse ? event.location : nil,
                endPoint: event.kind.isMouse ? event.location : nil, summary: ""
            ))
        }
        return groups
    }
}

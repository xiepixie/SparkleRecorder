import Foundation

public enum SemanticRecordingPlayableSanitizationField: String, Codable, Equatable, Sendable {
    case unicodeString
    case textAnchorText
    case behaviorGroupName

    public var preservesPlaybackInput: Bool {
        switch self {
        case .unicodeString,
             .behaviorGroupName:
            return true

        case .textAnchorText:
            return false
        }
    }
}

public struct SemanticRecordingPlayableEventSanitization: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { eventIndex }
    public var eventIndex: Int
    public var eventKind: RecordedEvent.Kind
    public var recordingTime: TimeInterval
    public var timelineEventID: UUID?
    public var frameID: UUID?
    public var sourceSuppressionIDs: [UUID]
    public var reasons: [RecordingSuppressionReason]
    public var redactedFields: [SemanticRecordingPlayableSanitizationField]
    public var fallback: String

    public init(
        eventIndex: Int,
        eventKind: RecordedEvent.Kind,
        recordingTime: TimeInterval,
        timelineEventID: UUID? = nil,
        frameID: UUID? = nil,
        sourceSuppressionIDs: [UUID],
        reasons: [RecordingSuppressionReason],
        redactedFields: [SemanticRecordingPlayableSanitizationField],
        fallback: String
    ) {
        self.eventIndex = max(0, eventIndex)
        self.eventKind = eventKind
        self.recordingTime = max(0, recordingTime)
        self.timelineEventID = timelineEventID
        self.frameID = frameID
        self.sourceSuppressionIDs = sourceSuppressionIDs
        self.reasons = reasons
        self.redactedFields = redactedFields
        self.fallback = fallback
    }

    public var preservesPlaybackInput: Bool {
        redactedFields.allSatisfy(\.preservesPlaybackInput)
    }
}

public struct SemanticRecordingPlayableSanitizationPlan: Codable, Equatable, Sendable {
    public var recordingID: UUID?
    public var eventSanitizations: [SemanticRecordingPlayableEventSanitization]

    public init(
        recordingID: UUID? = nil,
        eventSanitizations: [SemanticRecordingPlayableEventSanitization] = []
    ) {
        self.recordingID = recordingID
        self.eventSanitizations = eventSanitizations
    }

    public var isEmpty: Bool {
        eventSanitizations.isEmpty
    }

    public var preservesPlaybackInput: Bool {
        eventSanitizations.allSatisfy(\.preservesPlaybackInput)
    }

    public var playbackPreservingEventSanitizations: [SemanticRecordingPlayableEventSanitization] {
        eventSanitizations.filter(\.preservesPlaybackInput)
    }

    public var reviewRequiredEventSanitizations: [SemanticRecordingPlayableEventSanitization] {
        eventSanitizations.filter { !$0.preservesPlaybackInput }
    }

    public func sanitizedEvents(
        from events: [RecordedEvent]
    ) -> [RecordedEvent] {
        sanitizedEvents(from: events, applying: eventSanitizations)
    }

    public func playbackPreservingSanitizedEvents(
        from events: [RecordedEvent]
    ) -> [RecordedEvent] {
        sanitizedEvents(from: events, applying: playbackPreservingEventSanitizations)
    }

    public func summary(appliedAt: Date = Date()) -> MacroPlayableSanitizationSummary {
        MacroPlayableSanitizationSummary(
            recordingID: recordingID,
            appliedAt: appliedAt,
            sanitizedEventCount: playbackPreservingEventSanitizations.count,
            withheldReadableFieldCount: playbackPreservingEventSanitizations.reduce(0) {
                $0 + $1.redactedFields.count
            },
            reviewRequiredEventCount: reviewRequiredEventSanitizations.count,
            reviewRequiredFieldCount: reviewRequiredEventSanitizations.reduce(0) {
                $0 + $1.redactedFields.count
            }
        )
    }

    private func sanitizedEvents(
        from events: [RecordedEvent],
        applying eventSanitizations: [SemanticRecordingPlayableEventSanitization]
    ) -> [RecordedEvent] {
        guard !eventSanitizations.isEmpty else {
            return events
        }

        let sanitizationsByIndex = Dictionary(
            uniqueKeysWithValues: eventSanitizations.map { ($0.eventIndex, $0) }
        )
        return events.enumerated().map { index, event in
            guard let sanitization = sanitizationsByIndex[index] else {
                return event
            }
            return Self.sanitized(event, fields: sanitization.redactedFields)
        }
    }

    private static func sanitized(
        _ event: RecordedEvent,
        fields: [SemanticRecordingPlayableSanitizationField]
    ) -> RecordedEvent {
        var sanitized = event
        for field in fields {
            switch field {
            case .unicodeString:
                sanitized.unicodeString = nil

            case .textAnchorText:
                if var anchor = sanitized.textAnchor {
                    anchor.text = ""
                    sanitized.textAnchor = anchor
                }

            case .behaviorGroupName:
                sanitized.behaviorGroupName = nil
            }
        }
        return sanitized
    }
}

public enum SemanticRecordingPlayableSanitizationPlanner {
    public static func plan(
        for macro: SavedMacro,
        bundle: SemanticRecordingBundle
    ) -> SemanticRecordingPlayableSanitizationPlan {
        plan(for: macro.events, bundle: bundle)
    }

    public static func plan(
        for events: [RecordedEvent],
        bundle: SemanticRecordingBundle
    ) -> SemanticRecordingPlayableSanitizationPlan {
        let suppressions = bundle.suppressions
            .filter { $0.reason.redactsSemanticEvidence }
        guard !suppressions.isEmpty else {
            return SemanticRecordingPlayableSanitizationPlan(recordingID: bundle.id)
        }

        let timelineByEventIndex = Dictionary(
            bundle.timelineEvents
                .filter { $0.recordedEventIndex != nil }
                .sorted { lhs, rhs in
                    if lhs.recordingTime == rhs.recordingTime {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.recordingTime < rhs.recordingTime
                }
                .map { ($0.recordedEventIndex ?? 0, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let eventSanitizations: [SemanticRecordingPlayableEventSanitization] = events.enumerated().compactMap { index, event in
            let fields = redactedFields(for: event)
            guard !fields.isEmpty else {
                return nil
            }

            let timelineEvent = timelineByEventIndex[index]
            let matchingSuppressions = suppressions.filter {
                matches($0, event: event, timelineEvent: timelineEvent)
            }
            guard !matchingSuppressions.isEmpty else {
                return nil
            }

            return SemanticRecordingPlayableEventSanitization(
                eventIndex: index,
                eventKind: event.kind,
                recordingTime: event.time,
                timelineEventID: timelineEvent?.id,
                frameID: timelineEvent?.frameID,
                sourceSuppressionIDs: stableSuppressionIDs(matchingSuppressions),
                reasons: stableReasons(matchingSuppressions.map(\.reason)),
                redactedFields: fields,
                fallback: fallback(for: fields)
            )
        }

        return SemanticRecordingPlayableSanitizationPlan(
            recordingID: bundle.id,
            eventSanitizations: eventSanitizations
        )
    }

    private static func redactedFields(
        for event: RecordedEvent
    ) -> [SemanticRecordingPlayableSanitizationField] {
        var fields: [SemanticRecordingPlayableSanitizationField] = []
        if event.unicodeString?.isEmpty == false {
            fields.append(.unicodeString)
        }
        if event.textAnchor?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append(.textAnchorText)
        }
        if event.behaviorGroupName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append(.behaviorGroupName)
        }
        return fields
    }

    private static func matches(
        _ suppression: RecordingSuppressionRecord,
        event: RecordedEvent,
        timelineEvent: RecordingTimelineEvent?
    ) -> Bool {
        if let eventID = suppression.eventID,
           timelineEvent?.id == eventID {
            return true
        }
        if let frameID = suppression.frameID,
           timelineEvent?.frameID == frameID {
            return true
        }
        if let timeRange = suppression.timeRange,
           (timeRange.contains(event.time) || (timelineEvent.map { timeRange.contains($0.recordingTime) } ?? false)) {
            return true
        }
        if let recordingTime = suppression.recordingTime,
           matchesTime(recordingTime, eventTime: event.time, timelineTime: timelineEvent?.recordingTime) {
            return true
        }
        return false
    }

    private static func matchesTime(
        _ suppressionTime: TimeInterval,
        eventTime: TimeInterval,
        timelineTime: TimeInterval?
    ) -> Bool {
        let normalizedSuppressionTime = max(0, suppressionTime)
        if abs(max(0, eventTime) - normalizedSuppressionTime) <= 0.001 {
            return true
        }
        if let timelineTime,
           abs(max(0, timelineTime) - normalizedSuppressionTime) <= 0.001 {
            return true
        }
        return false
    }

    private static func stableSuppressionIDs(
        _ suppressions: [RecordingSuppressionRecord]
    ) -> [UUID] {
        Array(Set(suppressions.map(\.id))).sorted { $0.uuidString < $1.uuidString }
    }

    private static func stableReasons(
        _ reasons: [RecordingSuppressionReason]
    ) -> [RecordingSuppressionReason] {
        var unique: [RecordingSuppressionReason] = []
        for reason in reasons where !unique.contains(reason) {
            unique.append(reason)
        }
        return unique.sorted { $0.rawValue < $1.rawValue }
    }

    private static func fallback(
        for fields: [SemanticRecordingPlayableSanitizationField]
    ) -> String {
        if fields.allSatisfy(\.preservesPlaybackInput) {
            return "Replay can keep using key codes; readable text metadata is withheld."
        }
        return "Keep the original playable macro for execution until a reviewed replacement is accepted."
    }
}

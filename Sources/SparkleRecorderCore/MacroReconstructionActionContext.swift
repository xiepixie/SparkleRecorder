import Foundation

/// AI-facing reconstruction row. It keeps action identity together with the
/// Playback Surface and coordinate evidence needed to understand where the action
/// occurred, so external authors do not have to reconstruct that context by joining
/// several package files and event indices themselves.
public struct MacroReconstructionActionContext: Codable, Equatable, Sendable {
    public var actionID: String
    public var kind: String
    public var sourceEventIndices: [Int]
    public var sourcePlaybackStart: Double
    public var sourcePlaybackEnd: Double
    public var surfaceID: String?
    public var surface: MacroReconstructionSurfaceContext?
    public var startPoint: PointValue?
    public var endPoint: PointValue?
    public var startContentNormalized: PointValue?
    public var endContentNormalized: PointValue?
    public var pointerButton: String?
    public var clickCount: Int?
    public var keyboardLabel: String?
    public var textInputPreview: String?
    public var textInputCharacterCount: Int?
    public var scrollDeltaX: Int64?
    public var scrollDeltaY: Int64?
    public var coordinateBinding: CoordinateBinding?
    public var coordinateStrategy: CoordinateStrategy?
    public var locatorFallbackPolicy: LocatorFallbackPolicy?
    public var textAnchor: TextAnchor?
    public var textTimeout: TimeInterval?
    public var verifyMustExist: Bool?

    public init(
        action: MacroReconstructedAction,
        events: [RecordedEvent],
        surfaces: [String: PlaybackSurface]
    ) {
        self.init(
            action: action,
            events: events,
            surfaceContexts: Dictionary(uniqueKeysWithValues: surfaces.map { id, surface in
                (id, MacroReconstructionSurfaceContext(id: id, surface: surface))
            })
        )
    }

    public init(
        action: MacroReconstructedAction,
        events: [RecordedEvent],
        surfaceContexts: [String: MacroReconstructionSurfaceContext]
    ) {
        actionID = action.id
        kind = action.kind.rawValue
        sourceEventIndices = action.sourceEventIndices
        sourcePlaybackStart = action.startTime
        sourcePlaybackEnd = action.endTime
        surfaceID = action.surfaceID
        surface = action.surfaceID.flatMap { surfaceContexts[$0] }
        startPoint = action.startPoint
        endPoint = action.endPoint

        let firstEvent = action.sourceEventIndices.first.flatMap { index in
            events.indices.contains(index) ? events[index] : nil
        }
        let lastEvent = action.sourceEventIndices.last.flatMap { index in
            events.indices.contains(index) ? events[index] : nil
        }
        startContentNormalized = firstEvent.flatMap(Self.contentNormalizedPoint)
        endContentNormalized = lastEvent.flatMap(Self.contentNormalizedPoint)

        let actionEvents = action.sourceEventIndices.compactMap { index in
            events.indices.contains(index) ? events[index] : nil
        }
        pointerButton = Self.pointerButton(in: actionEvents)
        let mouseDownCount = actionEvents.filter {
            $0.kind == .leftMouseDown || $0.kind == .rightMouseDown || $0.kind == .otherMouseDown
        }.count
        clickCount = mouseDownCount > 0 ? mouseDownCount : nil
        if action.kind == .textInput {
            let text = actionEvents.filter { $0.kind == .keyDown }.compactMap(\.unicodeString).joined()
            textInputCharacterCount = text.isEmpty ? nil : text.count
            textInputPreview = text.isEmpty ? nil : Self.preview(text, maximumCharacters: 120)
            keyboardLabel = nil
        } else {
            keyboardLabel = KeyboardActionPresentation.label(
                kind: action.kind,
                eventIndices: action.sourceEventIndices,
                events: events
            )
            textInputCharacterCount = nil
            textInputPreview = nil
        }
        if action.kind == .scroll {
            scrollDeltaX = actionEvents.reduce(Int64(0)) { $0 + Int64($1.scrollDeltaX) }
            scrollDeltaY = actionEvents.reduce(Int64(0)) { $0 + Int64($1.scrollDeltaY) }
        } else {
            scrollDeltaX = nil
            scrollDeltaY = nil
        }

        let semanticEvent = action.sourceEventIndices.lazy.compactMap { index -> RecordedEvent? in
            guard events.indices.contains(index) else { return nil }
            let event = events[index]
            return event.textAnchor != nil || event.kind == .waitForText || event.kind == .verifyText
                ? event
                : nil
        }.first ?? firstEvent

        coordinateBinding = semanticEvent?.coordinateBinding
        coordinateStrategy = semanticEvent?.coordinateStrategy
        locatorFallbackPolicy = semanticEvent?.locatorFallbackPolicy
        textAnchor = semanticEvent?.textAnchor
        textTimeout = semanticEvent?.textTimeout
        verifyMustExist = semanticEvent?.verifyMustExist
    }

    private static func pointerButton(in events: [RecordedEvent]) -> String? {
        guard let event = events.first(where: { $0.kind.isMouse }) else { return nil }
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return "left"
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return "right"
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return event.mouseButton == 2 ? "middle" : "button\(event.mouseButton)"
        default:
            return nil
        }
    }

    private static func preview(_ text: String, maximumCharacters: Int) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters)) + "…"
    }

    private static func contentNormalizedPoint(_ event: RecordedEvent) -> PointValue? {
        guard let x = event.contentNormalizedX,
              let y = event.contentNormalizedY,
              x.isFinite,
              y.isFinite else {
            return nil
        }
        return PointValue(x: x, y: y)
    }
}

public struct MacroReconstructionActionContextDocument: Codable, Equatable, Sendable {
    public var version: String
    public var sourceRevision: String
    public var actions: [MacroReconstructionActionContext]

    public init(
        version: String = MacroReconstructionContractVersions.actionContext,
        sourceRevision: String,
        actions: [MacroReconstructionActionContext]
    ) {
        self.version = version
        self.sourceRevision = sourceRevision
        self.actions = actions
    }
}

public enum MacroReconstructionActionContextProjector {
    public static func project(
        actions: [MacroReconstructedAction],
        events: [RecordedEvent],
        surfaces: [String: PlaybackSurface]
    ) -> [MacroReconstructionActionContext] {
        actions.map {
            MacroReconstructionActionContext(action: $0, events: events, surfaces: surfaces)
        }
    }

    public static func project(
        actions: [MacroReconstructedAction],
        events: [RecordedEvent],
        surfaceContexts: [String: MacroReconstructionSurfaceContext]
    ) -> [MacroReconstructionActionContext] {
        actions.map {
            MacroReconstructionActionContext(action: $0, events: events, surfaceContexts: surfaceContexts)
        }
    }

    public static func document(
        actions: [MacroReconstructedAction],
        events: [RecordedEvent],
        surfaces: [String: PlaybackSurface],
        sourceRevision: String
    ) -> MacroReconstructionActionContextDocument {
        MacroReconstructionActionContextDocument(
            sourceRevision: sourceRevision,
            actions: project(actions: actions, events: events, surfaces: surfaces)
        )
    }

    public static func document(
        actions: [MacroReconstructedAction],
        events: [RecordedEvent],
        surfaceContexts: [String: MacroReconstructionSurfaceContext],
        sourceRevision: String
    ) -> MacroReconstructionActionContextDocument {
        MacroReconstructionActionContextDocument(
            sourceRevision: sourceRevision,
            actions: project(actions: actions, events: events, surfaceContexts: surfaceContexts)
        )
    }
}

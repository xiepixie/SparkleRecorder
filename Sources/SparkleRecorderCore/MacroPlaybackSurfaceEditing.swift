import Foundation

public enum MacroPlaybackSurfaceEditingError: Error, LocalizedError, Equatable, Sendable {
    case surfaceNotFound(String)
    case surfaceStillReferenced(surfaceID: String, eventCount: Int)
    case invalidEventIndex(Int)

    public var errorDescription: String? {
        switch self {
        case .surfaceNotFound(let id):
            "Playback Surface \(id) does not exist."
        case .surfaceStillReferenced(let id, let count):
            "Playback Surface \(id) is still referenced by \(count) event(s). Reassign those actions before removing it."
        case .invalidEventIndex(let index):
            "Event index \(index) is outside the macro event list."
        }
    }
}

/// Pure editing policy shared by accepted-Macro and Candidate editors. Window
/// identity is edited per surface ID; actions move between surfaces only through an
/// explicit event assignment. No operation silently collapses a multi-surface Macro.
public enum MacroPlaybackSurfaceEditing {
    public static func referenceCounts(in events: [RecordedEvent]) -> [String: Int] {
        events.reduce(into: [:]) { counts, event in
            guard let id = event.surfaceId else { return }
            counts[id, default: 0] += 1
        }
    }

    public static func selectedSurfaceIDs(
        in events: [RecordedEvent],
        eventIndices: some Sequence<Int>
    ) throws -> Set<String> {
        var result = Set<String>()
        for index in eventIndices {
            guard events.indices.contains(index) else {
                throw MacroPlaybackSurfaceEditingError.invalidEventIndex(index)
            }
            if let id = events[index].surfaceId {
                result.insert(id)
            }
        }
        return result
    }

    public static func orderedSurfaceIDs(_ surfaces: [String: PlaybackSurface]) -> [String] {
        surfaces.keys.sorted(by: surfaceIDLessThan)
    }

    /// Resolves the one surface an editor operation may safely target. Explicit
    /// event bindings win. Legacy events may inherit a surface only when the Macro
    /// has exactly one surface; multi-surface Macros never guess the first entry.
    public static func effectiveSurfaceID(
        in events: [RecordedEvent],
        eventIndices: some Sequence<Int>,
        surfaces: [String: PlaybackSurface]
    ) throws -> String? {
        let explicit = try selectedSurfaceIDs(in: events, eventIndices: eventIndices)
        if explicit.count == 1 { return explicit.first }
        if explicit.count > 1 { return nil }
        guard surfaces.count == 1 else { return nil }
        return surfaces.keys.first
    }

    public static func rebind(
        surfaceID: String,
        to surface: PlaybackSurface,
        in surfaces: [String: PlaybackSurface]
    ) throws -> [String: PlaybackSurface] {
        guard surfaces[surfaceID] != nil else {
            throw MacroPlaybackSurfaceEditingError.surfaceNotFound(surfaceID)
        }
        var result = surfaces
        result[surfaceID] = surface
        return result
    }

    public static func add(
        _ surface: PlaybackSurface,
        to surfaces: [String: PlaybackSurface]
    ) -> (surfaces: [String: PlaybackSurface], surfaceID: String) {
        var result = surfaces
        let id = nextSurfaceID(in: result)
        result[id] = surface
        return (result, id)
    }

    public static func remove(
        surfaceID: String,
        from surfaces: [String: PlaybackSurface],
        events: [RecordedEvent]
    ) throws -> [String: PlaybackSurface] {
        guard surfaces[surfaceID] != nil else {
            throw MacroPlaybackSurfaceEditingError.surfaceNotFound(surfaceID)
        }
        let references = referenceCounts(in: events)[surfaceID, default: 0]
        guard references == 0 else {
            throw MacroPlaybackSurfaceEditingError.surfaceStillReferenced(
                surfaceID: surfaceID,
                eventCount: references
            )
        }
        var result = surfaces
        result.removeValue(forKey: surfaceID)
        return result
    }

    public static func assign(
        surfaceID: String,
        toEventIndices eventIndices: some Sequence<Int>,
        in events: [RecordedEvent],
        surfaces: [String: PlaybackSurface]
    ) throws -> [RecordedEvent] {
        guard surfaces[surfaceID] != nil else {
            throw MacroPlaybackSurfaceEditingError.surfaceNotFound(surfaceID)
        }
        var result = events
        for index in eventIndices {
            guard result.indices.contains(index) else {
                throw MacroPlaybackSurfaceEditingError.invalidEventIndex(index)
            }
            result[index].surfaceId = surfaceID
        }
        return result
    }

    private static func nextSurfaceID(in surfaces: [String: PlaybackSurface]) -> String {
        var index = 1
        while surfaces["surface-\(index)"] != nil {
            index += 1
        }
        return "surface-\(index)"
    }

    private static func surfaceIDLessThan(_ lhs: String, _ rhs: String) -> Bool {
        func numericSuffix(_ value: String) -> Int? {
            guard value.hasPrefix("surface-") else { return nil }
            return Int(value.dropFirst("surface-".count))
        }
        switch (numericSuffix(lhs), numericSuffix(rhs)) {
        case let (l?, r?):
            return l == r ? lhs < rhs : l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs < rhs
        }
    }
}

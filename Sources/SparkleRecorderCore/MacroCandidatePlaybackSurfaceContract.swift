import Foundation

/// Describes who is allowed to change Playback Surface identity while a Candidate
/// is normalized. External authoring may choose surface references on events, but
/// the target-window identity itself remains owned by the Source Revision. A local
/// Candidate Draft may replace a surface only through the app's explicit window
/// picker, which supplies a trusted PlaybackSurface.
public enum MacroCandidatePlaybackSurfaceAuthority: String, Codable, Equatable, Sendable {
    case sourceRevision
    case appOwnedRebinding
}

public enum MacroCandidatePlaybackSurfaceViolation: Equatable, Sendable {
    case surfaceSetChanged
    case surfaceChanged(String)
}

public enum MacroCandidatePlaybackSurfaceContract {
    public static func violation(
        candidate: [String: PlaybackSurface],
        source: [String: PlaybackSurface],
        authority: MacroCandidatePlaybackSurfaceAuthority
    ) -> MacroCandidatePlaybackSurfaceViolation? {
        guard authority == .sourceRevision else { return nil }
        // v4 external candidates reference source-owned surfaces by event.surfaceId
        // and normally omit the surface bodies entirely. v3 standalone candidates
        // that still copy them are accepted only when execution identity matches.
        if candidate.isEmpty { return nil }
        guard Set(candidate.keys) == Set(source.keys) else {
            return .surfaceSetChanged
        }
        for id in source.keys.sorted() {
            guard let candidateSurface = candidate[id], let sourceSurface = source[id] else {
                return .surfaceSetChanged
            }
            if !executionContextMatches(candidateSurface, sourceSurface) {
                return .surfaceChanged(id)
            }
        }
        return nil
    }

    private static func executionContextMatches(
        _ lhs: PlaybackSurface,
        _ rhs: PlaybackSurface
    ) -> Bool {
        var left = lhs
        var right = rhs
        let neutralTimestamp = Date(timeIntervalSinceReferenceDate: 0)
        left.capturedAt = neutralTimestamp
        right.capturedAt = neutralTimestamp
        return left == right
    }
}

/// Runtime compatibility for older accepted macros. New Candidates must always
/// provide an explicit surfaceId for text operations, but a legacy macro with
/// exactly one Playback Surface is still unambiguous. Multi-surface playback never
/// guesses an arbitrary first surface for text recognition or coordinate fallback.
public enum PlaybackTextSurfaceSelection {
    public static func resolve(
        event: RecordedEvent,
        surfaces: [String: PlaybackSurface]
    ) -> String? {
        if let explicit = event.surfaceId {
            return surfaces[explicit] == nil ? nil : explicit
        }
        guard surfaces.count == 1 else { return nil }
        return surfaces.keys.first
    }
}

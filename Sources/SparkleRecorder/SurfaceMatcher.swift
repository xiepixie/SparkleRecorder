import CoreGraphics
import Foundation

public final class SurfaceMatcher: Sendable {
    public init() {}
    
    public func match(_ surface: PlaybackSurface, against surfaces: [String: PlaybackSurface]) -> String? {
        scoredMatches(for: surface, against: surfaces).first?.id
    }

    public func scoredMatches(
        for surface: PlaybackSurface,
        against surfaces: [String: PlaybackSurface]
    ) -> [SurfaceMatchScore] {
        let sameAppSurfaceCount = sameAppSurfaceCount(for: surface, in: surfaces)

        return surfaces.keys.sorted().compactMap { id in
            guard let existing = surfaces[id] else { return nil }
            return score(
                id: id,
                existing: existing,
                incoming: surface,
                sameAppSurfaceCount: sameAppSurfaceCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.originDistance != rhs.originDistance { return lhs.originDistance < rhs.originDistance }
            return lhs.id < rhs.id
        }
    }

    private func score(
        id: String,
        existing: PlaybackSurface,
        incoming: PlaybackSurface,
        sameAppSurfaceCount: Int
    ) -> SurfaceMatchScore? {
        guard hasCompatibleAppIdentity(existing: existing, incoming: incoming) else {
            return nil
        }

        let exactWindowID = existing.recordedWindowId != nil
            && incoming.recordedWindowId != nil
            && existing.recordedWindowId == incoming.recordedWindowId
        if existing.recordedWindowId != nil, incoming.recordedWindowId != nil, !exactWindowID {
            return nil
        }

        let exactTitle = existing.windowTitle != nil
            && incoming.windowTitle != nil
            && existing.windowTitle == incoming.windowTitle
        let patternTitle = titleMatchesPattern(existing: existing, incoming: incoming)
        let titleDriftAllowed = !exactTitle
            && !patternTitle
            && sameAppSurfaceCount == 1

        guard exactWindowID || exactTitle || patternTitle || titleDriftAllowed else {
            return nil
        }

        let sizeScore = Self.sizeScore(existing.recordedFrame, incoming.recordedFrame)
        let originDistance = Self.originDistance(existing.recordedFrame, incoming.recordedFrame)

        var score = 100
        if exactWindowID { score += 1_000 }
        if exactTitle { score += 220 }
        if patternTitle { score += 180 }
        if titleDriftAllowed { score += 120 }
        score += sizeScore
        score += Self.originScore(originDistance)

        if existing.recordedDisplayId != nil,
           incoming.recordedDisplayId != nil,
           existing.recordedDisplayId == incoming.recordedDisplayId {
            score += 30
        }

        return SurfaceMatchScore(id: id, score: score, originDistance: originDistance)
    }

    private func hasCompatibleAppIdentity(existing: PlaybackSurface, incoming: PlaybackSurface) -> Bool {
        if let incomingBundle = incoming.bundleIdentifier {
            return existing.bundleIdentifier == incomingBundle
        }

        if let incomingWindowID = incoming.recordedWindowId,
           existing.recordedWindowId == incomingWindowID {
            return true
        }

        if let incomingTitle = incoming.windowTitle,
           existing.windowTitle == incomingTitle {
            return true
        }

        return false
    }

    private func titleMatchesPattern(existing: PlaybackSurface, incoming: PlaybackSurface) -> Bool {
        guard let pattern = existing.windowTitlePattern,
              let title = incoming.windowTitle,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }

    private func sameAppSurfaceCount(
        for incoming: PlaybackSurface,
        in surfaces: [String: PlaybackSurface]
    ) -> Int {
        guard let incomingBundle = incoming.bundleIdentifier else { return 0 }
        return surfaces.values.filter { $0.bundleIdentifier == incomingBundle }.count
    }

    private static func sizeScore(_ lhs: RectValue, _ rhs: RectValue) -> Int {
        let widthDelta = abs(lhs.width - rhs.width)
        let heightDelta = abs(lhs.height - rhs.height)

        switch max(widthDelta, heightDelta) {
        case ...8:
            return 100
        case ...40:
            return 60
        case ...120:
            return 20
        default:
            return 0
        }
    }

    private static func originDistance(_ lhs: RectValue, _ rhs: RectValue) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func originScore(_ distance: CGFloat) -> Int {
        switch distance {
        case ...8:
            return 45
        case ...80:
            return 30
        case ...250:
            return 15
        default:
            return 0
        }
    }
}

public struct SurfaceMatchScore: Equatable, Sendable {
    public var id: String
    public var score: Int
    public var originDistance: CGFloat

    public init(id: String, score: Int, originDistance: CGFloat) {
        self.id = id
        self.score = score
        self.originDistance = originDistance
    }
}

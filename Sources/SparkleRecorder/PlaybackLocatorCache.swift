import CoreGraphics
import Foundation

public enum PlaybackLocatorCacheKey {
    public static func key(for event: RecordedEvent, surfaceId: String) -> String? {
        guard let anchor = event.textAnchor else { return nil }
        return [
            surfaceId,
            anchor.text,
            anchor.matchMode.rawValue,
            rectKey(anchor.observedContentNormalizedFrame ?? anchor.observedFrame),
            rectKey(anchor.searchContentNormalizedRegion ?? anchor.searchRegion),
            pointKey(anchor.coordinateFallbackContentNormalized ?? anchor.coordinateFallback)
        ].joined(separator: "|")
    }

    private static func rectKey(_ rect: RectValue?) -> String {
        guard let rect else { return "-" }
        return String(format: "%.4f,%.4f,%.4f,%.4f", rect.x, rect.y, rect.width, rect.height)
    }

    private static func pointKey(_ point: PointValue?) -> String {
        guard let point else { return "-" }
        return String(format: "%.4f,%.4f", point.x, point.y)
    }
}

public final class PlaybackLocatorCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (loopIndex: Int, key: String, point: CGPoint, eventTime: TimeInterval)?

    public init() {}

    public func point(for key: String?, loopIndex: Int, eventTime: TimeInterval) -> CGPoint? {
        guard let key else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let entry,
              entry.loopIndex == loopIndex,
              entry.key == key,
              abs(eventTime - entry.eventTime) <= 1.0 else {
            return nil
        }
        return entry.point
    }

    public func store(point: CGPoint, for key: String?, loopIndex: Int, eventTime: TimeInterval) {
        guard let key else { return }
        lock.lock()
        entry = (loopIndex, key, point, eventTime)
        lock.unlock()
    }
}

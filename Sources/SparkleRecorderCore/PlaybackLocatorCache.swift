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
            pointKey(anchor.coordinateFallbackContentNormalized ?? anchor.coordinateFallback),
            anchor.occurrenceHint.map(String.init) ?? "-"
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
    private var entry: (loopIndex: Int, key: String, point: CGPoint, eventTime: TimeInterval, gestureButton: Int64?)?

    public init() {}

    public func invalidate() {
        lock.lock()
        entry = nil
        lock.unlock()
    }

    /// A located mouse down pins its target until its matching release. Re-querying
    /// during a long press can move the release to an unrelated control.
    public func point(for key: String?, loopIndex: Int, event: RecordedEvent) -> CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        guard let button = Self.gestureButton(event), !Self.isDown(event.kind),
              let key, let current = entry, current.key == key,
              current.loopIndex == loopIndex, current.gestureButton == button,
              event.time >= current.eventTime else {
            entry = nil
            return nil
        }
        if Self.isUp(event.kind) { entry = nil }
        return current.point
    }

    public func store(point: CGPoint, for key: String?, loopIndex: Int, event: RecordedEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard let key, Self.isDown(event.kind), let button = Self.gestureButton(event) else {
            entry = nil
            return
        }
        entry = (loopIndex, key, point, event.time, button)
    }

    private static func isDown(_ kind: RecordedEvent.Kind) -> Bool {
        kind == .leftMouseDown || kind == .rightMouseDown || kind == .otherMouseDown
    }

    private static func isUp(_ kind: RecordedEvent.Kind) -> Bool {
        kind == .leftMouseUp || kind == .rightMouseUp || kind == .otherMouseUp
    }

    private static func gestureButton(_ event: RecordedEvent) -> Int64? {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: 1
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: event.mouseButton
        default: nil
        }
    }

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
        entry = (loopIndex, key, point, eventTime, nil)
        lock.unlock()
    }
}

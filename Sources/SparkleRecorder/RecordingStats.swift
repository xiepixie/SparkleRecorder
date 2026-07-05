import Foundation

public struct RecordingStats: Equatable, Sendable {
    public static let zero = RecordingStats()

    public var clicks: Int
    public var keys: Int
    public var scrolls: Int
    public var drags: Int

    public init(clicks: Int = 0, keys: Int = 0, scrolls: Int = 0, drags: Int = 0) {
        self.clicks = clicks
        self.keys = keys
        self.scrolls = scrolls
        self.drags = drags
    }

    public static func summarize<S: Sequence>(_ events: S) -> RecordingStats where S.Element == RecordedEvent {
        var stats = RecordingStats.zero
        stats.record(contentsOf: events)
        return stats
    }

    public mutating func record(contentsOf events: some Sequence<RecordedEvent>) {
        for event in events {
            record(event)
        }
    }

    public mutating func record(_ event: RecordedEvent) {
        switch event.kind {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            clicks += 1
        case .keyDown:
            keys += 1
        case .scrollWheel:
            scrolls += 1
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            drags += 1
        default:
            break
        }
    }

    public mutating func merge(_ other: RecordingStats) {
        clicks += other.clicks
        keys += other.keys
        scrolls += other.scrolls
        drags += other.drags
    }
}

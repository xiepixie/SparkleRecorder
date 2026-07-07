import CoreGraphics
import Foundation

public struct EventPosterClient: Sendable {
    public var post: @Sendable (RecordedEvent, CGPoint) -> Void

    public init(post: @escaping @Sendable (RecordedEvent, CGPoint) -> Void) {
        self.post = post
    }

    public static let none = EventPosterClient { _, _ in }
}

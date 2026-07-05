import Foundation

public struct RecordingEngineClient: @unchecked Sendable {
    public var events: @Sendable () -> AsyncStream<RawInputEvent>
    public var start: @Sendable () -> Bool
    public var stop: @Sendable () -> Void
    
    public init(
        events: @escaping @Sendable () -> AsyncStream<RawInputEvent>,
        start: @escaping @Sendable () -> Bool,
        stop: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.start = start
        self.stop = stop
    }
}

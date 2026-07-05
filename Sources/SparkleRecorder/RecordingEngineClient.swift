import CoreGraphics
import Foundation

public struct RawCGEvent: @unchecked Sendable {
    public let type: CGEventType
    public let event: CGEvent
    
    public init(type: CGEventType, event: CGEvent) {
        self.type = type
        self.event = event
    }
}

public struct RecordingEngineClient: @unchecked Sendable {
    public var events: @Sendable () -> AsyncStream<RawCGEvent>
    public var start: @Sendable () -> Void
    public var stop: @Sendable () -> Void
    
    public init(
        events: @escaping @Sendable () -> AsyncStream<RawCGEvent>,
        start: @escaping @Sendable () -> Void,
        stop: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.start = start
        self.stop = stop
    }
}

private final class RawEventContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<RawCGEvent>.Continuation?
    var keepAlive: Any?

    func set(_ continuation: AsyncStream<RawCGEvent>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func yield(_ event: RawCGEvent) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(event)
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

extension RecordingEngineClient {
    public static func live(mask: CGEventMask) -> Self {
        let thread = EventTapThread(mask: mask)
        let continuationBox = RawEventContinuationBox()
        
        final class Adapter: EventTapThreadDelegate, @unchecked Sendable {
            let continuationBox: RawEventContinuationBox

            init(continuationBox: RawEventContinuationBox) {
                self.continuationBox = continuationBox
            }
            
            func eventTapThread(_ thread: EventTapThread, didReceive type: CGEventType, event: CGEvent) {
                continuationBox.yield(RawCGEvent(type: type, event: event))
            }
        }
        
        let adapter = Adapter(continuationBox: continuationBox)
        continuationBox.keepAlive = adapter
        thread.delegate = adapter
        
        return Self(
            events: {
                return AsyncStream { continuation in
                    continuationBox.set(continuation)
                    continuation.onTermination = { @Sendable _ in
                        thread.stop()
                        continuationBox.finish()
                    }
                }
            },
            start: {
                thread.start()
            },
            stop: {
                thread.stop()
                continuationBox.finish()
            }
        )
    }
}

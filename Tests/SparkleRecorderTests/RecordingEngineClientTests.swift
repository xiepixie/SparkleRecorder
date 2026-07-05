import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

private final class RecordingEngineProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var stopCount = 0

    func recordStart() {
        lock.lock()
        startCount += 1
        lock.unlock()
    }

    func recordStop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }

    var snapshot: (starts: Int, stops: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (startCount, stopCount)
    }
}

@Suite("Recording Engine Client Tests")
struct RecordingEngineClientTests {
    @Test("Fake client can feed raw input events without CGEvent")
    func fakeClientFeedsRawInputEventsWithoutCGEvent() async {
        let probe = RecordingEngineProbe()
        let inputs = [
            RawInputEvent(
                kind: .leftMouseDown,
                timestamp: 1_000_000_000,
                location: CGPoint(x: 10, y: 20),
                mouseButton: 0,
                clickCount: 1
            ),
            RawInputEvent(
                kind: .keyDown,
                timestamp: 1_100_000_000,
                location: CGPoint(x: 10, y: 20),
                keyCode: 1,
                unicodeString: "s"
            )
        ]
        let client = RecordingEngineClient(
            events: {
                AsyncStream { continuation in
                    for input in inputs {
                        continuation.yield(input)
                    }
                    continuation.finish()
                }
            },
            start: {
                probe.recordStart()
                return true
            },
            stop: {
                probe.recordStop()
            }
        )

        #expect(client.start())
        var received: [RawInputEvent] = []
        for await input in client.events() {
            received.append(input)
        }
        client.stop()

        #expect(received == inputs)
        #expect(probe.snapshot.starts == 1)
        #expect(probe.snapshot.stops == 1)
    }

    @Test("Fake client can model startup failure")
    func fakeClientCanModelStartupFailure() {
        let probe = RecordingEngineProbe()
        let client = RecordingEngineClient(
            events: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            },
            start: {
                probe.recordStart()
                return false
            },
            stop: {
                probe.recordStop()
            }
        )

        #expect(!client.start())
        client.stop()
        #expect(probe.snapshot.starts == 1)
        #expect(probe.snapshot.stops == 1)
    }
}

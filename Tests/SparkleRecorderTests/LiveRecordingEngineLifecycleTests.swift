import Foundation
import Testing
@testable import SparkleRecorder

private final class ShutdownProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Suite("Live recording engine lifecycle")
struct LiveRecordingEngineLifecycleTests {
    @Test("Concurrent and reentrant stop requests execute shutdown exactly once")
    func concurrentStopRequestsRunOnce() async {
        let gate = RecordingEngineStopGate()
        let probe = ShutdownProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<128 {
                group.addTask {
                    gate.runOnce {
                        probe.increment()
                        _ = gate.runOnce {
                            probe.increment()
                        }
                    }
                }
            }
        }

        #expect(probe.value == 1)
        #expect(!gate.runOnce { probe.increment() })
        #expect(probe.value == 1)
    }

    @Test("Stopping an event tap before startup is harmless and idempotent")
    func stoppingBeforeStartupIsHarmless() {
        let thread = EventTapThread(mask: 0)

        thread.stop()
        thread.stop()
        thread.stop()

        #expect(!thread.startAndWait(timeout: 0.05))
    }
}

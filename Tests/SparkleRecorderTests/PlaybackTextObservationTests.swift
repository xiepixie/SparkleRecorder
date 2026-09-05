import Foundation
import Testing
import os
@testable import SparkleRecorderCore

@Suite("Playback text observation semantics")
struct PlaybackTextObservationTests {
    @Test("Unavailable observation never proves disappearance")
    func unavailableIsNotAbsence() async {
        let timer = OSAllocatedUnfairLock(initialState: 0.0)
        let result = await PlaybackTextObservationEvaluator.wait(
            mustExist: false, timeout: 1, pollInterval: 0.25,
            clock: clock(timer), observe: { .unavailable("capture failed") }
        )
        #expect(result == .unavailable("capture failed"))
        #expect(timer.withLock { $0 } == 1)
    }

    @Test("Valid absence completes disappearance immediately")
    func validAbsence() async {
        let timer = OSAllocatedUnfairLock(initialState: 0.0)
        let result = await PlaybackTextObservationEvaluator.wait(
            mustExist: false, timeout: 1, clock: clock(timer), observe: { .absent }
        )
        #expect(result == .matched)
        #expect(timer.withLock { $0 } == 0)
    }

    @Test("Cancellation does not return success")
    func cancellation() async {
        let result = await PlaybackTextObservationEvaluator.wait(
            mustExist: true, timeout: 1, clock: .immediate(), cancelled: { true }, observe: { .found }
        )
        #expect(result == .cancelled)
    }

    @Test("Invalid timeout cannot spin or succeed")
    func invalidTimeouts() async {
        for timeout in [Double.nan, .infinity, -1, 0] {
            let result = await PlaybackTextObservationEvaluator.wait(
                mustExist: true, timeout: timeout, clock: .immediate(), observe: { .found }
            )
            #expect(result == .invalidPolicy)
        }
    }

    @Test("Observation returning after deadline cannot establish success")
    func lateObservation() async {
        let timer = OSAllocatedUnfairLock(initialState: 0.0)
        let result = await PlaybackTextObservationEvaluator.wait(
            mustExist: true, timeout: 1, clock: clock(timer), observe: {
                timer.withLock { $0 = 2 }
                return .found
            }
        )
        #expect(result == .timedOut)
    }

    @Test("Unavailable sample can recover within the same deadline")
    func transientFailure() async {
        let timer = OSAllocatedUnfairLock(initialState: 0.0)
        let result = await PlaybackTextObservationEvaluator.wait(
            mustExist: true, timeout: 1, pollInterval: 0.25, clock: clock(timer), observe: {
                timer.withLock { $0 == 0 ? .unavailable("temporary") : .found }
            }
        )
        #expect(result == .matched)
    }

    private func clock(_ timer: OSAllocatedUnfairLock<Double>) -> PlaybackClockClient {
        PlaybackClockClient(now: { timer.withLock { $0 } }, sleep: { duration in timer.withLock { $0 += duration } },
            sleepSynchronously: { duration in timer.withLock { $0 += duration } }, spinsUntilTarget: false)
    }
}

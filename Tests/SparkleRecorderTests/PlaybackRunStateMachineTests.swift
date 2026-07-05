import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Run State Machine Tests")
struct PlaybackRunStateMachineTests {
    @Test("Start, progress, and finish update snapshots deterministically")
    func startProgressAndFinishUpdateSnapshots() {
        var machine = PlaybackRunStateMachine()

        let started = machine.start(totalLoops: 3)
        #expect(started == PlaybackRunSnapshot(
            generation: 1,
            isPlaying: true,
            currentLoop: 0,
            totalLoops: 3,
            progress: 0
        ))

        let loop = machine.updateCurrentLoop(2, generation: started.generation)
        #expect(loop?.currentLoop == 2)

        let progress = machine.updateProgress(1.4, generation: started.generation)
        #expect(progress?.progress == 1)

        let finished = machine.finish(generation: started.generation)
        #expect(finished == .idle(generation: started.generation))
    }

    @Test("Stop invalidates stale playback updates")
    func stopInvalidatesStalePlaybackUpdates() {
        var machine = PlaybackRunStateMachine()
        let started = machine.start(totalLoops: 1)
        let stopped = machine.stop()

        #expect(stopped == .idle(generation: 2))
        #expect(machine.updateCurrentLoop(1, generation: started.generation) == nil)
        #expect(machine.updateProgress(0.5, generation: started.generation) == nil)
        #expect(machine.finish(generation: started.generation) == nil)
        #expect(machine.snapshot == stopped)
    }

    @Test("Completion maps cancelled, aborted, and successful runs")
    func completionMapsTerminalOutcomes() {
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 2_000)

        let cancelled = PlaybackRunStateMachine.completion(
            runID: runID,
            startedAt: startedAt,
            duration: 1,
            didAbort: false,
            wasCancelled: true,
            failureEvidence: nil
        )
        #expect(cancelled.didFinishNaturally == false)
        #expect(cancelled.automationCompletion == .cancelled(reason: "Playback cancelled"))

        let failed = PlaybackRunStateMachine.completion(
            runID: runID,
            startedAt: startedAt,
            duration: 2,
            didAbort: true,
            wasCancelled: false,
            failureEvidence: nil
        )
        #expect(failed.didFinishNaturally == false)
        #expect(failed.automationCompletion == .failed(report: RunReport(
            runID: runID,
            startTime: startedAt,
            duration: 2,
            isSuccess: false,
            errorMessage: "Playback aborted"
        )))

        let succeeded = PlaybackRunStateMachine.completion(
            runID: runID,
            startedAt: startedAt,
            duration: 3,
            didAbort: false,
            wasCancelled: false,
            failureEvidence: nil
        )
        #expect(succeeded.didFinishNaturally)
        #expect(succeeded.automationCompletion == .succeeded(report: RunReport(
            runID: runID,
            startTime: startedAt,
            duration: 3,
            isSuccess: true
        )))
    }
}

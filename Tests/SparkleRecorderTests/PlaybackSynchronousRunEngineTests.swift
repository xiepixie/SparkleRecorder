import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Synchronous Run Engine Tests")
struct PlaybackSynchronousRunEngineTests {
    @Test("Synchronous engine runs loops and reports progress")
    func synchronousEngineRunsLoopsAndReportsProgress() {
        let clock = SynchronousManualPlaybackClock()
        let windowContext = SynchronousWindowContextRecorder(resolution: PlaybackSurfaceFrameResolution(
            outerFrame: RectValue(x: 50, y: 60, width: 800, height: 600),
            contentFrame: RectValue(x: 50, y: 90, width: 800, height: 570)
        ))
        let stepRecorder = SynchronousRunStepRecorder(result: .succeeded(.postedInput))
        let callbackRecorder = SynchronousRunCallbackRecorder()
        let events = [
            TestFixtures.clickEvent(time: 0.1, surfaceId: TestFixtures.surfaceId),
            TestFixtures.clickEvent(time: 0.2, surfaceId: TestFixtures.surfaceId)
        ]
        let engine = PlaybackSynchronousRunEngine(
            plan: PlaybackPlanner.plan(events: events, loops: 2, speed: 1),
            context: PlaybackContext(surfaces: [TestFixtures.surfaceId: TestFixtures.surface()]),
            runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            startedClock: clock.now(),
            clock: clock.client,
            windowContext: windowContext.client,
            stepClient: stepRecorder.client,
            waitStrategy: PlaybackWaitStrategy(sleepThreshold: 0, spinLeadTime: 0),
            activationDelay: 0.2,
            progressThrottleInterval: 0
        )

        let result = engine.run(callbacks: callbackRecorder.callbacks)
        let requests = stepRecorder.snapshot()

        #expect(result == PlaybackRunEngineResult(didAbort: false))
        #expect(callbackRecorder.loops() == [1, 2])
        #expect(callbackRecorder.progresses() == [0.5, 1.0, 0.5, 1.0])
        #expect(requests.map(\.loopIndex) == [1, 1, 2, 2])
        #expect(windowContext.requestedSurfaceCounts() == [1, 1])
        #expect(windowContext.activationCount() == 2)
    }

    @Test("Synchronous engine builds failure evidence on step failure")
    func synchronousEngineBuildsFailureEvidenceOnStepFailure() throws {
        let clock = SynchronousManualPlaybackClock()
        let macroID = UUID()
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let stepRecorder = SynchronousRunStepRecorder(results: [
            .succeeded(.postedInput),
            .failed(reason: "sync point missing")
        ])
        let events = [
            TestFixtures.clickEvent(time: 0.1, surfaceId: TestFixtures.surfaceId),
            TestFixtures.clickEvent(time: 0.2, surfaceId: TestFixtures.surfaceId)
        ]
        let engine = PlaybackSynchronousRunEngine(
            plan: PlaybackPlanner.plan(events: events, loops: 3, speed: 1),
            context: TestFixtures.playbackContext(),
            macroID: macroID,
            runID: runID,
            startedAt: startedAt,
            startedClock: clock.now(),
            clock: clock.client,
            stepClient: stepRecorder.client,
            waitStrategy: PlaybackWaitStrategy(sleepThreshold: 0, spinLeadTime: 0),
            activationDelay: 0
        )

        let result = engine.run()
        let evidence = try #require(result.failureEvidence)

        #expect(result.didAbort)
        #expect(evidence.macroID == macroID)
        #expect(evidence.runID == runID)
        #expect(evidence.startTime == startedAt)
        #expect(evidence.failedEventIndex == 1)
        #expect(evidence.errorMessage == "sync point missing")
        #expect(evidence.bundleIdentifier == "com.apple.finder")
        #expect(evidence.windowTitle == "Desktop")
        #expect(stepRecorder.snapshot().count == 2)
    }

    @Test("Synchronous engine aborts before step execution on conflict")
    func synchronousEngineAbortsBeforeStepOnConflict() {
        let clock = SynchronousManualPlaybackClock()
        let stepRecorder = SynchronousRunStepRecorder(result: .succeeded(.postedInput))
        let engine = PlaybackSynchronousRunEngine(
            plan: PlaybackPlanner.plan(
                events: [TestFixtures.clickEvent(time: 0.1)],
                loops: 1,
                speed: 1
            ),
            context: PlaybackContext(),
            runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            startedClock: clock.now(),
            clock: clock.client,
            conflict: PlaybackConflictClient(hasConflict: { true }),
            stepClient: stepRecorder.client,
            waitStrategy: PlaybackWaitStrategy(sleepThreshold: 0, spinLeadTime: 0),
            activationDelay: 0
        )

        let result = engine.run()

        #expect(result == PlaybackRunEngineResult(didAbort: true))
        #expect(stepRecorder.snapshot().isEmpty)
    }

    @Test("Synchronous engine treats continuous plans as no-op")
    func synchronousEngineTreatsContinuousPlansAsNoOp() {
        let clock = SynchronousManualPlaybackClock()
        let stepRecorder = SynchronousRunStepRecorder(result: .succeeded(.postedInput))
        let engine = PlaybackSynchronousRunEngine(
            plan: PlaybackPlanner.plan(
                events: [TestFixtures.clickEvent(time: 0.1)],
                loops: 0,
                speed: 1
            ),
            context: PlaybackContext(),
            runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            startedClock: clock.now(),
            clock: clock.client,
            stepClient: stepRecorder.client
        )

        let result = engine.run()

        #expect(result == PlaybackRunEngineResult(didAbort: false))
        #expect(stepRecorder.snapshot().isEmpty)
    }
}

private final class SynchronousManualPlaybackClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(_ value: TimeInterval = 0) {
        self.value = value
    }

    var client: PlaybackClockClient {
        PlaybackClockClient(
            now: { self.now() },
            sleep: { duration in self.advance(by: duration) },
            sleepSynchronously: { duration in self.advance(by: duration) },
            spinsUntilTarget: false
        )
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    private func advance(by duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        lock.lock()
        value += duration
        lock.unlock()
    }
}

private final class SynchronousWindowContextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let resolution: PlaybackSurfaceFrameResolution
    private var requestedCounts: [Int] = []
    private var activations = 0

    init(resolution: PlaybackSurfaceFrameResolution) {
        self.resolution = resolution
    }

    var client: WindowContextClient {
        WindowContextClient(
            resolveFrameResolutions: { surfaces in
                self.lock.lock()
                self.requestedCounts.append(surfaces.count)
                self.lock.unlock()

                return surfaces.reduce(into: [:]) { resolutions, entry in
                    resolutions[entry.key] = self.resolution
                }
            },
            activateSurface: { _ in
                self.lock.lock()
                self.activations += 1
                self.lock.unlock()
            }
        )
    }

    func requestedSurfaceCounts() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return requestedCounts
    }

    func activationCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return activations
    }
}

private final class SynchronousRunStepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [PlaybackRunStepResult]
    private var requests: [PlaybackRunStepRequest] = []

    init(result: PlaybackRunStepResult) {
        self.results = [result]
    }

    init(results: [PlaybackRunStepResult]) {
        self.results = results
    }

    var client: PlaybackSynchronousRunStepClient {
        PlaybackSynchronousRunStepClient { request in
            self.lock.lock()
            self.requests.append(request)
            let result: PlaybackRunStepResult
            if self.results.count > 1 {
                result = self.results.removeFirst()
            } else {
                result = self.results[0]
            }
            self.lock.unlock()
            return result
        }
    }

    func snapshot() -> [PlaybackRunStepRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class SynchronousRunCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var loopValues: [Int] = []
    private var progressValues: [Double] = []

    var callbacks: PlaybackSynchronousRunEngineCallbacks {
        PlaybackSynchronousRunEngineCallbacks(
            loopStarted: { loop in
                self.lock.lock()
                self.loopValues.append(loop)
                self.lock.unlock()
            },
            progressChanged: { progress in
                self.lock.lock()
                self.progressValues.append(progress)
                self.lock.unlock()
            }
        )
    }

    func loops() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return loopValues
    }

    func progresses() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return progressValues
    }
}

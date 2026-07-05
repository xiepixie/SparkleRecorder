import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Run Engine Tests")
struct PlaybackRunEngineTests {
    @Test("Engine activates windows, refreshes context, runs steps, and reports progress")
    func engineRunsLoopAndReportsProgress() async {
        let clock = ManualPlaybackClock()
        let windowContext = WindowContextRecorder(resolution: PlaybackSurfaceFrameResolution(
            outerFrame: RectValue(x: 50, y: 60, width: 800, height: 600),
            contentFrame: RectValue(x: 50, y: 90, width: 800, height: 570)
        ))
        let stepRecorder = PlaybackRunStepRecorder(result: .succeeded(.postedInput))
        let callbackRecorder = PlaybackRunCallbackRecorder()
        let events = [
            TestFixtures.clickEvent(time: 0.1, surfaceId: TestFixtures.surfaceId),
            TestFixtures.clickEvent(time: 0.2, surfaceId: TestFixtures.surfaceId)
        ]
        let engine = PlaybackRunEngine(
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

        let result = await engine.run(callbacks: callbackRecorder.callbacks)
        let loops = await callbackRecorder.loops()
        let progresses = await callbackRecorder.progresses()
        let requests = await stepRecorder.snapshot()

        #expect(result == PlaybackRunEngineResult(didAbort: false))
        #expect(loops == [1, 2])
        #expect(progresses == [0.5, 1.0, 0.5, 1.0])
        #expect(requests.map(\.loopIndex) == [1, 1, 2, 2])
        #expect(requests.allSatisfy { request in
            request.context.currentSurfaceFrames[TestFixtures.surfaceId] != nil
        })
        #expect(windowContext.requestedSurfaceCounts() == [1, 1])
        #expect(windowContext.activationCount() == 2)
    }

    @Test("Engine refreshes a missing target frame before running a step")
    func engineRefreshesMissingTargetFrameBeforeStep() async {
        let clock = ManualPlaybackClock()
        let windowContext = WindowContextRecorder(
            resolution: PlaybackSurfaceFrameResolution(
                outerFrame: RectValue(x: 10, y: 20, width: 300, height: 200),
                contentFrame: RectValue(x: 10, y: 42, width: 300, height: 178)
            ),
            emptyFirstRefresh: true
        )
        let stepRecorder = PlaybackRunStepRecorder(result: .succeeded(.postedInput))
        let event = TestFixtures.clickEvent(time: 0.1, surfaceId: TestFixtures.surfaceId)
        let engine = PlaybackRunEngine(
            plan: PlaybackPlanner.plan(events: [event], loops: 1, speed: 1),
            context: PlaybackContext(surfaces: [TestFixtures.surfaceId: TestFixtures.surface()]),
            runID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            startedClock: clock.now(),
            clock: clock.client,
            windowContext: windowContext.client,
            stepClient: stepRecorder.client,
            waitStrategy: PlaybackWaitStrategy(sleepThreshold: 0, spinLeadTime: 0),
            activationDelay: 0
        )

        _ = await engine.run()
        let requests = await stepRecorder.snapshot()

        #expect(windowContext.requestedSurfaceCounts() == [1, 1])
        #expect(windowContext.activationCount() == 2)
        #expect(requests.first?.context.currentSurfaceFrames[TestFixtures.surfaceId] == RectValue(
            x: 10,
            y: 20,
            width: 300,
            height: 200
        ))
    }

    @Test("Engine builds failure evidence on step failure and stops")
    func engineBuildsFailureEvidenceOnStepFailure() async throws {
        let clock = ManualPlaybackClock()
        let macroID = UUID()
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let stepRecorder = PlaybackRunStepRecorder(results: [
            .succeeded(.postedInput),
            .failed(reason: "point missing")
        ])
        let events = [
            TestFixtures.clickEvent(time: 0.1, surfaceId: TestFixtures.surfaceId),
            TestFixtures.clickEvent(time: 0.2, surfaceId: TestFixtures.surfaceId)
        ]
        let engine = PlaybackRunEngine(
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

        let result = await engine.run()
        let evidence = try #require(result.failureEvidence)
        let requests = await stepRecorder.snapshot()

        #expect(result.didAbort)
        #expect(evidence.macroID == macroID)
        #expect(evidence.runID == runID)
        #expect(evidence.startTime == startedAt)
        #expect(evidence.failedEventIndex == 1)
        #expect(evidence.errorMessage == "point missing")
        #expect(evidence.bundleIdentifier == "com.apple.finder")
        #expect(evidence.windowTitle == "Desktop")
        #expect(requests.count == 2)
    }

    @Test("Engine aborts before step execution when conflict is reported")
    func engineAbortsBeforeStepOnConflict() async {
        let clock = ManualPlaybackClock()
        let stepRecorder = PlaybackRunStepRecorder(result: .succeeded(.postedInput))
        let engine = PlaybackRunEngine(
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

        let result = await engine.run()
        let requests = await stepRecorder.snapshot()

        #expect(result == PlaybackRunEngineResult(didAbort: true))
        #expect(requests.isEmpty)
    }
}

private final class ManualPlaybackClock: @unchecked Sendable {
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

private final class WindowContextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let resolution: PlaybackSurfaceFrameResolution
    private let emptyFirstRefresh: Bool
    private var requestedCounts: [Int] = []
    private var activations = 0

    init(
        resolution: PlaybackSurfaceFrameResolution,
        emptyFirstRefresh: Bool = false
    ) {
        self.resolution = resolution
        self.emptyFirstRefresh = emptyFirstRefresh
    }

    var client: WindowContextClient {
        WindowContextClient(
            resolveFrameResolutions: { surfaces in
                self.lock.lock()
                self.requestedCounts.append(surfaces.count)
                let shouldReturnEmpty = self.emptyFirstRefresh && self.requestedCounts.count == 1
                self.lock.unlock()

                guard !shouldReturnEmpty else { return [:] }
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

private actor PlaybackRunStepRecorder {
    private var results: [PlaybackRunStepResult]
    private var requests: [PlaybackRunStepRequest] = []

    init(result: PlaybackRunStepResult) {
        self.results = [result]
    }

    init(results: [PlaybackRunStepResult]) {
        self.results = results
    }

    nonisolated var client: PlaybackRunStepClient {
        PlaybackRunStepClient { request in
            await self.record(request)
        }
    }

    private func record(_ request: PlaybackRunStepRequest) -> PlaybackRunStepResult {
        requests.append(request)
        if results.count > 1 {
            return results.removeFirst()
        }
        return results[0]
    }

    func snapshot() -> [PlaybackRunStepRequest] {
        requests
    }
}

private actor PlaybackRunCallbackRecorder {
    private var loopValues: [Int] = []
    private var progressValues: [Double] = []

    nonisolated var callbacks: PlaybackRunEngineCallbacks {
        PlaybackRunEngineCallbacks(
            loopStarted: { loop in
                await self.recordLoop(loop)
            },
            progressChanged: { progress in
                await self.recordProgress(progress)
            }
        )
    }

    private func recordLoop(_ loop: Int) {
        loopValues.append(loop)
    }

    private func recordProgress(_ progress: Double) {
        progressValues.append(progress)
    }

    func loops() -> [Int] {
        loopValues
    }

    func progresses() -> [Double] {
        progressValues
    }
}

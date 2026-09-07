import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Live playback reconstruction adapters")
struct LivePlaybackReconstructionAdapterTests {
    @Test(arguments: [false, true])
    func observationsSeparateUnavailableAbsenceAndCancellation(synchronous: Bool) async {
        for kind in [RecordedEvent.Kind.verifyText, .waitForText] {
            for observation in [PlaybackTextObservation.absent, .unavailable("permission denied")] {
                let state = AdapterFixtureState()
                let adapter = client(synchronous: synchronous, state: state, observation: .init { _, _ in observation })
                var event = event(kind, time: 0)
                event.verifyMustExist = false
                let result = await adapter(request(event))
                if observation == .absent {
                    #expect(result == .succeeded(kind == .verifyText ? .semanticVerificationCompleted : .semanticWaitCompleted))
                } else {
                    guard case .failed = result else { Issue.record("Unavailable observation matched absence"); continue }
                }
                #expect(state.points.isEmpty)
            }
            let state = AdapterFixtureState()
            let adapter = client(synchronous: synchronous, state: state, observation: .init { _, _ in
                state.cancel()
                return .found
            })
            let result = await adapter(request(event(kind, time: 0)))
            guard case .failed(let reason) = result else { Issue.record("Cancellation reported success"); continue }
            #expect(reason.localizedCaseInsensitiveContains("cancel"))
            #expect(state.points.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func longGestureUsesOriginalLocatedPointAndNextClickRelocates(synchronous: Bool) async {
        let state = AdapterFixtureState()
        let adapter = client(synchronous: synchronous, state: state)
        for (kind, time) in [(RecordedEvent.Kind.leftMouseDown, 0.0), (.leftMouseDragged, 5.0), (.leftMouseUp, 9.0)] {
            #expect(await adapter(request(event(kind, time: time))) == .succeeded(.postedInput))
        }
        #expect(state.locates == 1)
        #expect(state.points == Array(repeating: CGPoint(x: 100, y: 100), count: 3))
        #expect(await adapter(request(event(.leftMouseDown, time: 10))) == .succeeded(.postedInput))
        #expect(state.locates == 2)
        #expect(state.points.last == CGPoint(x: 200, y: 200))
    }

    @Test(arguments: [false, true])
    func locatorFailureUsesSharedContentNormalizedFallback(synchronous: Bool) async {
        let state = AdapterFixtureState()
        let adapter = client(
            synchronous: synchronous,
            state: state,
            locator: { _, _, _ in throw VisionDetectorError.textNotMatched }
        )
        var input = event(.leftMouseDown, time: 0)
        input.locatorFallbackPolicy = .allowCoordinateFallback
        input.textAnchor?.coordinateFallbackContentNormalized = PointValue(x: 0.5, y: 0.5)
        var context = PlaybackContext()
        context.surfaces["main"] = TestFixtures.surface(
            recordedFrame: RectValue(x: 100, y: 80, width: 400, height: 320),
            recordedContentFrame: RectValue(x: 100, y: 120, width: 400, height: 280)
        )
        context.currentSurfaceFrames["main"] = RectValue(x: 100, y: 80, width: 400, height: 320)
        context.currentContentFrames["main"] = RectValue(x: 100, y: 120, width: 400, height: 280)

        #expect(await adapter(request(input, context: context)) == .succeeded(.postedInput))
        #expect(state.points == [CGPoint(x: 300, y: 260)])
    }

    @Test(arguments: [false, true])
    func differentOccurrenceAndLoopNeverReuseGesture(synchronous: Bool) async {
        let state = AdapterFixtureState()
        let adapter = client(synchronous: synchronous, state: state)
        _ = await adapter(request(event(.leftMouseDown, time: 0)))
        var other = event(.leftMouseUp, time: 0.1)
        other.textAnchor?.occurrenceHint = 2
        _ = await adapter(request(other))
        #expect(state.locates == 2)
        _ = await adapter(request(event(.leftMouseDown, time: 1)))
        _ = await adapter(request(event(.leftMouseUp, time: 1.1), loop: 2))
        #expect(state.locates == 4)
    }

    private func client(
        synchronous: Bool,
        state: AdapterFixtureState,
        observation: PlaybackTextObservationClient = .init { _, _ in .found },
        locator: (@Sendable (RecordedEvent, PlaybackContext, PlaybackClockClient) async throws -> CGPoint)? = nil
    ) -> @Sendable (PlaybackRunStepRequest) async -> PlaybackRunStepResult {
        let poster = EventPosterClient { _, point in state.post(point) }
        let locatorClient = locator ?? { _, _, _ in state.locate() }
        if synchronous {
            let client = LivePlaybackSynchronousRunStepClient(playbackClock: state.clock, eventPoster: poster,
                textObservationClient: observation, locatorClient: locatorClient, cancelled: { state.cancelled }).makeClient()
            return { client.run($0) }
        }
        return LivePlaybackRunStepClient(playbackClock: state.clock, eventPoster: poster,
            textObservationClient: observation, locatorClient: locatorClient, cancelled: { state.cancelled }).makeClient().run
    }

    private func event(_ kind: RecordedEvent.Kind, time: Double) -> RecordedEvent {
        RecordedEvent(kind: kind, time: time, x: 1, y: 1, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1,
            scrollDeltaY: 0, scrollDeltaX: 0, coordinateStrategy: .locatorOnly, surfaceId: "main",
            textAnchor: TextAnchor(text: "Button", observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10)), textTimeout: 1)
    }

    private func request(_ event: RecordedEvent, loop: Int = 1, context: PlaybackContext = PlaybackContext()) -> PlaybackRunStepRequest {
        PlaybackRunStepRequest(loopIndex: loop,
            step: PlaybackStep(eventIndex: 0, event: event, deltaFromPrevious: 0, scheduledOffset: 0, progress: 0),
            context: context, targetSurfaceId: "main", scheduledTime: 0)
    }
}

private final class AdapterFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double = 0
    private var count = 0
    private var posted: [CGPoint] = []
    private var stopped = false
    var points: [CGPoint] { lock.withLock { posted } }
    var locates: Int { lock.withLock { count } }
    var cancelled: Bool { lock.withLock { stopped } }
    func cancel() { lock.withLock { stopped = true } }
    func post(_ point: CGPoint) { lock.withLock { posted.append(point) } }
    func locate() -> CGPoint { lock.withLock { count += 1; return CGPoint(x: count * 100, y: count * 100) } }
    func advance(_ duration: Double) { lock.withLock { time += duration } }
    var clock: PlaybackClockClient {
        PlaybackClockClient(now: { self.lock.withLock { self.time } }, sleep: { self.advance($0) },
            sleepSynchronously: { self.advance($0) }, spinsUntilTarget: false)
    }
}

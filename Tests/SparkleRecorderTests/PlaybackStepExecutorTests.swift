import CoreGraphics
import os
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Step Executor Tests")
struct PlaybackStepExecutorTests {
    @Test("Executor posts resolved input through injected event client")
    func executorPostsResolvedInput() throws {
        let recorder = PostedEventRecorder()
        let executor = PlaybackStepExecutor(
            eventPoster: EventPosterClient { event, point in
                recorder.append(event: event, point: point)
            }
        )

        var event = RecordedEvent.make(
            .leftMouseDown,
            time: 0.25,
            x: 400,
            y: 500,
            mouseButton: 0,
            clickCount: 1
        )
        event.coordinateBinding = .targetWindow
        event.coordinateStrategy = .windowLocalPreferred
        event.surfaceId = TestFixtures.surfaceId
        event.windowLocalX = 25
        event.windowLocalY = 40

        let context = TestFixtures.playbackContext(
            currentFrame: RectValue(x: 200, y: 300, width: 800, height: 600)
        ).withTitleBarHeight(0)
        let step = PlaybackStep(
            eventIndex: 0,
            event: event,
            deltaFromPrevious: 0.25,
            scheduledOffset: 0.25,
            progress: 1.0
        )

        let outcome = try executor.execute(step, context: context).get()

        #expect(outcome == .posted(CGPoint(x: 225, y: 340)))
        #expect(recorder.snapshot() == [
            PostedEvent(event: event, point: CGPoint(x: 225, y: 340))
        ])
    }

    @Test("Executor skips semantic events without posting input")
    func executorSkipsSemanticEvents() throws {
        let recorder = PostedEventRecorder()
        let executor = PlaybackStepExecutor(
            eventPoster: EventPosterClient { event, point in
                recorder.append(event: event, point: point)
            }
        )
        let event = RecordedEvent.make(.waitForText, time: 1.0)
        let step = PlaybackStep(
            eventIndex: 0,
            event: event,
            deltaFromPrevious: 1.0,
            scheduledOffset: 1.0,
            progress: 1.0
        )

        let outcome = try executor.execute(step, context: PlaybackContext()).get()

        #expect(outcome == .skippedSemanticEvent(.waitForText))
        #expect(recorder.snapshot().isEmpty)
    }

    @Test("Executor fails safely before posting when target frame is missing")
    func executorDoesNotPostWhenPointResolutionFails() {
        let recorder = PostedEventRecorder()
        let executor = PlaybackStepExecutor(
            eventPoster: EventPosterClient { event, point in
                recorder.append(event: event, point: point)
            }
        )

        var event = RecordedEvent.make(.leftMouseDown, time: 0.1)
        event.coordinateBinding = .targetWindow
        event.surfaceId = TestFixtures.surfaceId
        event.windowLocalX = 10
        event.windowLocalY = 20

        let context = PlaybackContext(
            surfaces: [TestFixtures.surfaceId: TestFixtures.surface()],
            currentSurfaceFrames: [:]
        )
        let step = PlaybackStep(
            eventIndex: 0,
            event: event,
            deltaFromPrevious: 0.1,
            scheduledOffset: 0.1,
            progress: 1.0
        )

        switch executor.execute(step, context: context) {
        case .success:
            Issue.record("Expected missing window frame failure")
        case .failure(.pointResolve(.missingWindowFrame(let surfaceId))):
            #expect(surfaceId == TestFixtures.surfaceId)
        case .failure(let error):
            Issue.record("Unexpected executor error: \(error)")
        }
        #expect(recorder.snapshot().isEmpty)
    }
}

private struct PostedEvent: Equatable, Sendable {
    var event: RecordedEvent
    var point: CGPoint
}

private final class PostedEventRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[PostedEvent]>(initialState: [])

    func append(event: RecordedEvent, point: CGPoint) {
        lock.withLock {
            $0.append(PostedEvent(event: event, point: point))
        }
    }

    func snapshot() -> [PostedEvent] {
        lock.withLock { $0 }
    }
}

private extension PlaybackContext {
    func withTitleBarHeight(_ height: CGFloat, surfaceId: String = TestFixtures.surfaceId) -> PlaybackContext {
        var copy = self
        copy.currentTitleBarHeights[surfaceId] = height
        return copy
    }
}

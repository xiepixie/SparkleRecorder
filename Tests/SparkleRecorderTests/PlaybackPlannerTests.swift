import Testing
@testable import SparkleRecorderCore

@Suite("Playback Planner Tests")
struct PlaybackPlannerTests {
    @Test("Planner clamps speed and preserves finite loop count")
    func plannerClampsSpeedAndLoops() {
        let events = TestFixtures.clickPair(downTime: 0.5, upTime: 1.0)

        let slow = PlaybackPlanner.plan(events: events, loops: 3, speed: 0.01)
        #expect(slow.speed == 0.1)
        #expect(slow.loopMode == .finite(3))
        #expect(slow.loopMode.displayLoopCount == 3)

        let fast = PlaybackPlanner.plan(events: events, loops: 0, speed: 99)
        #expect(fast.speed == 10.0)
        #expect(fast.loopMode == .continuous)
        #expect(fast.loopMode.displayLoopCount == 0)
        #expect(fast.loopMode.isContinuous)

        let invalid = PlaybackPlanner.plan(events: events, loops: 1, speed: .nan)
        #expect(invalid.speed == 1.0)
    }

    @Test("Timeline turns event times into scaled deltas")
    func timelineBuildsScaledDeltas() {
        let events = [
            RecordedEvent.make(.mouseMoved, time: 0.4),
            RecordedEvent.make(.leftMouseDown, time: 1.0),
            RecordedEvent.make(.leftMouseUp, time: 0.8)
        ]

        let steps = PlaybackPlanner.timeline(events: events, speed: 2.0)
        #expect(steps.count == 3)
        #expect(abs(steps[0].deltaFromPrevious - 0.2) < 0.0001)
        #expect(abs(steps[1].deltaFromPrevious - 0.3) < 0.0001)
        #expect(steps[2].deltaFromPrevious == 0)
        #expect(abs(steps[1].scheduledOffset - 0.5) < 0.0001)
        #expect(steps[2].scheduledOffset == steps[1].scheduledOffset)
        #expect(steps[1].progress == 1.0)
    }

    @Test("Target surface resolution mirrors player fallback order")
    func targetSurfaceResolution() {
        let surface = TestFixtures.surface(recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        let context = PlaybackContext(surfaces: [TestFixtures.surfaceId: surface])

        var event = RecordedEvent.make(.leftMouseDown, time: 0)
        event.surfaceId = TestFixtures.surfaceId
        #expect(PlaybackPlanner.targetSurfaceId(for: event, context: context) == TestFixtures.surfaceId)

        event.surfaceId = "missing"
        #expect(PlaybackPlanner.targetSurfaceId(for: event, context: context) == TestFixtures.surfaceId)

        let emptyContext = PlaybackContext()
        #expect(PlaybackPlanner.targetSurfaceId(for: event, context: emptyContext) == "missing")
    }
}

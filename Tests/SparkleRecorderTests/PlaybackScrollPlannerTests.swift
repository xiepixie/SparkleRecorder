import CoreGraphics
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Scroll Planner Tests")
struct PlaybackScrollPlannerTests {
    struct PointDeltaCase: Sendable {
        var recorded: Int32
        var payload: CGFloat?
        var expected: Int32
    }

    struct LineDeltaCase: Sendable {
        var recorded: Int32
        var payload: Int32?
        var expected: Int32
    }

    @Test(
        "Point delta uses meaningful payload and falls back to recorded amount",
        arguments: [
            PointDeltaCase(recorded: -12, payload: nil, expected: -12),
            PointDeltaCase(recorded: -12, payload: 0, expected: -12),
            PointDeltaCase(recorded: 18, payload: 0.2, expected: 18),
            PointDeltaCase(recorded: -12, payload: -4.6, expected: -5),
            PointDeltaCase(recorded: 0, payload: 7.0, expected: 7),
            PointDeltaCase(recorded: 3, payload: CGFloat(Int32.max) + 10_000, expected: Int32.max),
        ]
    )
    func pointDeltaUsesMeaningfulPayloadAndFallsBackToRecordedAmount(_ testCase: PointDeltaCase) {
        #expect(
            PlaybackScrollPlanner.effectivePointDelta(recorded: testCase.recorded, payload: testCase.payload)
                == testCase.expected
        )
    }

    @Test(
        "Line delta preserves payload and derives line fallback from recorded points",
        arguments: [
            LineDeltaCase(recorded: -12, payload: nil, expected: -1),
            LineDeltaCase(recorded: 24, payload: nil, expected: 2),
            LineDeltaCase(recorded: 5, payload: nil, expected: 1),
            LineDeltaCase(recorded: -5, payload: nil, expected: -1),
            LineDeltaCase(recorded: 0, payload: nil, expected: 0),
            LineDeltaCase(recorded: -12, payload: -3, expected: -3),
            LineDeltaCase(recorded: -12, payload: 0, expected: -1),
        ]
    )
    func lineDeltaPreservesPayloadAndDerivesFallback(_ testCase: LineDeltaCase) {
        #expect(
            PlaybackScrollPlanner.effectiveLineDelta(recorded: testCase.recorded, payload: testCase.payload)
                == testCase.expected
        )
    }

    @Test("Wheel scroll uses line units when payload is discrete")
    func wheelScrollUsesLineUnitsWhenPayloadIsDiscrete() {
        var wheel = RecordedEvent.make(.scrollWheel, time: 0.1, x: 100, y: 100, scrollDeltaY: -12, scrollDeltaX: 0)
        wheel.scrollPayload = ScrollPayload(
            deltaX: 0,
            deltaY: 0,
            lineDeltaX: 0,
            lineDeltaY: -1,
            phase: 0,
            isContinuous: false
        )

        let spec = PlaybackScrollPlanner.spec(for: wheel)

        #expect(spec.unit == .line)
        #expect(spec.wheelY == -1)
        #expect(spec.wheelX == 0)
        #expect(!spec.isContinuous)
        #expect(spec.phase == nil)
        #expect(spec.momentumPhase == nil)
    }

    @Test("Trackpad scroll uses pixel units and preserves continuous phases")
    func trackpadScrollUsesPixelUnitsAndPreservesContinuousPhases() {
        var trackpad = RecordedEvent.make(.scrollWheel, time: 0.1, x: 100, y: 100, scrollDeltaY: -8, scrollDeltaX: 2)
        trackpad.scrollPayload = ScrollPayload(
            deltaX: 2,
            deltaY: -8,
            lineDeltaX: 1,
            lineDeltaY: -1,
            phase: 1,
            momentumPhase: 3,
            isContinuous: true
        )

        let spec = PlaybackScrollPlanner.spec(for: trackpad)

        #expect(spec.unit == .pixel)
        #expect(spec.wheelY == -8)
        #expect(spec.wheelX == 2)
        #expect(spec.isContinuous)
        #expect(spec.phase == 1)
        #expect(spec.momentumPhase == 3)
    }
}

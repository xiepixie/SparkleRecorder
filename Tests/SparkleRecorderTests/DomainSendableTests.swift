import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Domain Sendable Tests")
struct DomainSendableTests {
    @Test("Core macro values satisfy Sendable boundaries")
    func coreMacroValuesAreSendable() {
        let event = TestFixtures.clickEvent()
        let surface = TestFixtures.surface()
        let macro = SavedMacro(
            name: "Sendable smoke",
            events: [event],
            surfaces: [TestFixtures.surfaceId: surface],
            hotkey: HotkeyBinding(keyCode: 97, name: "F6")
        )
        let action = ActionGroup(
            kind: .click,
            eventIndices: [0],
            startTime: 0.1,
            endTime: 0.2,
            startPoint: CGPoint(x: 120, y: 240),
            summary: "Click"
        )
        let context = TestFixtures.playbackContext(surface: surface)

        assertSendable(event)
        assertSendable(surface)
        assertSendable(macro)
        assertSendable(action)
        assertSendable(context)
        assertSendable(EventGrouper())
        assertSendable(PointResolver())
        assertSendable(PlaybackPlanner.plan(events: [event], loops: 1, speed: 1.0))
        assertSendable(PlaybackWaitStrategy.precise)
        assertSendable(PlaybackWaitStrategy.precise.plan(now: 0, target: 1))
        assertSendable(PlaybackClockClient.immediate())
        assertSendable(EventPosterClient.none)
        assertSendable(PlaybackStepExecutor())
        assertSendable(PlaybackSurfaceFrameResolution(
            outerFrame: RectValue(x: 0, y: 0, width: 100, height: 100),
            contentFrame: RectValue(x: 0, y: 24, width: 100, height: 76)
        ))
        assertSendable(WindowContextClient.none)
        assertSendable(RecordingDragSampler())
        assertSendable(RecordingDragSamplingConfiguration.default)
        assertSendable(RecordingDragSample(location: CGPoint(x: 1, y: 2), time: 0.1))
        assertSendable(PlaybackScrollSpec(unit: .pixel, wheelY: -8, wheelX: 0, isContinuous: true, phase: 1))
        assertSendable(PlaybackInputPlan.mouse(PlaybackMouseSpec(button: .left, buttonNumber: 0, clickState: 1, flags: 0)))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

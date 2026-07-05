import Testing
@testable import SparkleRecorderCore

@Suite("Playback Input Planner Tests")
struct PlaybackInputPlannerTests {
    struct MouseButtonCase: Sendable {
        var kind: RecordedEvent.Kind
        var mouseButton: Int64
        var expectedButton: PlaybackMouseButton
    }

    struct ClickStateCase: Sendable {
        var kind: RecordedEvent.Kind
        var clickCount: Int64
        var expected: Int64?
    }

    @Test("Semantic events do not produce low-level input plans")
    func semanticEventsDoNotProduceLowLevelInputPlans() {
        #expect(PlaybackInputPlanner.plan(for: RecordedEvent.make(.waitForText, time: 0)) == nil)
        #expect(PlaybackInputPlanner.plan(for: RecordedEvent.make(.verifyText, time: 0)) == nil)
    }

    @Test("Keyboard and flags changed events preserve key code and flags")
    func keyboardAndFlagsChangedEventsPreserveKeyCodeAndFlags() {
        let down = RecordedEvent.make(.keyDown, time: 0.1, keyCode: 42, flags: 0x12)
        let up = RecordedEvent.make(.keyUp, time: 0.2, keyCode: 42, flags: 0x34)
        let flags = RecordedEvent.make(.flagsChanged, time: 0.3, keyCode: 58, flags: 0x56)

        #expect(PlaybackInputPlanner.plan(for: down) == .keyboard(
            PlaybackKeyboardSpec(keyCode: 42, keyDown: true, flags: 0x12)
        ))
        #expect(PlaybackInputPlanner.plan(for: up) == .keyboard(
            PlaybackKeyboardSpec(keyCode: 42, keyDown: false, flags: 0x34)
        ))
        #expect(PlaybackInputPlanner.plan(for: flags) == .flagsChanged(
            PlaybackFlagsChangedSpec(keyCode: 58, flags: 0x56)
        ))
    }

    @Test(
        "Mouse button mapping follows recorded kind",
        arguments: [
            MouseButtonCase(kind: .leftMouseDown, mouseButton: 0, expectedButton: .left),
            MouseButtonCase(kind: .leftMouseDragged, mouseButton: 0, expectedButton: .left),
            MouseButtonCase(kind: .rightMouseUp, mouseButton: 1, expectedButton: .right),
            MouseButtonCase(kind: .otherMouseDown, mouseButton: 3, expectedButton: .other(3)),
            MouseButtonCase(kind: .mouseMoved, mouseButton: 0, expectedButton: .left),
        ]
    )
    func mouseButtonMappingFollowsRecordedKind(_ testCase: MouseButtonCase) {
        let event = RecordedEvent.make(testCase.kind, time: 0, mouseButton: testCase.mouseButton)
        let spec = PlaybackInputPlanner.mouseSpec(for: event)

        #expect(spec.button == testCase.expectedButton)
        #expect(spec.buttonNumber == testCase.mouseButton)
    }

    @Test(
        "Click state keeps explicit count and defaults click or drag to one",
        arguments: [
            ClickStateCase(kind: .leftMouseDown, clickCount: 2, expected: 2),
            ClickStateCase(kind: .leftMouseUp, clickCount: 0, expected: 1),
            ClickStateCase(kind: .leftMouseDragged, clickCount: 0, expected: 1),
            ClickStateCase(kind: .rightMouseDragged, clickCount: 3, expected: 3),
            ClickStateCase(kind: .mouseMoved, clickCount: 0, expected: nil),
        ]
    )
    func clickStateKeepsExplicitCountAndDefaultsClickOrDragToOne(_ testCase: ClickStateCase) {
        let event = RecordedEvent.make(testCase.kind, time: 0, clickCount: testCase.clickCount)

        #expect(PlaybackInputPlanner.clickState(for: event) == testCase.expected)
    }

    @Test("Scroll plan delegates to playback scroll planner")
    func scrollPlanDelegatesToPlaybackScrollPlanner() {
        var wheel = RecordedEvent.make(.scrollWheel, time: 0.1, scrollDeltaY: -12, scrollDeltaX: 0)
        wheel.scrollPayload = ScrollPayload(deltaX: 0, deltaY: 0, lineDeltaX: 0, lineDeltaY: -1, phase: 0, isContinuous: false)

        #expect(PlaybackInputPlanner.plan(for: wheel) == .scroll(
            PlaybackScrollSpec(unit: .line, wheelY: -1, wheelX: 0, isContinuous: false)
        ))
    }
}

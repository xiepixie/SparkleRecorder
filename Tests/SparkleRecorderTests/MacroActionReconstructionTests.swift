import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro Action Reconstruction Tests")
struct MacroActionReconstructionTests {
    @Test("Source gestures retain every event and derived wait ranges")
    func gesturesAndWaits() throws {
        let events = [
            event(.leftMouseDown, 0), event(.leftMouseUp, 0.05),
            event(.leftMouseDown, 1), event(.leftMouseDragged, 1.1, x: 50), event(.leftMouseUp, 1.2, x: 60),
            event(.keyDown, 2), event(.keyUp, 2.05),
            event(.keyDown, 3, text: "a"), event(.keyUp, 3.05),
            event(.keyDown, 3.1, text: "b"), event(.keyUp, 3.15),
            event(.scrollWheel, 4), event(.scrollWheel, 4.1)
        ]
        let original = events
        let actions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "revision-1")
        #expect(actions.map(\.kind) == [.click, .wait, .drag, .wait, .keyPress, .wait, .textInput, .wait, .scroll])
        #expect(actions.filter { $0.kind != .wait }.map(\.sourceEventIndices) == [[0, 1], [2, 3, 4], [5, 6], [7, 8, 9, 10], [11, 12]])
        #expect(actions[1].startTime == 0.05)
        #expect(actions[1].endTime == 1)
        #expect(actions.filter { $0.kind == .wait }.allSatisfy { $0.sourceEventIndices.isEmpty && $0.surfaceID == nil })
        #expect(actions[2].startPoint == PointValue(x: 10, y: 20))
        #expect(actions[2].endPoint == PointValue(x: 60, y: 20))
        #expect(actions[0].surfaceID == "surface-a")
        #expect(events == original)
    }

    @Test("Reconstruction identity is reproducible and scoped to the exact revision")
    func stableIdentity() throws {
        let events = [event(.mouseMoved, 0), event(.keyUp, 1)]
        let first = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r:/日本語")
        #expect(first == (try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r:/日本語")))
        let other = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r:/日本語2")
        #expect(Set(first.map(\.id)).isDisjoint(with: other.map(\.id)))
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test("Display name localization and behavior UUID do not become source identity")
    func displayNameIndependentIdentity() throws {
        let groupID = BehaviorGroupID()
        var events = [event(.leftMouseDown, 0), event(.leftMouseUp, 0.05), event(.keyUp, 1)]
        for index in events.indices {
            events[index].behaviorGroupID = groupID
            events[index].behaviorGroupName = "Checkout"
        }
        let first = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r1")
        let replacementID = BehaviorGroupID()
        for index in events.indices {
            events[index].behaviorGroupID = replacementID
            events[index].behaviorGroupName = "结账"
        }
        #expect(first.map(\.kind) == [.click, .wait, .keyPress])
        #expect(first == (try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r1")))
    }

    @Test("Equal-time events retain distinct source identities")
    func equalTimes() throws {
        let actions = try MacroActionReconstructor.reconstruct(events: [event(.keyUp, 0), event(.keyUp, 0)], sourceRevision: "r")
        #expect(actions.map(\.sourceEventIndices) == [[0], [1]])
        #expect(Set(actions.map(\.id)).count == 2)
    }

    @Test("Cross-surface gestures split into raw evidence including unknown surface")
    func crossSurfaceGroups() throws {
        let events = [event(.leftMouseDown, 0), event(.leftMouseDragged, 0.05, x: 40, surface: "surface-b"), event(.leftMouseUp, 0.1, x: 50, surface: nil)]
        let actions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r")
        #expect(actions.map(\.sourceEventIndices) == [[0], [1], [2]])
        #expect(actions.map(\.kind) == [.click, .drag, .click])
        #expect(actions.map(\.surfaceID) == ["surface-a", "surface-b", nil])
        #expect(actions.allSatisfy { $0.startTime == $0.endTime })
        #expect(actions[1].startPoint == PointValue(x: 40, y: 20))
    }

    @Test("Unpaired input and interleaved shortcuts preserve exactly-once coverage")
    func interruptedAndUnpairedInput() throws {
        var command = event(.keyDown, 0)
        command.flags = ModFlag.command
        let events = [command, event(.mouseMoved, 0.05), event(.leftMouseUp, 0.1), event(.keyUp, 0.15), event(.leftMouseDown, 1)]
        let actions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r")
        #expect(actions.filter { $0.kind != .wait }.flatMap(\.sourceEventIndices) == [0, 1, 2, 3, 4])
        #expect(actions.last?.sourceEventIndices == [4])
        #expect(actions.last?.startTime == actions.last?.endTime)
    }

    @Test("Every supported source event kind retains its source index")
    func allEventKinds() throws {
        let kinds: [RecordedEvent.Kind] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved, .keyDown, .keyUp, .flagsChanged, .scrollWheel, .waitForText, .verifyText]
        let events = kinds.enumerated().map { event($0.element, Double($0.offset)) }
        let actions = try MacroActionReconstructor.reconstruct(events: events, sourceRevision: "r")
        #expect(actions.filter { $0.kind != .wait }.flatMap(\.sourceEventIndices) == Array(events.indices))
    }

    @Test("Invalid or backward source timestamps are rejected", arguments: [-1.0, Double.nan, Double.infinity, -Double.infinity])
    func invalidTimes(time: Double) {
        #expect(throws: (any Error).self) {
            try MacroActionReconstructor.reconstruct(events: [event(.keyUp, time)], sourceRevision: "r")
        }
    }

    @Test("Revision is required even for an empty source and descending times fail")
    func invalidRevisionAndOrder() throws {
        #expect(throws: (any Error).self) {
            try MacroActionReconstructor.reconstruct(events: [], sourceRevision: "")
        }
        #expect(throws: (any Error).self) {
            try MacroActionReconstructor.reconstruct(events: [event(.keyUp, 1), event(.keyUp, 0)], sourceRevision: "r")
        }
        #expect(try MacroActionReconstructor.reconstruct(events: [], sourceRevision: "r") == [])
    }

    @Test("Unsafe mouse coordinates fail before grouper integer formatting", arguments: [Double.nan, Double.infinity, -Double.infinity])
    func unsafeCoordinates(value: Double) {
        #expect(throws: (any Error).self) {
            try MacroActionReconstructor.reconstruct(events: [event(.mouseMoved, 0, x: value)], sourceRevision: "r")
        }
    }

    @Test("Overflow-risk scroll values retain raw source evidence and derived waits")
    func scrollOverflow() throws {
        var first = event(.scrollWheel, 0)
        first.scrollDeltaY = .max
        var second = event(.scrollWheel, 0.1)
        second.scrollDeltaY = 1
        let burst = try MacroActionReconstructor.reconstruct(events: [first, second], sourceRevision: "r")
        #expect(burst.map(\.sourceEventIndices) == [[0], [1]])
        second.time = 0.3
        let segment = try MacroActionReconstructor.reconstruct(events: [first, second], sourceRevision: "r")
        #expect(segment.map(\.kind) == [.scroll, .wait, .scroll])
        #expect(segment.flatMap(\.sourceEventIndices) == [0, 1])
        second.time = 1
        let actions = try MacroActionReconstructor.reconstruct(events: [first, second], sourceRevision: "r")
        #expect(actions.map(\.kind) == [.scroll, .wait, .scroll])
    }

    @Test("Finite coordinates outside integer range remain raw source evidence")
    func largeFiniteCoordinates() throws {
        let actions = try MacroActionReconstructor.reconstruct(
            events: [event(.mouseMoved, 0, x: .greatestFiniteMagnitude)], sourceRevision: "r")
        #expect(actions.map(\.sourceEventIndices) == [[0]])
        #expect(actions.first?.startPoint?.x == .greatestFiniteMagnitude)
    }

    @Test("Splitting a cross-surface scroll segment restores the source gap")
    func crossSurfaceScrollGap() throws {
        let actions = try MacroActionReconstructor.reconstruct(events: [
            event(.scrollWheel, 0), event(.scrollWheel, 0.3, surface: "surface-b")
        ], sourceRevision: "r")
        #expect(actions.map(\.kind) == [.scroll, .wait, .scroll])
        #expect(actions.map(\.sourceEventIndices) == [[0], [], [1]])
        #expect(actions[1].startTime == 0)
        #expect(actions[1].endTime == 0.3)
    }

    @Test("Unrepresentable merged click counts retain singleton source evidence")
    func overflowingClickCount() throws {
        var first = event(.leftMouseDown, 0)
        first.clickCount = .max
        let actions = try MacroActionReconstructor.reconstruct(events: [
            first, event(.leftMouseUp, 0.01), event(.leftMouseDown, 0.02), event(.leftMouseUp, 0.03)
        ], sourceRevision: "r")
        #expect(actions.map(\.sourceEventIndices) == [[0], [1], [2], [3]])
    }

    @Test("A pointer interruption of a shortcut retains pointer geometry")
    func shortcutPointerGeometry() throws {
        var key = event(.keyDown, 0)
        key.flags = ModFlag.command
        let actions = try MacroActionReconstructor.reconstruct(events: [
            key, event(.mouseMoved, 0.05, x: 55)
        ], sourceRevision: "r")
        #expect(actions.map(\.kind) == [.keyPress, .mouseMove])
        #expect(actions.map(\.sourceEventIndices) == [[0], [1]])
        #expect(actions.last?.startPoint == PointValue(x: 55, y: 20))
    }

    @Test("Merged scroll endpoint corresponds to its last source timestamp")
    func scrollSourceEndpoint() throws {
        let actions = try MacroActionReconstructor.reconstruct(events: [
            event(.scrollWheel, 0, x: 10), event(.scrollWheel, 0.3, x: 20), event(.scrollWheel, 0.4, x: 30)
        ], sourceRevision: "r")
        #expect(actions.map(\.kind) == [.scroll])
        #expect(actions.first?.endTime == 0.4)
        #expect(actions.first?.endPoint == PointValue(x: 30, y: 20))
    }

    private func event(_ kind: RecordedEvent.Kind, _ time: Double, x: CGFloat = 10, text: String? = nil, surface: String? = "surface-a") -> RecordedEvent {
        RecordedEvent(kind: kind, time: time, x: x, y: 20, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 1, scrollDeltaX: 0, surfaceId: surface, unicodeString: text)
    }
}

import Testing
import Foundation
@testable import SparkleRecorderCore

/// Tests that `reorderGroup` never produces event interleaving that causes the
/// `EventGrouper` to misclassify actions (e.g. two clicks becoming a drag).
@Suite("Macro Reorder Interleaving Tests")
struct MacroReorderInterleavingTests {

    // MARK: - Helpers

    private func click(at point: (Double, Double), time: TimeInterval, button: Int64 = 0) -> [RecordedEvent] {
        [
            RecordedEvent(
                kind: .leftMouseDown, time: time, x: point.0, y: point.1,
                keyCode: 0, flags: 0, mouseButton: button, clickCount: 1,
                scrollDeltaY: 0, scrollDeltaX: 0
            ),
            RecordedEvent(
                kind: .leftMouseUp, time: time + 0.05, x: point.0, y: point.1,
                keyCode: 0, flags: 0, mouseButton: button, clickCount: 1,
                scrollDeltaY: 0, scrollDeltaX: 0
            ),
        ]
    }

    private func keyPress(char: String, time: TimeInterval) -> [RecordedEvent] {
        var down = RecordedEvent(
            kind: .keyDown, time: time, x: 0, y: 0,
            keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0,
            scrollDeltaY: 0, scrollDeltaX: 0
        )
        down.unicodeString = char
        var up = RecordedEvent(
            kind: .keyUp, time: time + 0.03, x: 0, y: 0,
            keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0,
            scrollDeltaY: 0, scrollDeltaX: 0
        )
        up.unicodeString = char
        return [down, up]
    }

    // MARK: - Two click swap

    @Test("Swapping two distant clicks preserves click kinds")
    func swapTwoClicks() {
        var events: [RecordedEvent] = []
        events += click(at: (100, 100), time: 1.0)   // Click A
        events += click(at: (500, 500), time: 3.0)    // Click B  (2s gap)

        let before = EventGrouper().group(events, liveDuration: 4.0)
        let clicksBefore = before.filter { $0.kind == .click }
        #expect(clicksBefore.count == 2, "Precondition: two clicks before reorder")

        // Move Click B before Click A
        let groupB = before.first { $0.kind == .click && $0.startPoint == CGPoint(x: 500, y: 500) }!
        events.reorderGroup(sourceEventIndices: groupB.eventIndices, beforeEventIndex: 0)

        let after = EventGrouper().group(events, liveDuration: 4.0)
        let clicksAfter = after.filter { $0.kind == .click }
        let drags = after.filter { $0.kind == .drag }

        #expect(drags.isEmpty, "Swap must not create a drag action")
        #expect(clicksAfter.count == 2, "Both actions must remain clicks after swap")

        // Verify order actually swapped: first click should now be at (500,500)
        #expect(clicksAfter[0].startPoint == CGPoint(x: 500, y: 500))
        #expect(clicksAfter[1].startPoint == CGPoint(x: 100, y: 100))
    }

    // MARK: - Click + KeyPress swap

    @Test("Swapping click and key press preserves both kinds")
    func swapClickAndKey() {
        var events: [RecordedEvent] = []
        events += click(at: (200, 300), time: 1.0)    // Click
        events += keyPress(char: "A", time: 3.0)       // Key (2s gap)

        let before = EventGrouper().group(events, liveDuration: 4.0)
        #expect(before.contains { $0.kind == .click })
        #expect(before.contains { $0.kind == .keyPress })

        // Move key press before click
        let keyGroup = before.first { $0.kind == .keyPress }!
        events.reorderGroup(sourceEventIndices: keyGroup.eventIndices, beforeEventIndex: 0)

        let after = EventGrouper().group(events, liveDuration: 4.0)
        let drags = after.filter { $0.kind == .drag }
        #expect(drags.isEmpty, "Swap must not create a drag")
        #expect(after.contains { $0.kind == .click }, "Click must survive")
        #expect(after.contains { $0.kind == .keyPress }, "Key press must survive")

        // Key press must now come first
        let nonWait = after.filter { $0.kind != .wait }
        #expect(nonWait.first?.kind == .keyPress)
    }

    // MARK: - Three-group rotation

    @Test("Moving last group to first position preserves all action kinds")
    func moveLastToFirst() {
        var events: [RecordedEvent] = []
        events += click(at: (100, 100), time: 1.0)    // A
        events += click(at: (300, 300), time: 3.0)     // B  (2s gap)
        events += click(at: (500, 500), time: 6.0)     // C  (3s gap)

        let before = EventGrouper().group(events, liveDuration: 7.0)
        let clicksBefore = before.filter { $0.kind == .click }
        #expect(clicksBefore.count == 3)

        // Move C to before A
        let groupC = clicksBefore.last!
        events.reorderGroup(sourceEventIndices: groupC.eventIndices, beforeEventIndex: 0)

        let after = EventGrouper().group(events, liveDuration: 7.0)
        let clicksAfter = after.filter { $0.kind == .click }
        let drags = after.filter { $0.kind == .drag }

        #expect(drags.isEmpty, "Move must not create drags")
        #expect(clicksAfter.count == 3, "All three clicks must survive")
        #expect(clicksAfter[0].startPoint == CGPoint(x: 500, y: 500), "C should be first")
    }

    // MARK: - Multi-group block move

    @Test("Moving a block of two clicks preserves all action kinds")
    func moveBlockOfTwo() {
        var events: [RecordedEvent] = []
        events += click(at: (100, 100), time: 1.0)    // A
        events += click(at: (200, 200), time: 1.3)     // B  (0.25s gap, close)
        events += click(at: (500, 500), time: 4.0)     // C  (2.7s gap)

        let before = EventGrouper().group(events, liveDuration: 5.0)
        let nonWait = before.filter { $0.kind != .wait }

        // Move {A, B} after C
        let sourceIndices = nonWait[0].eventIndices + nonWait[1].eventIndices
        events.reorderGroup(sourceEventIndices: sourceIndices, beforeEventIndex: nil)

        let after = EventGrouper().group(events, liveDuration: 5.0)
        let clicksAfter = after.filter { $0.kind == .click }
        let drags = after.filter { $0.kind == .drag }
        let multiPoints = after.filter { $0.kind == .multiPointClick }

        #expect(drags.isEmpty, "Block move must not create drags")
        #expect(clicksAfter.count + multiPoints.count >= 2,
                "Original click actions must not collapse into fewer groups")
        // C should now be first
        let firstAction = after.first { $0.kind != .wait }
        #expect(firstAction?.startPoint == CGPoint(x: 500, y: 500), "C should be first after move")
    }

    // MARK: - Timing gap preservation

    @Test("Swap preserves a meaningful gap between actions")
    func swapPreservesGap() {
        var events: [RecordedEvent] = []
        events += click(at: (100, 100), time: 1.0)
        events += click(at: (500, 500), time: 3.0)  // 2s gap

        let groupB = EventGrouper().group(events, liveDuration: 4.0)
            .first { $0.startPoint == CGPoint(x: 500, y: 500) }!
        events.reorderGroup(sourceEventIndices: groupB.eventIndices, beforeEventIndex: 0)

        let after = EventGrouper().group(events, liveDuration: 4.0)
        let nonWait = after.filter { $0.kind != .wait }
        #expect(nonWait.count == 2)

        // The gap between the two actions must be > multiPointClickGap (0.12s)
        // to prevent incorrect merging.
        let gap = nonWait[1].startTime - nonWait[0].endTime
        #expect(gap > 0.12, "Gap after reorder (\(gap)s) must exceed multiPointClickGap to prevent mis-merging")
    }
}

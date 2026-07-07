import Testing
import Foundation
@testable import SparkleRecorderCore

@Suite struct MacroReorderBugWaitTests {
    @Test func testDuplicatedSequenceWithInternalWaitReordering() throws {
        var events: [RecordedEvent] = []
        let idA = BehaviorGroupID()
        
        var ev1 = RecordedEvent(
            kind: .keyDown, time: 1.0, x: 0, y: 0, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev1.behaviorGroupID = idA
        events.append(ev1)
        
        var ev2 = RecordedEvent(
            kind: .leftMouseDown, time: 3.0, x: 100, y: 100, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev2.behaviorGroupID = idA
        events.append(ev2)
        
        var ev3 = RecordedEvent(
            kind: .leftMouseUp, time: 3.1, x: 100, y: 100, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev3.behaviorGroupID = idA
        events.append(ev3)
        
        let initialGroups = EventGrouper().group(events, liveDuration: 6.0)
        for (i, g) in initialGroups.enumerated() {
            print("[\(i)] kind: \(g.kind) behavior: \(String(describing: g.behaviorGroupID)) events: \(g.eventIndices) time: \(g.startTime) to \(g.endTime)")
        }
        #expect(initialGroups.count == 2) // Sequence(A), Wait
    }
}

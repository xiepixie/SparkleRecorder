import Testing
import Foundation
@testable import SparkleRecorderCore

@Suite struct MacroReorderBugTests {
    @Test func testDuplicatedSequenceReordering() throws {
        var events: [RecordedEvent] = []
        let idA = BehaviorGroupID()
        print("idA = \(idA)")
        
        var ev1 = RecordedEvent(
            kind: .leftMouseDown, time: 1.0, x: 0, y: 0, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev1.behaviorGroupID = idA
        ev1.behaviorGroupName = "Test Action"
        events.append(ev1)
        
        var ev2 = RecordedEvent(
            kind: .leftMouseUp, time: 1.5, x: 100, y: 100, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev2.behaviorGroupID = idA
        ev2.behaviorGroupName = "Test Action"
        events.append(ev2)
        
        var ev3 = RecordedEvent(
            kind: .keyDown, time: 1.6, x: 100, y: 100, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0
        )
        ev3.behaviorGroupID = idA
        ev3.behaviorGroupName = "Test Action"
        ev3.unicodeString = "A"
        events.append(ev3)
        
        // Add a random unrelated click at 5.0
        events.append(RecordedEvent(
            kind: .leftMouseDown, time: 5.0, x: 200, y: 200, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        ))
        events.append(RecordedEvent(
            kind: .leftMouseUp, time: 5.1, x: 200, y: 200, keyCode: 0,
            flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0
        ))
        
        // Group before copy
        let initialGroups = EventGrouper().group(events, liveDuration: 6.0)
        
        // Duplicate the Sequence
        events.duplicateEvents(at: [0, 1, 2])
        
        // Group after copy
        let copiedGroups = EventGrouper().group(events, liveDuration: 10.0)
        
        // Now MOVE Sequence(B) before Sequence(A)
        let seqB = copiedGroups[1] // Sequence(B)
        print("Sequence B ID: \(String(describing: seqB.behaviorGroupID))")
        events.reorderGroup(sourceEventIndices: seqB.eventIndices, beforeEventIndex: 0)
        
        // Group after move
        let finalGroups = EventGrouper().group(events, liveDuration: 10.0)
        for (i, g) in finalGroups.enumerated() {
            print("[\(i)] kind: \(g.kind) behavior: \(String(describing: g.behaviorGroupID)) events: \(g.eventIndices) time: \(g.startTime) to \(g.endTime)")
        }
        
        let sequences = finalGroups.filter { $0.kind == .sequence }
        #expect(sequences.count == 2)
    }
}

import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro Transformer Timing Tests")
struct MacroTransformerTimingTests {
    @Test("Wait text conversion applies as playable text click events")
    func waitTextConversionAppliesAsPlayableTextClickEvents() throws {
        var wait = RecordedEvent.make(.waitForText, time: 1.0)
        wait.textAnchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24)
        )
        wait.textTimeout = 7.0
        wait.locatorFallbackPolicy = .allowCoordinateFallback
        wait.surfaceId = "checkout"
        let next = RecordedEvent.make(.keyDown, time: 1.05, keyCode: 36)
        var events = [wait, next]
        var liveDuration = 1.2
        let waitGroup = try #require(EventGrouper().group(events, liveDuration: liveDuration).first)

        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: waitGroup,
            events: events,
            liveDuration: liveDuration
        )
        events.applyTextClickConversionPlan(plan)
        if let convertedDuration = plan.liveDurationAfterConversion {
            liveDuration = convertedDuration
        }

        #expect(events.map(\.kind) == [.leftMouseDown, .leftMouseUp, .keyDown])
        #expect(events.map(\.coordinateStrategy) == [.locatorOnly, .locatorOnly, nil])
        #expect(events[0].textAnchor?.text == "Confirm")
        #expect(events[0].textAnchor?.coordinateFallback == PointValue(x: 130, y: 102))
        #expect(events[0].textTimeout == 7.0)
        #expect(events[0].locatorFallbackPolicy == .allowCoordinateFallback)
        #expect(events[0].surfaceId == "checkout")
        #expect(abs(events[2].time - 1.1) < 0.000_001)
        #expect(abs(liveDuration - 1.25) < 0.000_001)

        let groups = EventGrouper().group(events, liveDuration: liveDuration)
        let click = try #require(groups.first)
        #expect(click.kind == .click)
        #expect(click.summary == "Click text: Confirm")
        #expect(click.textTargetReadiness == .ready)
        #expect(!groups.contains { $0.kind == .waitForText })
    }

    @Test("Live duration stretch preserves trailing wait beyond last event")
    func liveDurationStretchPreservesTrailingWaitBeyondLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 0.5)

        #expect(abs(stretched - 1.0) < 0.000_001)
    }

    @Test("Live duration stretch never falls behind scaled last event")
    func liveDurationStretchNeverFallsBehindScaledLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 3.0, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 2.0)

        #expect(abs(stretched - 6.0) < 0.000_001)
    }

    @Test("Shifting selected actions extends live duration when needed")
    func shiftingSelectedActionsExtendsLiveDurationWhenNeeded() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]

        let shiftedLater = events.liveDurationAfterShifting(
            1.0,
            indices: IndexSet([1]),
            by: 0.5
        )
        let shiftedEarlier = events.liveDurationAfterShifting(
            3.0,
            indices: IndexSet([0, 1]),
            by: -0.5
        )

        #expect(abs(shiftedLater - 1.5) < 0.000_001)
        #expect(abs(shiftedEarlier - 3.0) < 0.000_001)
    }

    @Test("Earlier shift delta clamps as one block at timeline start")
    func earlierShiftDeltaClampsAsOneBlockAtTimelineStart() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]

        let clampedDelta = events.shiftDeltaClampedToTimelineStart(
            indices: IndexSet([0, 1]),
            by: -0.5
        )

        #expect(abs(clampedDelta + 0.2) < 0.000_001)
    }

    @Test("Time shift plan preserves grouped action spacing at timeline start")
    func timeShiftPlanPreservesGroupedActionSpacingAtTimelineStart() {
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]
        let indices = IndexSet([0, 1])

        let plan = events.timeShiftPlan(
            liveDuration: 1.5,
            indices: indices,
            requestedDelta: -0.5
        )
        events.shiftTime(of: indices, by: plan.delta)

        #expect(plan.canApply)
        #expect(abs(plan.delta + 0.2) < 0.000_001)
        #expect(abs(plan.liveDurationAfterShift - 1.5) < 0.000_001)
        #expect(abs(events[0].time - 0.0) < 0.000_001)
        #expect(abs(events[1].time - 0.3) < 0.000_001)
    }

    @Test("Time shift plan extends live duration for edits past timeline end")
    func timeShiftPlanExtendsLiveDurationForEditsPastTimelineEnd() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 0.6, keyCode: 36)
        ]

        let plan = events.timeShiftPlan(
            liveDuration: 0.6,
            indices: IndexSet([2]),
            requestedDelta: 0.5
        )

        #expect(plan.canApply)
        #expect(abs(plan.delta - 0.5) < 0.000_001)
        #expect(abs(plan.liveDurationAfterShift - 1.1) < 0.000_001)
    }

    @Test("Macro edit mutation snapshot ignores no-op edits")
    func macroEditMutationSnapshotIgnoresNoOpEdits() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]
        let baseline = MacroEditMutationSnapshot(events: events, liveDuration: 0.5)
        let same = MacroEditMutationSnapshot(events: events, liveDuration: 0.5)
        let retimed = MacroEditMutationSnapshot(
            events: [
                RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
                RecordedEvent.make(.leftMouseUp, time: 0.2, x: 10, y: 10)
            ],
            liveDuration: 0.5
        )
        let extended = MacroEditMutationSnapshot(events: events, liveDuration: 0.8)

        #expect(!same.differs(from: baseline))
        #expect(retimed.differs(from: baseline))
        #expect(extended.differs(from: baseline))
    }

    @Test("Click type conversion preserves duration around long press edits")
    func clickTypeConversionPreservesDurationAroundLongPressEdits() {
        var clickEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]
        let clickPreviousLastEventTime = clickEvents.last?.time

        clickEvents.convertClickType(at: [0, 1], from: .click, to: .longPress)
        let longPressDuration = clickEvents.liveDurationPreservingTrailingWait(
            previousLiveDuration: 0.1,
            previousLastEventTime: clickPreviousLastEventTime
        )

        #expect(clickEvents.allSatisfy { $0.clickCount == 1 })
        #expect(abs(clickEvents[1].time - 1.0) < 0.000_001)
        #expect(abs(longPressDuration - 1.0) < 0.000_001)

        var longPressEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        let longPressPreviousLastEventTime = longPressEvents.last?.time

        longPressEvents.convertClickType(at: [0, 1], from: .longPress, to: .click)
        let clickDuration = longPressEvents.liveDurationPreservingTrailingWait(
            previousLiveDuration: 2.0,
            previousLastEventTime: longPressPreviousLastEventTime
        )

        #expect(longPressEvents.allSatisfy { $0.clickCount == 1 })
        #expect(abs(longPressEvents[1].time - 0.1) < 0.000_001)
        #expect(abs(clickDuration - 1.1) < 0.000_001)

        var doubleClickEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        doubleClickEvents.convertClickType(at: [0, 1], from: .longPress, to: .doubleClick)

        #expect(doubleClickEvents.allSatisfy { $0.clickCount == 2 })
        #expect(abs(doubleClickEvents[1].time - 0.1) < 0.000_001)

        var repeatedClickEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        repeatedClickEvents.convertClickType(at: [0, 1], from: .longPress, to: .repeatedClick)

        #expect(repeatedClickEvents.allSatisfy { $0.clickCount == 3 })
        #expect(abs(repeatedClickEvents[1].time - 0.1) < 0.000_001)
    }

    @Test("Inserted actions preserve trailing wait in live duration")
    func insertedActionsPreserveTrailingWaitInLiveDuration() {
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        let previousLastEventTime = events.last?.time

        events.insertClick(at: events.count)
        let liveDuration = events.liveDurationPreservingTrailingWait(
            previousLiveDuration: 3.0,
            previousLastEventTime: previousLastEventTime
        )

        #expect(abs(liveDuration - 3.2) < 0.000_001)
    }

    @Test("Inserted actions never keep stale live duration behind last event")
    func insertedActionsNeverKeepStaleLiveDurationBehindLastEvent() {
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        let previousLastEventTime = events.last?.time

        events.insertClick(at: events.count)
        let liveDuration = events.liveDurationPreservingTrailingWait(
            previousLiveDuration: 0.5,
            previousLastEventTime: previousLastEventTime
        )

        #expect(abs(liveDuration - 1.2) < 0.000_001)
    }

    @Test("First inserted action does not inherit empty macro duration as trailing wait")
    func firstInsertedActionDoesNotInheritEmptyMacroDurationAsTrailingWait() {
        var events: [RecordedEvent] = []

        events.insertClick(at: 0)
        let liveDuration = events.liveDurationPreservingTrailingWait(
            previousLiveDuration: 5.0,
            previousLastEventTime: nil
        )

        #expect(abs(liveDuration - 0.1) < 0.000_001)
    }

    @Test("Passive wait insertion preserves timeline duration")
    func passiveWaitInsertionPreservesTimelineDuration() {
        var middleEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        let middlePreviousLastEventTime = middleEvents.last?.time
        let middlePreviousCount = middleEvents.count

        middleEvents.insertWait(at: 1, milliseconds: 500)
        let middleLiveDuration = middleEvents.liveDurationAfterPassiveWaitInsertion(
            previousLiveDuration: 3.0,
            previousLastEventTime: middlePreviousLastEventTime,
            previousEventCount: middlePreviousCount,
            insertionIndex: 1,
            waitDelta: 0.5
        )

        #expect(abs(middleLiveDuration - 3.5) < 0.000_001)

        var endEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.0, x: 10, y: 10)
        ]
        let endPreviousLastEventTime = endEvents.last?.time
        let endPreviousCount = endEvents.count

        endEvents.insertWait(at: endEvents.count, milliseconds: 500)
        let endLiveDuration = endEvents.liveDurationAfterPassiveWaitInsertion(
            previousLiveDuration: 3.0,
            previousLastEventTime: endPreviousLastEventTime,
            previousEventCount: endPreviousCount,
            insertionIndex: endPreviousCount,
            waitDelta: 0.5
        )

        #expect(abs(endLiveDuration - 3.5) < 0.000_001)
    }

    @Test("Inserted actions at beginning stay before existing events")
    func insertedActionsAtBeginningStayBeforeExistingEvents() {
        var clickEvents = [
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]

        clickEvents.insertClick(at: 0)

        #expect(clickEvents.map(\.kind) == [.leftMouseDown, .leftMouseUp, .keyDown])
        #expect(abs(clickEvents[0].time - 0.0) < 0.000_001)
        #expect(abs(clickEvents[1].time - 0.1) < 0.000_001)
        #expect(abs(clickEvents[2].time - 1.2) < 0.000_001)

        var textEvents = [
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]

        let textRange = textEvents.insertTextClick(at: 0)

        #expect(textRange == 0..<2)
        #expect(textEvents.map(\.kind) == [.leftMouseDown, .leftMouseUp, .keyDown])
        #expect(abs(textEvents[0].time - 0.0) < 0.000_001)
        #expect(abs(textEvents[1].time - 0.1) < 0.000_001)
        #expect(abs(textEvents[2].time - 1.2) < 0.000_001)

        var waitEvents = [
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]

        waitEvents.insertWaitForText(at: 0)

        #expect(waitEvents.map(\.kind) == [.waitForText, .keyDown])
        #expect(abs(waitEvents[0].time - 0.0) < 0.000_001)
        #expect(abs(waitEvents[1].time - 1.2) < 0.000_001)
    }

    @Test("Negative insertion index clamps to the beginning")
    func negativeInsertionIndexClampsToBeginning() {
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 1.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 1.1, x: 10, y: 10)
        ]

        events.insertKeystroke(at: -5)

        #expect(events.map(\.kind) == [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp])
        #expect(abs(events[0].time - 0.0) < 0.000_001)
        #expect(abs(events[1].time - 0.1) < 0.000_001)
        #expect(abs(events[2].time - 1.2) < 0.000_001)
        #expect(abs(events[3].time - 1.3) < 0.000_001)
    }

    @Test("Removing multi click points preserves at least two complete points")
    func removingMultiClickPointsPreservesAtLeastTwoCompletePoints() {
        var events: [RecordedEvent] = []
        events.insertMultiPointClick(at: 0)

        events.removeLastMultiPointClick(at: Array(events.indices))

        #expect(events.count == 4)
        #expect(events.map(\.kind) == [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        #expect(events.map(\.x) == [100, 100, 150, 150])

        let twoPointSnapshot = events
        events.removeLastMultiPointClick(at: Array(events.indices))

        #expect(events == twoPointSnapshot)

        var malformedEvents = [
            RecordedEvent.make(.leftMouseDown, time: 0.00, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.02, x: 10, y: 10),
            RecordedEvent.make(.leftMouseDown, time: 0.04, x: 20, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 0.06, x: 20, y: 20),
            RecordedEvent.make(.leftMouseDown, time: 0.08, x: 30, y: 30)
        ]
        let malformedSnapshot = malformedEvents

        malformedEvents.removeLastMultiPointClick(at: Array(malformedEvents.indices))

        #expect(malformedEvents == malformedSnapshot)
    }

    @Test("Appending multi click point ignores stale and repeated indices")
    func appendingMultiClickPointIgnoresStaleAndRepeatedIndices() {
        var events: [RecordedEvent] = []
        events.insertMultiPointClick(at: 0)

        events.appendMultiPointClick(at: [-1, 0, 1, 2, 3, 3, 99], point: CGPoint(x: 240, y: 260))

        #expect(events.count == 8)
        #expect(events.map(\.kind) == [
            .leftMouseDown, .leftMouseUp,
            .leftMouseDown, .leftMouseUp,
            .leftMouseDown, .leftMouseUp,
            .leftMouseDown, .leftMouseUp
        ])
        #expect(events.map(\.x) == [100, 100, 150, 150, 240, 240, 200, 200])
        #expect(events.map(\.y) == [100, 100, 100, 100, 260, 260, 100, 100])

        let snapshot = events
        events.appendMultiPointClick(at: [-3, 42], point: CGPoint(x: 300, y: 320))

        #expect(events == snapshot)
    }

    @Test("Duplicating events ignores stale and repeated indices")
    func duplicatingEventsIgnoresStaleAndRepeatedIndices() {
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]

        events.duplicateEvents(at: [-1, 0, 1, 1, 99])

        #expect(events.map(\.kind) == [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        #expect(events.map(\.time).map { round($0 * 1000) / 1000 } == [0.0, 0.1, 0.2, 0.3])

        let snapshot = events
        events.duplicateEvents(at: [-3, 42])

        #expect(events == snapshot)
    }

    @Test("Duplicating behavior creates an independent behavior group")
    func duplicatingBehaviorCreatesIndependentBehaviorGroup() throws {
        let behaviorID = BehaviorGroupID()
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 0.2, keyCode: 36),
            RecordedEvent.make(.keyUp, time: 0.3, keyCode: 36)
        ]
        events.bindBehavior(at: [0, 1, 2, 3], id: behaviorID, name: "Login")

        events.duplicateEvents(at: [0, 1, 2, 3])

        let originalIDs = Set(events[0..<4].compactMap(\.behaviorGroupID))
        let copiedIDs = Set(events[4..<8].compactMap(\.behaviorGroupID))
        let copiedID = try #require(copiedIDs.first)
        let groups = EventGrouper().group(events)

        #expect(originalIDs == Set([behaviorID]))
        #expect(copiedIDs.count == 1)
        #expect(copiedID != behaviorID)
        #expect(events[4..<8].allSatisfy { $0.behaviorGroupName == "Copy of Login" })
        #expect(groups.filter { $0.kind == .sequence }.count == 2)
        #expect(groups.filter { $0.kind == .sequence }.allSatisfy { $0.containedActionCount == 2 })
        #expect(Set(groups.compactMap(\.behaviorGroupID)).contains(behaviorID))
        #expect(Set(groups.compactMap(\.behaviorGroupID)).contains(copiedID))
    }

    @Test("Renaming behavior updates every bound event")
    func renamingBehaviorUpdatesEveryBoundEvent() {
        let behaviorID = BehaviorGroupID()
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 0.2, keyCode: 36)
        ]
        events.bindBehavior(at: [0, 1, 2], id: behaviorID, name: "Old Name")

        events.renameBehavior(id: behaviorID, name: "Checkout")

        #expect(events.allSatisfy { $0.behaviorGroupName == "Checkout" })
        #expect(EventGrouper().group(events).first?.summary == "Checkout (2 actions)")
    }
}

import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Action Group Projection Tests")
struct ActionGroupProjectionTests {
    @Test("Projection filters mouse move groups without changing action groups")
    func projectionFiltersMouseMoves() {
        let events = [
            RecordedEvent.make(.mouseMoved, time: 0.00, x: 10, y: 10),
            RecordedEvent.make(.mouseMoved, time: 0.05, x: 20, y: 20),
            RecordedEvent.make(.leftMouseDown, time: 0.10, x: 30, y: 30, mouseButton: 0),
            RecordedEvent.make(.leftMouseUp, time: 0.15, x: 30, y: 30, mouseButton: 0)
        ]

        let visible = ActionGroupProjection.groups(
            from: events,
            liveDuration: 0.15,
            hidesMouseMoves: true,
            smartMergeGestures: true
        )

        #expect(visible.map(\.kind) == [.click])
        #expect(visible.first?.eventIndices == [2, 3])
    }

    @Test("Projection can expose raw event rows when gesture merging is disabled")
    func projectionCanDisableGestureMerging() {
        let events = TestFixtures.clickPair(downTime: 0.0, upTime: 0.05, x: 40, y: 50)

        let merged = ActionGroupProjection.groups(
            from: events,
            liveDuration: 0.05,
            hidesMouseMoves: false,
            smartMergeGestures: true
        )
        let raw = ActionGroupProjection.groups(
            from: events,
            liveDuration: 0.05,
            hidesMouseMoves: false,
            smartMergeGestures: false
        )

        #expect(merged.map(\.kind) == [.click])
        #expect(raw.map(\.eventIndices) == [[0], [1]])
    }

    @Test("Projection resolves inserted event, wait, and behavior group selections")
    func projectionFindsSelectionTargets() throws {
        let behaviorId = BehaviorGroupID()
        let groups = [
            ActionGroup(
                kind: .click,
                eventIndices: [0, 1],
                startTime: 0,
                endTime: 0.1,
                summary: "Click"
            ),
            ActionGroup(
                kind: .wait,
                eventIndices: [],
                startTime: 0.1,
                endTime: 1.1,
                summary: "Wait"
            ),
            ActionGroup(
                kind: .sequence,
                eventIndices: [2, 3],
                startTime: 1.1,
                endTime: 1.5,
                summary: "Behavior",
                behaviorGroupID: behaviorId,
                behaviorGroupName: "Behavior 1"
            )
        ]

        let inserted = try #require(ActionGroupProjection.firstGroup(containingEventIn: 2..<4, groups: groups))
        #expect(inserted.kind == .sequence)

        let wait = try #require(ActionGroupProjection.firstWaitGroup(start: 0.1, end: 1.1, groups: groups))
        #expect(wait.kind == .wait)

        let behavior = try #require(ActionGroupProjection.firstBehaviorGroup(id: behaviorId, groups: groups))
        #expect(behavior.eventIndices == [2, 3])
    }

    @Test("Selection snapshot keeps group order and sorts event indices once")
    func selectionSnapshotKeepsGroupOrderAndSortsEventIndices() {
        let firstID = UUID()
        let secondID = UUID()
        let behaviorID = BehaviorGroupID()
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.keyDown, time: 0.2, keyCode: 1),
            RecordedEvent.make(.keyUp, time: 0.3, keyCode: 1),
            RecordedEvent.make(.scrollWheel, time: 0.4, x: 20, y: 30)
        ]
        events[4].behaviorGroupID = behaviorID
        let groups = [
            ActionGroup(
                id: firstID,
                kind: .click,
                eventIndices: [3, 1],
                startTime: 0,
                endTime: 0.3,
                summary: "Click"
            ),
            ActionGroup(
                id: secondID,
                kind: .scroll,
                eventIndices: [4],
                startTime: 0.4,
                endTime: 0.4,
                summary: "Scroll"
            )
        ]

        let snapshot = ActionGroupProjection.selectionSnapshot(
            groups: groups,
            selectedGroupIDs: [secondID, firstID],
            events: events
        )

        #expect(snapshot.groupIDs == [firstID, secondID])
        #expect(snapshot.eventIndices == [1, 3, 4])
        #expect(snapshot.containsBehavior)
        #expect(snapshot.canBindBehavior)
    }

    @Test("Selection snapshot detects behavior stored on grouped row")
    func selectionSnapshotDetectsGroupBehavior() {
        let groupID = UUID()
        let behaviorID = BehaviorGroupID()
        let group = ActionGroup(
            id: groupID,
            kind: .sequence,
            eventIndices: [],
            startTime: 0,
            endTime: 1,
            summary: "Behavior",
            behaviorGroupID: behaviorID,
            behaviorGroupName: "Behavior 1"
        )

        let snapshot = ActionGroupProjection.selectionSnapshot(
            groups: [group],
            selectedGroupIDs: [groupID],
            events: []
        )

        #expect(snapshot.groupIDs == [groupID])
        #expect(snapshot.eventIndices.isEmpty)
        #expect(snapshot.containsBehavior)
        #expect(!snapshot.canBindBehavior)
    }

    @Test("Selection snapshot is empty when nothing is selected")
    func selectionSnapshotIsEmptyWithoutSelection() {
        let group = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 0.1,
            summary: "Click"
        )

        let snapshot = ActionGroupProjection.selectionSnapshot(
            groups: [group],
            selectedGroupIDs: [],
            events: TestFixtures.clickPair()
        )

        #expect(snapshot.isEmpty)
        #expect(snapshot.groupIDs.isEmpty)
        #expect(snapshot.eventIndices.isEmpty)
        #expect(!snapshot.containsBehavior)
    }

    @Test("Text target selection includes coordinate clicks that can become click text")
    func textTargetSelectionIncludesCoordinateClickCandidates() {
        let waitID = UUID()
        let clickID = UUID()
        var events = [
            RecordedEvent.make(.waitForText, time: 0.0),
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 120, y: 80, mouseButton: 0),
            RecordedEvent.make(.leftMouseUp, time: 0.25, x: 120, y: 80, mouseButton: 0)
        ]
        events[0].textAnchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 100, y: 70, width: 80, height: 24)
        )
        let groups = [
            ActionGroup(
                id: waitID,
                kind: .waitForText,
                eventIndices: [0],
                startTime: 0.0,
                endTime: 0.0,
                summary: "Wait Text"
            ),
            ActionGroup(
                id: clickID,
                kind: .click,
                eventIndices: [1, 2],
                startTime: 0.2,
                endTime: 0.25,
                summary: "Click"
            )
        ]

        let targets = ActionGroupProjection.textTargetGroups(
            groups: groups,
            selectedGroupIDs: [waitID, clickID],
            events: events
        )
        let configuredOnly = ActionGroupProjection.textTargetGroups(
            groups: groups,
            selectedGroupIDs: [waitID, clickID],
            events: events,
            includesCoordinateClickCandidates: false
        )

        #expect(targets.map(\.kind) == [.waitForText, .click])
        #expect(configuredOnly.map(\.kind) == [.waitForText])
    }

    @Test("Text target selection does not turn plain scrolls into click text candidates")
    func textTargetSelectionExcludesPlainScrollCandidates() {
        let scrollID = UUID()
        var events = [
            RecordedEvent.make(.scrollWheel, time: 0.0, x: 120, y: 80, scrollDeltaY: -8)
        ]
        let group = ActionGroup(
            id: scrollID,
            kind: .scroll,
            eventIndices: [0],
            startTime: 0.0,
            endTime: 0.0,
            summary: "Scroll"
        )

        #expect(!ActionGroupProjection.isTextTargetGroup(group, events: events))

        events[0].coordinateStrategy = .locatorOnly

        #expect(ActionGroupProjection.isTextTargetGroup(group, events: events))
    }

    @Test("Text target readiness reports inserted empty text actions as incomplete")
    func textTargetReadinessReportsEmptyInsertedTextActions() {
        let groupID = UUID()
        var events = TestFixtures.clickPair(x: 130, y: 102)
        let emptyAnchor = TextAnchor(
            text: "",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        for index in events.indices {
            events[index].coordinateStrategy = .locatorOnly
            events[index].textAnchor = emptyAnchor
        }
        let group = ActionGroup(
            id: groupID,
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 0.1,
            summary: "Click text",
            textAnchor: emptyAnchor
        )

        #expect(ActionGroupProjection.textTargetReadiness(for: group, events: events) == .missingText)
        #expect(!ActionGroupProjection.textAnchorIsReady(emptyAnchor))
    }

    @Test("Text target readiness treats typed text with no observed frame as ready")
    func textTargetReadinessAllowsTypedTextWithoutObservedFrame() {
        let groupID = UUID()
        let anchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 0, y: 0, width: 0, height: 0)
        )
        var event = RecordedEvent.make(.waitForText, time: 0)
        event.textAnchor = anchor
        let group = ActionGroup(
            id: groupID,
            kind: .waitForText,
            eventIndices: [0],
            startTime: 0,
            endTime: 0,
            summary: "Wait Text",
            textAnchor: anchor
        )

        #expect(ActionGroupProjection.textTargetReadiness(for: group, events: [event]) == .ready)
        #expect(ActionGroupProjection.textAnchorIsReady(anchor))
    }

    @Test("Preview affordance separates click pulses from condition regions")
    func previewAffordanceSeparatesClickPulsesFromConditionRegions() {
        let click = ActionGroupProjection.previewAffordance(for: .click)
        let textClick = ActionGroupProjection.previewAffordance(for: .click, usesTextLocator: true)
        let wait = ActionGroupProjection.previewAffordance(for: .waitForText)
        let gone = ActionGroupProjection.previewAffordance(for: .waitForTextGone)
        let verify = ActionGroupProjection.previewAffordance(for: .verifyText)

        #expect(click == .inputPoint)
        #expect(click.showsClickPulse)
        #expect(!click.showsConditionRegion)
        #expect(textClick == .textClickTarget)
        #expect(textClick.showsClickPulse)
        #expect(textClick.showsLocatorFallbackPoint)
        #expect(textClick.showsTargetRegionLabel)

        #expect(wait == .waitTextRegion)
        #expect(gone == .waitTextGoneRegion)
        #expect(verify == .verifyTextRegion)
        #expect([wait, gone, verify].allSatisfy { $0.showsConditionRegion })
        #expect([wait, gone, verify].allSatisfy { !$0.showsClickPulse })
        #expect([wait, gone, verify].allSatisfy { $0.showsTargetRegionLabel })

        #expect(ActionGroupProjection.previewAffordance(for: .multiPointClick) == .pointSequence)
        #expect(ActionGroupProjection.previewAffordance(for: .drag) == .inputPath)
    }

    @Test("Text click factory creates locator backed click events from wait anchor")
    func textClickFactoryCreatesLocatorBackedClickEventsFromWaitAnchor() throws {
        let anchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24),
            searchRegion: RectValue(x: 70, y: 70, width: 140, height: 80),
            coordinateFallback: PointValue(x: 130, y: 102)
        )

        let events = TextClickEventFactory.makeEvents(
            startTime: 1.25,
            textAnchor: anchor,
            timeout: 8.0,
            fallbackPolicy: .allowCoordinateFallback,
            surfaceId: "checkout"
        )

        #expect(events.map(\.kind) == [.leftMouseDown, .leftMouseUp])
        #expect(events.map(\.coordinateStrategy) == [.locatorOnly, .locatorOnly])
        #expect(events.map(\.coordinateBinding) == [.targetWindow, .targetWindow])
        #expect(events.allSatisfy { $0.textAnchor == anchor })
        #expect(events.allSatisfy { $0.textTimeout == 8.0 })
        #expect(events.allSatisfy { $0.locatorFallbackPolicy == .allowCoordinateFallback })
        #expect(events.allSatisfy { $0.surfaceId == "checkout" })
        #expect(events[0].x == 130)
        #expect(events[0].y == 102)

        let group = try #require(EventGrouper().group(events).first)
        #expect(group.kind == .click)
        #expect(group.summary == "Click text: Confirm")
        #expect(group.textTargetReadiness == .ready)
    }

    @Test("Text click factory uses observed frame center when fallback is missing")
    func textClickFactoryUsesObservedFrameCenterWhenFallbackIsMissing() {
        let anchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24),
            observedContentNormalizedFrame: RectValue(x: 0.2, y: 0.3, width: 0.1, height: 0.2)
        )

        let events = TextClickEventFactory.makeEvents(startTime: 1.25, textAnchor: anchor)

        #expect(events.map(\.x) == [130, 130])
        #expect(events.map(\.y) == [102, 102])
        #expect(events.allSatisfy { $0.textAnchor?.coordinateFallback == PointValue(x: 130, y: 102) })
        #expect(events.allSatisfy { $0.textAnchor?.coordinateFallbackContentNormalized == PointValue(x: 0.25, y: 0.4) })
    }

    @Test("Text target anchor factory preserves recorded click as fallback")
    func textTargetAnchorFactoryPreservesRecordedClickAsFallback() {
        var click = RecordedEvent.make(
            .leftMouseDown,
            time: 0.25,
            x: 420,
            y: 280,
            mouseButton: 0,
            clickCount: 1
        )
        click.contentNormalizedX = 0.42
        click.contentNormalizedY = 0.64

        let anchor = TextTargetAnchorFactory.anchor(
            existing: nil,
            text: "Continue",
            fallbackEvent: click
        )

        #expect(anchor.text == "Continue")
        #expect(anchor.coordinateFallback == PointValue(x: 420, y: 280))
        #expect(anchor.coordinateFallbackContentNormalized == PointValue(x: 0.42, y: 0.64))
        #expect(ActionGroupProjection.textAnchorIsReady(anchor))
    }

    @Test("Text target anchor factory does not treat wait event origin as click fallback")
    func textTargetAnchorFactoryIgnoresWaitEventOriginFallback() {
        let wait = RecordedEvent.make(.waitForText, time: 0, x: 0, y: 0)

        let anchor = TextTargetAnchorFactory.anchor(
            existing: nil,
            text: "Continue",
            fallbackEvent: wait
        )

        #expect(anchor.coordinateFallback == nil)
        #expect(anchor.coordinateFallbackContentNormalized == nil)
    }

    @Test("Text click conversion planner replaces wait text with locator backed click")
    func textClickConversionPlannerReplacesWaitTextWithClickEvents() throws {
        var wait = RecordedEvent.make(.waitForText, time: 1.0)
        wait.textAnchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24)
        )
        wait.textTimeout = 7.0
        wait.locatorFallbackPolicy = .allowCoordinateFallback
        wait.surfaceId = "checkout"
        let next = RecordedEvent.make(.keyDown, time: 1.05, keyCode: 36)
        let group = ActionGroup(
            kind: .waitForText,
            eventIndices: [0],
            startTime: 1.0,
            endTime: 1.0,
            summary: "Wait Text",
            textAnchor: wait.textAnchor,
            textTimeout: 7.0
        )

        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: group,
            events: [wait, next],
            liveDuration: 1.2
        )

        #expect(plan.sourceEventIndex == 0)
        #expect(plan.insertedEvents.map(\.kind) == [.leftMouseDown, .leftMouseUp])
        #expect(plan.insertedEvents.map(\.coordinateStrategy) == [.locatorOnly, .locatorOnly])
        #expect(plan.insertedEvents.map(\.coordinateBinding) == [.targetWindow, .targetWindow])
        #expect(plan.insertedEvents.allSatisfy { $0.textAnchor?.text == "Confirm" })
        #expect(plan.insertedEvents.allSatisfy { $0.textTimeout == 7.0 })
        #expect(plan.insertedEvents.allSatisfy { $0.locatorFallbackPolicy == .allowCoordinateFallback })
        #expect(plan.insertedEvents.allSatisfy { $0.surfaceId == "checkout" })
        #expect(plan.insertedEvents.allSatisfy { $0.textAnchor?.coordinateFallback == PointValue(x: 130, y: 102) })
        #expect(abs(plan.insertedEvents[0].time - 1.0) < 0.000_001)
        #expect(abs(plan.insertedEvents[1].time - 1.1) < 0.000_001)

        let shift = try #require(plan.eventTimeShifts.first)
        #expect(shift.eventIndices == [1])
        #expect(abs(shift.delta - 0.05) < 0.000_001)
        #expect(abs((plan.liveDurationAfterConversion ?? 0) - 1.25) < 0.000_001)
    }

    @Test("Text click conversion planner keeps later timing when click has room")
    func textClickConversionPlannerKeepsLaterTimingWhenClickHasRoom() {
        var wait = RecordedEvent.make(.waitForText, time: 1.0)
        wait.textAnchor = TextAnchor(
            text: "Confirm",
            observedFrame: RectValue(x: 90, y: 90, width: 80, height: 24)
        )
        let next = RecordedEvent.make(.keyDown, time: 1.3, keyCode: 36)
        let group = ActionGroup(
            kind: .waitForText,
            eventIndices: [0],
            startTime: 1.0,
            endTime: 1.0,
            summary: "Wait Text",
            textAnchor: wait.textAnchor
        )

        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: group,
            events: [wait, next],
            liveDuration: 1.4
        )

        #expect(!plan.isEmpty)
        #expect(plan.eventTimeShifts.isEmpty)
        #expect(plan.liveDurationAfterConversion == nil)
    }

    @Test("Text click conversion planner keeps incomplete wait editable as click text")
    func textClickConversionPlannerKeepsIncompleteWaitEditableAsClickText() throws {
        let wait = RecordedEvent.make(.waitForText, time: 1.0)
        let group = ActionGroup(
            kind: .waitForText,
            eventIndices: [0],
            startTime: 1.0,
            endTime: 1.0,
            summary: "Wait Text"
        )

        let plan = ActionGroupTextClickConversionPlanner.plan(
            for: group,
            events: [wait],
            liveDuration: 1.0
        )
        let clickGroup = try #require(EventGrouper().group(plan.insertedEvents).first)

        #expect(!plan.isEmpty)
        #expect(clickGroup.kind == .click)
        #expect(clickGroup.summary == "Click text (needs text)")
        #expect(clickGroup.textTargetReadiness == .missingText)
        #expect(plan.liveDurationAfterConversion == 1.1)
    }

    @Test("Passive wait duplication planner extends middle wait by shifting later events")
    func passiveWaitDuplicationPlannerExtendsMiddleWaitByShiftingLaterEvents() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.leftMouseDown, time: 1.1, x: 20, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 1.2, x: 20, y: 20)
        ]
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 1.1,
            summary: "Wait"
        )

        let plan = ActionGroupPassiveWaitDuplicationPlanner.plan(
            for: [wait],
            events: events,
            liveDuration: 1.2
        )

        #expect(plan.eventTimeShifts == [
            ActionGroupEventTimeShift(eventIndices: [2, 3], delta: 1.0)
        ])
        #expect(abs((plan.liveDurationAfterDuplication ?? 0) - 2.2) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Passive wait duplication planner applies cumulative shifts for multiple waits")
    func passiveWaitDuplicationPlannerAppliesCumulativeShiftsForMultipleWaits() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 10, y: 10),
            RecordedEvent.make(.leftMouseDown, time: 2.2, x: 20, y: 20),
            RecordedEvent.make(.leftMouseDown, time: 5.2, x: 30, y: 30)
        ]
        let firstWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.2,
            endTime: 2.2,
            summary: "Wait"
        )
        let secondWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 2.2,
            endTime: 5.2,
            summary: "Wait"
        )

        let plan = ActionGroupPassiveWaitDuplicationPlanner.plan(
            for: [firstWait, secondWait],
            events: events,
            liveDuration: 5.2
        )

        #expect(plan.eventTimeShifts == [
            ActionGroupEventTimeShift(eventIndices: [1], delta: 2.0),
            ActionGroupEventTimeShift(eventIndices: [2], delta: 5.0)
        ])
        #expect(abs((plan.liveDurationAfterDuplication ?? 0) - 10.2) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Passive wait duplication planner extends trailing wait by lengthening live duration")
    func passiveWaitDuplicationPlannerExtendsTrailingWaitByLengtheningLiveDuration() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]
        let trailingWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 2.1,
            summary: "Wait"
        )

        let plan = ActionGroupPassiveWaitDuplicationPlanner.plan(
            for: [trailingWait],
            events: events,
            liveDuration: 2.1
        )

        #expect(plan.eventTimeShifts.isEmpty)
        #expect(abs((plan.liveDurationAfterDuplication ?? 0) - 4.1) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Deletion planner removes middle wait by shifting later events")
    func deletionPlannerRemovesMiddleWaitByShiftingLaterEvents() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10),
            RecordedEvent.make(.leftMouseDown, time: 1.1, x: 20, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 1.2, x: 20, y: 20)
        ]
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 1.1,
            summary: "Wait"
        )

        let plan = ActionGroupDeletionPlanner.plan(
            for: [wait],
            events: events,
            liveDuration: 1.2
        )

        #expect(plan.eventIndices.isEmpty)
        #expect(plan.eventTimeShifts == [
            ActionGroupEventTimeShift(eventIndices: [2, 3], delta: -1.0)
        ])
        #expect(plan.subsequentShiftCutoffTime == 1.1)
        #expect(plan.subsequentShift == -1.0)
        #expect(abs((plan.liveDurationAfterDeletion ?? 0) - 0.2) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Deletion planner applies cumulative shifts for multiple waits")
    func deletionPlannerAppliesCumulativeShiftsForMultipleWaits() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.2, x: 10, y: 10),
            RecordedEvent.make(.leftMouseDown, time: 2.2, x: 20, y: 20),
            RecordedEvent.make(.leftMouseDown, time: 5.2, x: 30, y: 30)
        ]
        let firstWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.2,
            endTime: 2.2,
            summary: "Wait"
        )
        let secondWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 2.2,
            endTime: 5.2,
            summary: "Wait"
        )

        let plan = ActionGroupDeletionPlanner.plan(
            for: [firstWait, secondWait],
            events: events,
            liveDuration: 5.2
        )

        #expect(plan.eventIndices.isEmpty)
        #expect(plan.eventTimeShifts == [
            ActionGroupEventTimeShift(eventIndices: [1], delta: -2.0),
            ActionGroupEventTimeShift(eventIndices: [2], delta: -5.0)
        ])
        #expect(plan.subsequentShiftCutoffTime == 2.2)
        #expect(plan.subsequentShift == -5.0)
        #expect(abs((plan.liveDurationAfterDeletion ?? 0) - 0.2) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Deletion planner removes trailing wait by shortening live duration")
    func deletionPlannerRemovesTrailingWaitByShorteningLiveDuration() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]
        let trailingWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 2.1,
            summary: "Wait"
        )

        let plan = ActionGroupDeletionPlanner.plan(
            for: [trailingWait],
            events: events,
            liveDuration: 2.1
        )

        #expect(plan.eventIndices.isEmpty)
        #expect(plan.eventTimeShifts.isEmpty)
        #expect(plan.subsequentShiftCutoffTime == nil)
        #expect(plan.subsequentShift == 0)
        #expect(abs((plan.liveDurationAfterDeletion ?? 0) - 0.1) < 0.000_001)
        #expect(!plan.isEmpty)
    }

    @Test("Deletion planner deletes event backed actions directly")
    func deletionPlannerDeletesEventBackedActionsDirectly() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 10)
        ]
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.0,
            endTime: 0.1,
            summary: "Click"
        )

        let plan = ActionGroupDeletionPlanner.plan(
            for: [click],
            events: events,
            liveDuration: 0.1
        )

        #expect(plan.eventIndices == [0, 1])
        #expect(plan.eventTimeShifts.isEmpty)
        #expect(plan.subsequentShiftCutoffTime == nil)
        #expect(plan.liveDurationAfterDeletion == nil)
        #expect(!plan.isEmpty)
    }
}

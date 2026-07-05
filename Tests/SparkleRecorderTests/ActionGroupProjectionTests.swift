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
}

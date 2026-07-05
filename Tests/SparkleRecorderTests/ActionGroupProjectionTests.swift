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
}

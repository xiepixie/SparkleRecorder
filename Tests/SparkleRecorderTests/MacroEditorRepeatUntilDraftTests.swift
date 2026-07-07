import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro Editor Repeat Until Draft Tests")
struct MacroEditorRepeatUntilDraftTests {
    @Test("Selected behavior and wait text create draft-only repeat-until preview")
    func selectedBehaviorAndWaitTextCreateDraftOnlyRepeatUntilPreview() throws {
        let bodyMacroID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
        let events = behaviorThenWaitTextEvents()
        let groups = ActionGroupProjection.groups(
            from: events,
            liveDuration: 5,
            hidesMouseMoves: false,
            smartMergeGestures: true
        )
        let clickGroup = try #require(groups.first { $0.kind == .click })
        let waitGroup = try #require(groups.first { $0.kind == .waitForText })

        let plan = MacroEditorRepeatUntilDraftBuilder.plan(
            request: MacroEditorRepeatUntilDraftRequest(
                sourceMacroName: "Checkout",
                bodyMacroID: bodyMacroID,
                bodyMacroName: "Checkout - Submit form",
                events: events,
                groups: groups,
                selectedGroupIDs: [clickGroup.id, waitGroup.id]
            )
        )

        #expect(plan.readiness == .ready)
        #expect(plan.bodyEventIndices == [0, 1])
        let normalizedTimes = plan.bodyEvents.map(\.time)
        #expect(normalizedTimes.count == 2)
        #expect(abs(normalizedTimes[0] - 0) < 0.000_001)
        #expect(abs(normalizedTimes[1] - 0.1) < 0.000_001)
        #expect(plan.bodyEvents.allSatisfy { $0.behaviorGroupID == nil })

        let document = try #require(plan.document)
        let loopTask = try #require(document.workflow.tasks.first)
        let loop = try #require(loopTask.loop)
        #expect(loop.kind == AutomationWorkflowDraftLoopKind.repeatUntil)
        #expect(loop.maxAttempts == 10)
        #expect(loop.timeoutSeconds == 30)
        #expect(loop.pollingSeconds == 1)
        #expect(loop.onFailure == AutomationWorkflowDraftLoopFailurePolicy.failRun)
        #expect(loop.tasks.first?.macroRef?.id == bodyMacroID)
        #expect(loop.tasks.first?.macroRef?.name == "Checkout - Submit form")

        let condition = try #require(loop.until)
        #expect(condition.type == "ocrText")
        #expect(condition.text == "Submitted")
        #expect(condition.matchMode == .contains)
        #expect(condition.requireVisible == true)
        #expect(condition.regionRef == "editor_91000000_until_region")

        let region = try #require(document.visualAssets?.regions.first)
        #expect(region.key == condition.regionRef)
        #expect(region.space == .contentNormalized)
        #expect(region.bounds == RectValue(x: 0.2, y: 0.3, width: 0.4, height: 0.1))

        let validation = AutomationWorkflowDraftValidator.validate(
            document,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: [
                AutomationWorkflowDraftMacroCatalogEntry(id: bodyMacroID, name: "Checkout - Submit form")
            ])
        )
        let containsDraftOnlyLoopIssue = validation.issues.contains(where: { issue in
            issue.code == .invalidLoop &&
            issue.message.contains("draft-only")
        })
        let containsMissingMacroRef = validation.issues.contains(where: { issue in
            issue.code == .missingMacroRef
        })
        #expect(containsDraftOnlyLoopIssue)
        #expect(!containsMissingMacroRef)
    }

    @Test("Wait text gone becomes non-visible repeat-until condition")
    func waitTextGoneBecomesNonVisibleRepeatUntilCondition() throws {
        let bodyMacroID = UUID(uuidString: "91000000-0000-0000-0000-000000000002")!
        var events = behaviorThenWaitTextEvents()
        events[2].verifyMustExist = false
        let groups = ActionGroupProjection.groups(
            from: events,
            liveDuration: 5,
            hidesMouseMoves: false,
            smartMergeGestures: true
        )
        let clickGroup = try #require(groups.first { $0.kind == .click })
        let goneGroup = try #require(groups.first { $0.kind == .waitForTextGone })

        let plan = MacroEditorRepeatUntilDraftBuilder.plan(
            request: MacroEditorRepeatUntilDraftRequest(
                sourceMacroName: "Checkout",
                bodyMacroID: bodyMacroID,
                bodyMacroName: "Checkout - Retry",
                events: events,
                groups: groups,
                selectedGroupIDs: [clickGroup.id, goneGroup.id]
            )
        )

        let condition = try #require(plan.untilCondition)
        #expect(condition.requireVisible == false)
    }

    @Test("Selection readiness explains missing body and ambiguous until")
    func selectionReadinessExplainsMissingBodyAndAmbiguousUntil() throws {
        let events = behaviorThenWaitTextEvents() + [waitTextEvent(time: 6, text: "Done")]
        let groups = ActionGroupProjection.groups(
            from: events,
            liveDuration: 6,
            hidesMouseMoves: false,
            smartMergeGestures: true
        )
        let waitGroups = groups.filter { $0.kind == .waitForText }
        let clickGroup = try #require(groups.first { $0.kind == .click })
        let firstWait = try #require(waitGroups.first)
        let secondWait = try #require(waitGroups.dropFirst().first)

        #expect(MacroEditorRepeatUntilDraftBuilder.readiness(
            events: events,
            groups: groups,
            selectedGroupIDs: [firstWait.id]
        ) == .missingBody)

        #expect(MacroEditorRepeatUntilDraftBuilder.readiness(
            events: events,
            groups: groups,
            selectedGroupIDs: [clickGroup.id, firstWait.id, secondWait.id]
        ) == .multipleUntilConditions)
    }

    private func behaviorThenWaitTextEvents() -> [RecordedEvent] {
        var down = RecordedEvent.make(.leftMouseDown, time: 4, x: 120, y: 160, mouseButton: 0, clickCount: 1)
        down.behaviorGroupID = BehaviorGroupID(UUID(uuidString: "92000000-0000-0000-0000-000000000001")!)
        down.behaviorGroupName = "Submit form"
        var up = RecordedEvent.make(.leftMouseUp, time: 4.1, x: 120, y: 160, mouseButton: 0, clickCount: 1)
        up.behaviorGroupID = down.behaviorGroupID
        up.behaviorGroupName = down.behaviorGroupName
        return [
            down,
            up,
            waitTextEvent(time: 5, text: "Submitted")
        ]
    }

    private func waitTextEvent(time: TimeInterval, text: String) -> RecordedEvent {
        var event = RecordedEvent.make(.waitForText, time: time)
        event.textAnchor = TextAnchor(
            text: text,
            observedFrame: RectValue(x: 80, y: 120, width: 200, height: 40),
            searchRegion: RectValue(x: 70, y: 110, width: 240, height: 80),
            observedContentNormalizedFrame: RectValue(x: 0.25, y: 0.32, width: 0.3, height: 0.06),
            searchContentNormalizedRegion: RectValue(x: 0.2, y: 0.3, width: 0.4, height: 0.1)
        )
        event.textTimeout = 12
        event.verifyMustExist = true
        return event
    }
}

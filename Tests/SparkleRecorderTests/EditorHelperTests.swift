import CoreGraphics
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Editor Helper Tests")
struct EditorHelperTests {
    @Test("Text click readiness help distinguishes add and convert actions")
    func textClickReadinessHelpDistinguishesAddAndConvertActions() {
        #expect(textClickFollowUpInsertionReadinessHelp(.ready) == "Reuse this wait target for the next text click.")
        #expect(textClickConversionReadinessHelp(.ready) == "Replace this wait with a text click using the same target.")
        #expect(textClickFollowUpInsertionReadinessHelp(.missingSourceEvent) == "This wait row has no recorded wait event to reuse. Insert Click Text manually instead.")
        #expect(textClickConversionReadinessHelp(.missingSourceEvent) == "This wait row has no recorded wait event to replace. Add Click Text instead.")
    }

    @Test("Action row text target status distinguishes missing anchor from missing text")
    func actionRowTextTargetStatusDistinguishesMissingAnchorFromMissingText() {
        #expect(actionRowTextTargetStatusLabel(.missingAnchor) == "No text target")
        #expect(actionRowTextTargetStatusLabel(.missingText) == "No target text")
        #expect(actionRowTextTargetStatusLabel(.notTextTarget) == nil)
        #expect(actionRowTextTargetStatusLabel(.ready) == nil)
    }

    @Test("Behavior bind readiness help explains disabled binding")
    func behaviorBindReadinessHelpExplainsDisabledBinding() {
        #expect(behaviorBindReadinessHelp(.ready) == "Create a named behavior from the selected actions.")
        #expect(behaviorBindReadinessHelp(.noSelection) == "Select two or more recorded actions to create a behavior.")
        #expect(behaviorBindReadinessHelp(.needsTwoRecordedActions) == "Select at least two recorded actions; wait gaps alone cannot create a behavior.")
        #expect(behaviorBindReadinessHelp(.nonContiguousRecordedActions) == "Select one continuous block of recorded actions. Wait gaps can stay between them.")
        #expect(behaviorBindReadinessHelp(.containsBehavior) == "This selection already contains a behavior. Rename or unbind it before creating another.")
    }

    @Test("Behavior rename readiness explains disabled renaming")
    func behaviorRenameReadinessExplainsDisabledRenaming() {
        let behavior = ActionGroup(
            kind: .sequence,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 1,
            summary: "Checkout",
            behaviorGroupID: BehaviorGroupID(),
            behaviorGroupName: "Checkout"
        )
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )

        #expect(behaviorRenameReadiness(for: nil, proposedName: "Checkout") == .noSelectedBehavior)
        #expect(behaviorRenameReadiness(for: click, proposedName: "Checkout") == .noSelectedBehavior)
        #expect(behaviorRenameReadiness(for: behavior, proposedName: "  ") == .missingName)
        #expect(behaviorRenameReadiness(for: behavior, proposedName: " Checkout ") == .unchangedName)
        #expect(behaviorRenameReadiness(for: behavior, proposedName: "Submit order") == .ready)
    }

    @Test("Behavior rename readiness help is localized")
    func behaviorRenameReadinessHelpIsLocalized() {
        #expect(behaviorRenameReadinessHelp(.ready) == "Rename the selected behavior.")
        #expect(behaviorRenameReadinessHelp(.noSelectedBehavior) == "Select one behavior to rename.")
        #expect(behaviorRenameReadinessHelp(.missingName) == "Enter a behavior name before renaming.")
        #expect(behaviorRenameReadinessHelp(.unchangedName) == "Change the behavior name before applying Rename.")
    }

    @Test("Action row count label keeps behavior count user-facing")
    func actionRowCountLabelKeepsBehaviorCountUserFacing() {
        let behavior = ActionGroup(
            kind: .sequence,
            eventIndices: [0, 1, 2, 3],
            startTime: 0,
            endTime: 1,
            summary: "Login (2 actions)",
            containedActionCount: 2
        )
        let merged = ActionGroup(
            kind: .click,
            eventIndices: [0, 1, 2, 3],
            startTime: 0,
            endTime: 1,
            summary: "Merged Click"
        )

        #expect(actionRowCountLabel(for: behavior) == "2 actions")
        #expect(actionRowCountLabel(for: merged) == "Merged (4)")
    }

    @Test("Action kind traits keep multi click out of single click type conversion")
    func actionKindTraitsKeepMultiClickOutOfSingleClickTypeConversion() {
        #expect(ActionGroupKind.click.canConvertClickType)
        #expect(ActionGroupKind.doubleClick.canConvertClickType)
        #expect(ActionGroupKind.repeatedClick.canConvertClickType)
        #expect(ActionGroupKind.longPress.canConvertClickType)
        #expect(!ActionGroupKind.multiPointClick.canConvertClickType)
        #expect(ActionGroupKind.multiPointClick.previewsPointSequence)
        #expect(!ActionGroupKind.multiPointClick.canUseLocatorStrategy)
    }

    @Test("Multi click point removal readiness keeps at least two points")
    func multiClickPointRemovalReadinessKeepsAtLeastTwoPoints() {
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let twoPointMultiClick = ActionGroup(
            kind: .multiPointClick,
            eventIndices: [0, 1, 2, 3],
            startTime: 0,
            endTime: 0.1,
            path: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)],
            summary: "Multi Click"
        )
        let threePointMultiClick = ActionGroup(
            kind: .multiPointClick,
            eventIndices: [0, 1, 2, 3, 4, 5],
            startTime: 0,
            endTime: 0.2,
            path: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40), CGPoint(x: 50, y: 60)],
            summary: "Multi Click"
        )

        #expect(multiPointClickPointRemovalReadiness(for: click) == .unsupportedAction)
        #expect(multiPointClickPointRemovalReadiness(for: twoPointMultiClick) == .needsAtLeastThreePoints)
        #expect(multiPointClickPointRemovalReadiness(for: threePointMultiClick) == .ready)
        #expect(multiPointClickPointRemovalReadinessHelp(.ready) == "Remove the last point from this Multi Click.")
        #expect(multiPointClickPointRemovalReadinessHelp(.unsupportedAction) == "Only Multi Click actions can remove click points.")
        #expect(multiPointClickPointRemovalReadinessHelp(.needsAtLeastThreePoints) == "Multi Click keeps at least two points.")
    }

    @Test("Batch coordinate alignment readiness prevents silent no-ops")
    func batchCoordinateAlignmentReadinessPreventsSilentNoOps() {
        let key = ActionGroup(
            kind: .keyPress,
            eventIndices: [0],
            startTime: 0,
            endTime: 0.1,
            summary: "Key"
        )
        let firstClick = ActionGroup(
            kind: .click,
            eventIndices: [1, 2],
            startTime: 0.2,
            endTime: 0.3,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let sameXClick = ActionGroup(
            kind: .click,
            eventIndices: [3, 4],
            startTime: 0.4,
            endTime: 0.5,
            startPoint: CGPoint(x: 10, y: 40),
            summary: "Click"
        )
        let samePointClick = ActionGroup(
            kind: .click,
            eventIndices: [5, 6],
            startTime: 0.6,
            endTime: 0.7,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.7,
            endTime: 1.0,
            summary: "Wait"
        )

        #expect(batchCoordinateAlignmentReadiness(for: [firstClick], alignsXCoordinate: true) == .needsMultipleActions)
        #expect(batchCoordinateAlignmentReadiness(for: [key, firstClick], alignsXCoordinate: true) == .firstActionHasNoCoordinate)
        #expect(batchCoordinateAlignmentReadiness(for: [firstClick, wait], alignsXCoordinate: true) == .noOtherCoordinateActions)
        #expect(batchCoordinateAlignmentReadiness(for: [firstClick, sameXClick], alignsXCoordinate: true) == .alreadyAligned)
        #expect(batchCoordinateAlignmentReadiness(for: [firstClick, sameXClick], alignsXCoordinate: false) == .ready)
        #expect(batchCoordinateAlignmentReadiness(for: [firstClick, samePointClick], alignsXCoordinate: false) == .alreadyAligned)
    }

    @Test("Batch coordinate alignment readiness help is localized")
    func batchCoordinateAlignmentReadinessHelpIsLocalized() {
        #expect(batchCoordinateAlignmentReadinessHelp(.ready) == "Align selected coordinate actions to the first selected action.")
        #expect(batchCoordinateAlignmentReadinessHelp(.needsMultipleActions) == "Select at least two actions to align coordinates.")
        #expect(batchCoordinateAlignmentReadinessHelp(.firstActionHasNoCoordinate) == "The first selected action has no coordinate to align to.")
        #expect(batchCoordinateAlignmentReadinessHelp(.noOtherCoordinateActions) == "Select another coordinate action to align.")
        #expect(batchCoordinateAlignmentReadinessHelp(.alreadyAligned) == "Selected coordinate actions are already aligned.")
    }

    @Test("Batch timeout readiness only enables text-target actions")
    func batchTimeoutReadinessOnlyEnablesTextTargetActions() {
        let anchor = TextAnchor(
            text: "Continue",
            observedFrame: RectValue(x: 10, y: 10, width: 80, height: 20)
        )
        var clickEvent = RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 20)
        clickEvent.coordinateStrategy = .locatorOnly
        clickEvent.textAnchor = anchor
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 20),
            RecordedEvent.make(.keyDown, time: 0.2, keyCode: 36),
            RecordedEvent.make(.waitForText, time: 0.4),
            clickEvent
        ]
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0],
            startTime: 0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let key = ActionGroup(
            kind: .keyPress,
            eventIndices: [1],
            startTime: 0.2,
            endTime: 0.2,
            summary: "Key"
        )
        let waitText = ActionGroup(
            kind: .waitForText,
            eventIndices: [2],
            startTime: 0.4,
            endTime: 0.4,
            summary: "Wait Text",
            textAnchor: anchor
        )
        let clickText = ActionGroup(
            kind: .click,
            eventIndices: [3],
            startTime: 0.6,
            endTime: 0.6,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click text",
            textAnchor: anchor
        )

        #expect(batchTimeoutReadiness(for: [click, key], events: events, timeout: 2.0) == .noTimeoutActions)
        #expect(batchTimeoutReadiness(for: [click, key], events: events, timeout: -1.0) == .noTimeoutActions)
        #expect(batchTimeoutReadiness(for: [click, waitText], events: events, timeout: 2.0) == .ready)
        #expect(batchTimeoutReadiness(for: [key, clickText], events: events, timeout: 2.0) == .ready)
        #expect(batchTimeoutReadiness(for: [waitText], events: events, timeout: -1.0) == .invalidTimeout)
        #expect(batchTimeoutReadiness(for: [waitText], events: events, timeout: .infinity) == .invalidTimeout)
        #expect(batchTimeoutEditableGroups(for: [click, waitText, clickText], events: events).map(\.eventIndices) == [[2], [3]])
    }

    @Test("Batch timeout readiness help is localized")
    func batchTimeoutReadinessHelpIsLocalized() {
        #expect(batchTimeoutReadinessHelp(.ready) == "Apply this timeout to selected text-target actions.")
        #expect(batchTimeoutReadinessHelp(.noTimeoutActions) == "Select Wait Text, Verify Text, or Click Text actions with a target to set a timeout.")
        #expect(batchTimeoutReadinessHelp(.invalidTimeout) == "Enter a timeout of 0 or greater before applying to selected actions.")
    }

    @Test("Batch text target readiness prevents empty batch targets")
    func batchTextTargetReadinessPreventsEmptyBatchTargets() {
        let waitText = ActionGroup(
            kind: .waitForText,
            eventIndices: [0],
            startTime: 0,
            endTime: 0.1,
            summary: "Wait Text"
        )

        #expect(batchTextTargetReadiness(for: [], targetText: "Confirm") == .noTextTargetActions)
        #expect(batchTextTargetReadiness(for: [waitText], targetText: "") == .missingTargetText)
        #expect(batchTextTargetReadiness(for: [waitText], targetText: "  \n  ") == .missingTargetText)
        #expect(batchTextTargetReadiness(for: [waitText], targetText: "Confirm") == .ready)
    }

    @Test("Batch text target readiness help is localized")
    func batchTextTargetReadinessHelpIsLocalized() {
        #expect(batchTextTargetReadinessHelp(.ready) == "Apply this target text to selected text-target actions.")
        #expect(batchTextTargetReadinessHelp(.noTextTargetActions) == "Select text-capable actions before applying a shared target.")
        #expect(batchTextTargetReadinessHelp(.missingTargetText) == "Enter or pick target text before applying to selected actions.")
    }

    @Test("Selection delete and duplicate readiness prevents silent no-ops")
    func actionSelectionMutationReadinessPreventsSilentNoOps() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 20)
        ]
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 0.7,
            summary: "Wait"
        )
        let emptyWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.7,
            endTime: 0.7,
            summary: "Wait"
        )

        #expect(actionSelectionDeletionReadiness(for: [], events: events, liveDuration: 1.0) == .noSelection)
        #expect(actionSelectionDeletionReadiness(for: [emptyWait], events: events, liveDuration: 1.0) == .noDeletableActions)
        #expect(actionSelectionDeletionReadiness(for: [click], events: events, liveDuration: 1.0) == .ready)
        #expect(actionSelectionDeletionReadiness(for: [wait], events: events, liveDuration: 1.0) == .ready)

        #expect(actionSelectionDuplicationReadiness(for: [], events: events, liveDuration: 1.0) == .noSelection)
        #expect(actionSelectionDuplicationReadiness(for: [emptyWait], events: events, liveDuration: 1.0) == .noDuplicatableActions)
        #expect(actionSelectionDuplicationReadiness(for: [click], events: events, liveDuration: 1.0) == .ready)
        #expect(actionSelectionDuplicationReadiness(for: [wait], events: events, liveDuration: 1.0) == .ready)
    }

    @Test("Selection delete and duplicate readiness help is localized")
    func actionSelectionMutationReadinessHelpIsLocalized() {
        #expect(actionSelectionDeletionReadinessHelp(.ready) == "Delete selected actions from the macro.")
        #expect(actionSelectionDeletionReadinessHelp(.noSelection) == "Select actions to delete.")
        #expect(actionSelectionDeletionReadinessHelp(.noDeletableActions) == "Select recorded actions or wait gaps with duration to delete.")

        #expect(actionSelectionDuplicationReadinessHelp(.ready) == "Duplicate selected actions or wait gaps.")
        #expect(actionSelectionDuplicationReadinessHelp(.noSelection) == "Select actions to duplicate.")
        #expect(actionSelectionDuplicationReadinessHelp(.noDuplicatableActions) == "Select recorded actions or wait gaps with duration to duplicate.")
    }

    @Test("Inspector input warning explains invalid typed fields")
    func actionInspectorInputWarningExplainsInvalidTypedFields() {
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.2,
            endTime: 0.3,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let drag = ActionGroup(
            kind: .drag,
            eventIndices: [0, 1, 2],
            startTime: 0.2,
            endTime: 0.5,
            startPoint: CGPoint(x: 10, y: 20),
            endPoint: CGPoint(x: 40, y: 60),
            summary: "Drag"
        )
        let key = ActionGroup(
            kind: .keyPress,
            eventIndices: [0],
            startTime: 0.2,
            endTime: 0.2,
            summary: "Key"
        )

        #expect(actionInspectorInputWarning(
            for: click,
            timeText: "-1",
            xText: "10",
            yText: "20",
            endXText: "",
            endYText: "",
            keyText: "",
            strategy: .windowLocalPreferred,
            timeout: 1
        ) == .invalidTime)
        #expect(actionInspectorInputWarning(
            for: click,
            timeText: "0.2",
            xText: "oops",
            yText: "20",
            endXText: "",
            endYText: "",
            keyText: "",
            strategy: .windowLocalPreferred,
            timeout: 1
        ) == .invalidStartCoordinate)
        #expect(actionInspectorInputWarning(
            for: click,
            timeText: "0.2",
            xText: "oops",
            yText: "20",
            endXText: "",
            endYText: "",
            keyText: "",
            strategy: .locatorOnly,
            timeout: -1
        ) == .invalidTimeout)
        #expect(actionInspectorInputWarning(
            for: drag,
            timeText: "0.2",
            xText: "10",
            yText: "20",
            endXText: "40",
            endYText: "bad",
            keyText: "",
            strategy: .windowLocalPreferred,
            timeout: 1
        ) == .invalidEndCoordinate)
        #expect(actionInspectorInputWarning(
            for: key,
            timeText: "0.2",
            xText: "",
            yText: "",
            endXText: "",
            endYText: "",
            keyText: "not-a-code",
            strategy: .windowLocalPreferred,
            timeout: 1
        ) == .invalidKeyCode)
        #expect(actionInspectorInputWarning(
            for: key,
            timeText: "0.2",
            xText: "",
            yText: "",
            endXText: "",
            endYText: "",
            keyText: " 36 ",
            strategy: .windowLocalPreferred,
            timeout: 1
        ) == .none)
    }

    @Test("Inspector input warning help is localized")
    func actionInspectorInputWarningHelpIsLocalized() {
        #expect(actionInspectorInputWarningHelp(.none) == "Inspector inputs are ready to apply.")
        #expect(actionInspectorInputWarningHelp(.invalidTime) == "Enter a valid time or duration of 0 or greater.")
        #expect(actionInspectorInputWarningHelp(.invalidTimeout) == "Enter a timeout of 0 or greater.")
        #expect(actionInspectorInputWarningHelp(.invalidStartCoordinate) == "Enter valid X and Y coordinates for the action start.")
        #expect(actionInspectorInputWarningHelp(.invalidEndCoordinate) == "Enter valid X and Y coordinates for the action end.")
        #expect(actionInspectorInputWarningHelp(.invalidKeyCode) == "Enter a valid key code.")
    }

    @Test("Action trim readiness prevents silent no-ops")
    func actionTrimReadinessPreventsSilentNoOps() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 20),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 10, y: 20),
            RecordedEvent.make(.keyDown, time: 1.0, keyCode: 36)
        ]
        let firstClick = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let delayedFirstClick = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.4,
            endTime: 0.5,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let lastKey = ActionGroup(
            kind: .keyPress,
            eventIndices: [2],
            startTime: 1.0,
            endTime: 1.0,
            summary: "Key"
        )
        let middleWait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 1.0,
            summary: "Wait"
        )

        #expect(actionTrimReadiness(for: [], events: events, liveDuration: 1.0, direction: .before) == .needsSingleAction)
        #expect(actionTrimReadiness(for: [firstClick, lastKey], events: events, liveDuration: 1.0, direction: .after) == .needsSingleAction)
        #expect(actionTrimReadiness(for: [firstClick], events: events, liveDuration: 1.0, direction: .before) == .noContentBefore)
        #expect(actionTrimReadiness(for: [delayedFirstClick], events: events, liveDuration: 1.0, direction: .before) == .ready)
        #expect(actionTrimReadiness(for: [firstClick], events: events, liveDuration: 1.0, direction: .after) == .ready)
        #expect(actionTrimReadiness(for: [middleWait], events: events, liveDuration: 1.0, direction: .after) == .ready)
        #expect(actionTrimReadiness(for: [lastKey], events: events, liveDuration: 1.0, direction: .after) == .noContentAfter)
        #expect(actionTrimReadiness(for: [lastKey], events: events, liveDuration: 1.5, direction: .after) == .ready)
    }

    @Test("Action trim readiness help is localized")
    func actionTrimReadinessHelpIsLocalized() {
        #expect(actionTrimReadinessHelp(.ready, direction: .before) == "Remove everything before the selected action and start it at 0.")
        #expect(actionTrimReadinessHelp(.ready, direction: .after) == "Remove everything after the selected action.")
        #expect(actionTrimReadinessHelp(.needsSingleAction, direction: .before) == "Select exactly one action to trim the macro.")
        #expect(actionTrimReadinessHelp(.noContentBefore, direction: .before) == "The selected action is already at the beginning.")
        #expect(actionTrimReadinessHelp(.noContentAfter, direction: .after) == "The selected action is already at the end.")
    }

    @Test("Action shift readiness prevents silent no-ops")
    func actionShiftReadinessPreventsSilentNoOps() {
        let firstClick = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0.0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let laterKey = ActionGroup(
            kind: .keyPress,
            eventIndices: [2],
            startTime: 0.8,
            endTime: 0.8,
            summary: "Key"
        )
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 0.8,
            summary: "Wait"
        )

        #expect(actionShiftReadiness(for: [], direction: .earlier) == .noSelection)
        #expect(actionShiftReadiness(for: [wait], direction: .earlier) == .noEventBackedActions)
        #expect(actionShiftReadiness(for: [wait], direction: .later) == .noEventBackedActions)
        #expect(actionShiftReadiness(for: [firstClick], direction: .earlier) == .alreadyAtStart)
        #expect(actionShiftReadiness(for: [firstClick], direction: .later) == .ready)
        #expect(actionShiftReadiness(for: [laterKey], direction: .earlier) == .ready)
        #expect(actionShiftReadiness(for: [wait, laterKey], direction: .later) == .ready)
    }

    @Test("Action shift readiness help is localized")
    func actionShiftReadinessHelpIsLocalized() {
        #expect(actionShiftReadinessHelp(.ready, direction: .earlier) == "Move selected recorded actions earlier.")
        #expect(actionShiftReadinessHelp(.ready, direction: .later) == "Move selected recorded actions later.")
        #expect(actionShiftReadinessHelp(.noSelection, direction: .earlier) == "Select recorded actions to shift their timing.")
        #expect(actionShiftReadinessHelp(.noEventBackedActions, direction: .later) == "Wait gaps are edited with Wait Duration instead of Shift Selected.")
        #expect(actionShiftReadinessHelp(.alreadyAtStart, direction: .earlier) == "The selected action is already at the beginning.")
    }

    @Test("Action time stretch readiness prevents silent no-ops")
    func actionTimeStretchReadinessPreventsSilentNoOps() {
        #expect(actionTimeStretchReadiness(hasActions: false, factor: 2.0) == .noActions)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: 1.0) == .unchangedFactor)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: 1.0005) == .unchangedFactor)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: 0.0) == .invalidFactor)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: -0.5) == .invalidFactor)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: .infinity) == .invalidFactor)
        #expect(actionTimeStretchReadiness(hasActions: true, factor: 1.05) == .ready)
    }

    @Test("Action time stretch readiness help is localized")
    func actionTimeStretchReadinessHelpIsLocalized() {
        #expect(actionTimeStretchReadinessHelp(.ready) == "Apply this stretch factor to the full macro timeline.")
        #expect(actionTimeStretchReadinessHelp(.noActions) == "Record or insert actions before stretching time.")
        #expect(actionTimeStretchReadinessHelp(.invalidFactor) == "Choose a stretch factor greater than 0.")
        #expect(actionTimeStretchReadinessHelp(.unchangedFactor) == "Choose a stretch factor other than 1.00x.")
    }

    @Test("Action row reorder readiness explains disabled move controls")
    func actionRowReorderReadinessExplainsDisabledMoveControls() {
        let click = ActionGroup(
            kind: .click,
            eventIndices: [0, 1],
            startTime: 0,
            endTime: 0.1,
            startPoint: CGPoint(x: 10, y: 20),
            summary: "Click"
        )
        let wait = ActionGroup(
            kind: .wait,
            eventIndices: [],
            startTime: 0.1,
            endTime: 0.8,
            summary: "Wait"
        )

        #expect(actionRowReorderReadiness(for: [], canMove: false, direction: .up) == .noSelection)
        #expect(actionRowReorderReadiness(for: [wait], canMove: false, direction: .down) == .noRecordedActions)
        #expect(actionRowReorderReadiness(for: [click], canMove: false, direction: .up) == .alreadyAtTop)
        #expect(actionRowReorderReadiness(for: [click], canMove: false, direction: .down) == .alreadyAtBottom)
        #expect(actionRowReorderReadiness(for: [wait, click], canMove: true, direction: .down) == .ready)
    }

    @Test("Action row reorder readiness help is localized")
    func actionRowReorderReadinessHelpIsLocalized() {
        #expect(actionRowReorderReadinessHelp(.ready, direction: .up) == "Move selected actions up")
        #expect(actionRowReorderReadinessHelp(.ready, direction: .down) == "Move selected actions down")
        #expect(actionRowReorderReadinessHelp(.noSelection, direction: .up) == "Select recorded actions to reorder them.")
        #expect(actionRowReorderReadinessHelp(.noRecordedActions, direction: .down) == "Wait gaps are edited with Wait Duration instead of row reordering.")
        #expect(actionRowReorderReadinessHelp(.alreadyAtTop, direction: .up) == "Selected actions are already at the top.")
        #expect(actionRowReorderReadinessHelp(.alreadyAtBottom, direction: .down) == "Selected actions are already at the bottom.")
        #expect(actionRowReorderDisabledSummary(up: .alreadyAtTop, down: .alreadyAtBottom) == "Selected actions cannot move farther.")
        #expect(actionRowReorderDisabledSummary(up: .noRecordedActions, down: .noRecordedActions) == "Wait gaps are edited with Wait Duration instead of row reordering.")
    }

    @Test("Observation presentation distinguishes OCR scope from visual detectors")
    func observationPresentationDistinguishesOCRScopeFromVisualDetectors() {
        #expect(AutomationConditionObservationPresentation.ocrDetectorTitle() == "Detector: OCR text")
        #expect(AutomationConditionObservationPresentation.ocrDetectorDetail() == "Recognizes visible text only; icons and drawings need a visual condition.")
        #expect(AutomationConditionObservationPresentation.scopeTitle(hasRegion: false) == "Scope: full display")
        #expect(AutomationConditionObservationPresentation.ocrScopeDetail(hasRegion: false) == "All detected text on the captured display can match.")
        #expect(AutomationConditionObservationPresentation.scopeTitle(hasRegion: true) == "Scope: selected region")
        #expect(AutomationConditionObservationPresentation.ocrScopeDetail(hasRegion: true) == "Only text detected inside the selected region can match.")

        #expect(AutomationVisualConditionPresentation.detectorTitle(for: .imageAppeared) == "Detector: image template")
        #expect(AutomationVisualConditionPresentation.detectorDetail(for: .imageAppeared) == "Looks for a saved image crop, such as an icon or button, inside the watched area.")
        #expect(AutomationVisualConditionPresentation.detectorDetail(for: .imageDisappeared) == "Continues when the saved image crop is absent from the watched area.")
        #expect(AutomationVisualConditionPresentation.detectorTitle(for: .regionChanged) == "Detector: baseline diff")
        #expect(AutomationVisualConditionPresentation.detectorTitle(for: .pixelMatched) == "Detector: pixel color")
        #expect(AutomationConditionObservationPresentation.visualScopeDetail(hasRegion: true) == "Only pixels inside the selected bounds are evaluated.")
    }
}

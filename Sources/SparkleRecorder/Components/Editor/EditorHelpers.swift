import Cocoa
import SwiftUI
import SparkleRecorderCore

func formatDuration(_ d: TimeInterval) -> String {
    let m = Int(d) / 60
    let s = Int(d) % 60
    let cs = Int((d - floor(d)) * 100)
    return String(format: "%02d:%02d.%02d", m, s, cs)
}

func humanKindName(_ k: RecordedEvent.Kind) -> String {
    switch k {
    case .leftMouseDown:     return NSLocalizedString("Left Click ↓", comment: "")
    case .leftMouseUp:       return NSLocalizedString("Left Click ↑", comment: "")
    case .rightMouseDown:    return NSLocalizedString("Right Click ↓", comment: "")
    case .rightMouseUp:      return NSLocalizedString("Right Click ↑", comment: "")
    case .otherMouseDown:    return NSLocalizedString("Other Click ↓", comment: "")
    case .otherMouseUp:      return NSLocalizedString("Other Click ↑", comment: "")
    case .mouseMoved:        return NSLocalizedString("Mouse Move", comment: "")
    case .leftMouseDragged:  return NSLocalizedString("Drag (L)", comment: "")
    case .rightMouseDragged: return NSLocalizedString("Drag (R)", comment: "")
    case .otherMouseDragged: return NSLocalizedString("Drag (Other)", comment: "")
    case .keyDown:           return NSLocalizedString("Key Down", comment: "")
    case .keyUp:             return NSLocalizedString("Key Up", comment: "")
    case .flagsChanged:      return NSLocalizedString("Modifier", comment: "")
    case .scrollWheel:       return NSLocalizedString("Scroll", comment: "")
    case .waitForText:       return NSLocalizedString("Wait Text", comment: "")
    case .verifyText:        return NSLocalizedString("Verify Text", comment: "")
    }
}

func kindIcon(_ k: RecordedEvent.Kind) -> String {
    if k.isKey { return "keyboard" }
    switch k {
    case .leftMouseDown, .leftMouseUp:           return "cursorarrow.click"
    case .rightMouseDown, .rightMouseUp:         return "cursorarrow.click.2"
    case .mouseMoved:                            return "arrow.up.left.and.arrow.down.right"
    case .leftMouseDragged, .rightMouseDragged,
         .otherMouseDragged:                     return "hand.draw"
    case .scrollWheel:                           return "arrow.up.and.down"
    case .otherMouseDown, .otherMouseUp:         return "circle.grid.cross"
    default:                                     return "circle"
    }
}

func actionKindColor(_ k: ActionGroupKind) -> Color {
    switch k {
    case .click, .doubleClick, .repeatedClick: return Brand.sigGreen
    case .multiPointClick: return Brand.sigPink
    case .longPress: return Brand.sigGreen
    case .drag: return Brand.sigViolet
    case .scroll: return Brand.sigTeal
    case .keyPress, .keyHold, .keyRepeat, .shortcut, .modifierHold, .textInput: return Brand.sigBlue
    case .waitForText, .waitForTextGone: return Brand.sigAmber
    case .verifyText: return Brand.sigViolet
    case .sequence: return Brand.sigAmber
    case .wait: return .secondary
    case .mouseMove: return .secondary
    }
}

func actionKindIcon(_ k: ActionGroupKind) -> String {
    switch k {
    case .click: return "cursorarrow.click"
    case .doubleClick: return "cursorarrow.click.2"
    case .repeatedClick: return "repeat"
    case .multiPointClick: return "point.3.connected.trianglepath.dotted"
    case .longPress: return "hand.tap"
    case .drag: return "hand.draw"
    case .scroll: return "arrow.up.and.down"
    case .keyPress, .keyHold, .keyRepeat, .shortcut, .modifierHold, .textInput: return "keyboard"
    case .waitForText: return "text.magnifyingglass"
    case .waitForTextGone: return "text.badge.minus"
    case .verifyText: return "checkmark.seal"
    case .sequence: return "square.stack.3d.down.right"
    case .wait: return "clock"
    case .mouseMove: return "arrow.up.left.and.arrow.down.right"
    }
}

func humanActionKindName(_ k: ActionGroupKind) -> String {
    switch k {
    case .click: return NSLocalizedString("Click", comment: "")
    case .doubleClick: return NSLocalizedString("Double Click", comment: "")
    case .repeatedClick: return NSLocalizedString("Repeated Click", comment: "")
    case .multiPointClick: return NSLocalizedString("Multi Click", comment: "")
    case .longPress: return NSLocalizedString("Long Press", comment: "")
    case .drag: return NSLocalizedString("Drag", comment: "")
    case .scroll: return NSLocalizedString("Scroll", comment: "")
    case .keyPress: return NSLocalizedString("KeyPress", comment: "")
    case .keyHold: return NSLocalizedString("KeyHold", comment: "")
    case .keyRepeat: return NSLocalizedString("Key Repeat", comment: "")
    case .shortcut: return NSLocalizedString("Shortcut", comment: "")
    case .modifierHold: return NSLocalizedString("Modifier Hold", comment: "")
    case .textInput: return NSLocalizedString("Text Input", comment: "")
    case .waitForText: return NSLocalizedString("Wait Text", comment: "")
    case .waitForTextGone: return NSLocalizedString("Wait Text Gone", comment: "")
    case .verifyText: return NSLocalizedString("Verify Text", comment: "")
    case .sequence: return NSLocalizedString("Behavior", comment: "")
    case .wait: return NSLocalizedString("Wait", comment: "")
    case .mouseMove: return NSLocalizedString("Mouse Move", comment: "")
    }
}

/// Editor-facing behavior for each semantic action type.
///
/// `ActionGroupKind` is produced by `EventGrouper` from raw mouse/keyboard
/// events. The editor uses these traits to decide which controls make sense for
/// the selected action, keeping interaction rules in one place instead of
/// scattering `kind == ...` checks across the UI.
///
/// Action edit model:
/// - Click, double click, repeated click, long press, multi click, and scroll are point
///   actions: they can use absolute/window/OCR targeting.
/// - Drag is a path action: start/end handles edit the whole down-drag-up
///   gesture while preserving the captured curve.
/// - Key, shortcut, modifier hold, repeat, and text input are keyboard actions:
///   they share key-code/modifier editing.
/// - Wait for text and verify text are semantic OCR actions: they edit text
///   anchors rather than mouse coordinates.
/// - Wait rows are derived timing gaps, not raw events, so they are edited as
///   durations and excluded from reorder moves.
/// - Behavior, mouse move, repeated/key-hold variants may be recorder-generated
///   rather than sidebar-inserted, but still participate in selection, preview,
///   and editing through the same traits.
extension ActionGroupKind {
    var isClickFamily: Bool {
        switch self {
        case .click, .doubleClick, .repeatedClick, .longPress, .multiPointClick:
            return true
        default:
            return false
        }
    }

    var editsPointTarget: Bool {
        isClickFamily || self == .scroll
    }

    var editsPathTarget: Bool {
        self == .drag
    }

    var editsKeyboardInput: Bool {
        switch self {
        case .keyPress, .keyHold, .keyRepeat, .shortcut, .modifierHold, .textInput:
            return true
        default:
            return false
        }
    }

    var editsSemanticTextTarget: Bool {
        self == .waitForText || self == .waitForTextGone || self == .verifyText
    }

    var canUseLocatorStrategy: Bool {
        editsPointTarget && self != .multiPointClick
    }

    var canRetargetCoordinate: Bool {
        isClickFamily || editsPathTarget
    }

    var canConvertClickType: Bool {
        switch self {
        case .click, .doubleClick, .repeatedClick, .longPress:
            return true
        default:
            return false
        }
    }

    var canPreviewPath: Bool {
        self == .drag || self == .scroll || self == .multiPointClick
    }

    var previewsPointSequence: Bool {
        self == .multiPointClick
    }

    var isPassiveWait: Bool {
        self == .wait
    }

    var isReorderableAction: Bool {
        self != .wait
    }

    var insertedEventCount: Int {
        switch self {
        case .click, .doubleClick, .keyPress:
            return 2
        case .multiPointClick:
            return 6
        case .drag:
            return 3
        case .waitForText, .waitForTextGone, .verifyText, .scroll:
            return 1
        default:
            return 0
        }
    }
}

func actionWorkflowMessage(for group: ActionGroup, event: RecordedEvent?) -> String {
    if group.kind == .waitForText {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            return NSLocalizedString("Needs target text before playback can wait.", comment: "")
        }
        return NSLocalizedString("Waits until the target text appears, then continues. It does not click.", comment: "")
    }
    if group.kind == .waitForTextGone {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            return NSLocalizedString("Needs target text before playback can wait.", comment: "")
        }
        return NSLocalizedString("Waits until the target text disappears, then continues. It does not click.", comment: "")
    }
    if group.kind == .verifyText {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            return NSLocalizedString("Needs target text before playback can verify.", comment: "")
        }
        return NSLocalizedString("Checks the text condition once. Playback stops if the condition is not met.", comment: "")
    }
    if group.kind == .multiPointClick {
        return NSLocalizedString("Clicks several coordinates in rapid sequence so they behave like one combined action.", comment: "")
    }
    if group.kind.canUseLocatorStrategy && ((event?.coordinateStrategy == .locatorOnly) || group.textAnchor != nil) {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            if group.kind == .click {
                return NSLocalizedString("Needs target text before playback can click.", comment: "")
            }
            return NSLocalizedString("Needs target text before playback can locate this action.", comment: "")
        }
        if group.kind == .click {
            return NSLocalizedString("Waits for the target text up to the timeout, then clicks the matched text box.", comment: "")
        }
        return NSLocalizedString("Waits for the target text up to the timeout, then plays this action at the matched text box.", comment: "")
    }
    if group.kind.editsPathTarget {
        return NSLocalizedString("Keeps the drag as one down-drag-up gesture; moving handles preserves the path shape.", comment: "")
    }
    if group.kind.isPassiveWait {
        return NSLocalizedString("Adds time between actions without sending input.", comment: "")
    }
    if group.kind.editsKeyboardInput {
        return NSLocalizedString("Edits the captured key and modifiers while keeping the action timing in place.", comment: "")
    }
    if group.kind == .sequence {
        return NSLocalizedString("Keeps the selected events together as one behavior block while preserving their internal timing.", comment: "")
    }
    return NSLocalizedString("Edits this action without changing the surrounding actions.", comment: "")
}

enum MultiPointClickPointRemovalReadiness: String, Codable, Equatable, Sendable {
    case ready
    case unsupportedAction
    case needsAtLeastThreePoints

    var canRemove: Bool {
        self == .ready
    }
}

func multiPointClickPointRemovalReadiness(for group: ActionGroup) -> MultiPointClickPointRemovalReadiness {
    guard group.kind == .multiPointClick else {
        return .unsupportedAction
    }
    let pointCount = max(group.path.count, group.eventIndices.count / 2)
    guard pointCount > 2 else {
        return .needsAtLeastThreePoints
    }
    return .ready
}

func multiPointClickPointRemovalReadinessHelp(_ readiness: MultiPointClickPointRemovalReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Remove the last point from this Multi Click.", comment: "")
    case .unsupportedAction:
        return NSLocalizedString("Only Multi Click actions can remove click points.", comment: "")
    case .needsAtLeastThreePoints:
        return NSLocalizedString("Multi Click keeps at least two points.", comment: "")
    }
}

func textClickConversionReadinessHelp(_ readiness: TextClickConversionReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Replace this wait with a text click using the same target.", comment: "")
    case .unsupportedAction:
        return NSLocalizedString("Only Wait Text actions can be converted to Click Text.", comment: "")
    case .missingSourceEvent:
        return NSLocalizedString("This wait row has no recorded wait event to replace. Add Click Text instead.", comment: "")
    case .sourceEventMismatch:
        return NSLocalizedString("This row no longer matches its recorded wait event. Refresh the action list, then try again.", comment: "")
    }
}

func textClickFollowUpInsertionReadinessHelp(_ readiness: TextClickConversionReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Reuse this wait target for the next text click.", comment: "")
    case .unsupportedAction:
        return NSLocalizedString("Only Wait Text actions can add a follow-up Click Text.", comment: "")
    case .missingSourceEvent:
        return NSLocalizedString("This wait row has no recorded wait event to reuse. Insert Click Text manually instead.", comment: "")
    case .sourceEventMismatch:
        return NSLocalizedString("This row no longer matches its recorded wait event. Refresh the action list, then try again.", comment: "")
    }
}

func actionRowTextTargetStatusLabel(_ readiness: TextTargetReadiness) -> String? {
    switch readiness {
    case .missingAnchor:
        return NSLocalizedString("No text target", comment: "")
    case .missingText:
        return NSLocalizedString("No target text", comment: "")
    case .notTextTarget, .ready:
        return nil
    }
}

func behaviorBindReadinessHelp(_ readiness: BehaviorBindReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Create a named behavior from the selected actions.", comment: "")
    case .noSelection:
        return NSLocalizedString("Select two or more recorded actions to create a behavior.", comment: "")
    case .needsTwoRecordedActions:
        return NSLocalizedString("Select at least two recorded actions; wait gaps alone cannot create a behavior.", comment: "")
    case .nonContiguousRecordedActions:
        return NSLocalizedString("Select one continuous block of recorded actions. Wait gaps can stay between them.", comment: "")
    case .containsBehavior:
        return NSLocalizedString("This selection already contains a behavior. Rename or unbind it before creating another.", comment: "")
    }
}

enum BehaviorRenameReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelectedBehavior
    case missingName
    case unchangedName

    var canRename: Bool {
        self == .ready
    }
}

func behaviorRenameReadiness(
    for group: ActionGroup?,
    proposedName: String
) -> BehaviorRenameReadiness {
    guard let group, group.behaviorGroupID != nil else {
        return .noSelectedBehavior
    }
    let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        return .missingName
    }
    let currentName = (group.behaviorGroupName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedName != currentName else {
        return .unchangedName
    }
    return .ready
}

func behaviorRenameReadinessHelp(_ readiness: BehaviorRenameReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Rename the selected behavior.", comment: "")
    case .noSelectedBehavior:
        return NSLocalizedString("Select one behavior to rename.", comment: "")
    case .missingName:
        return NSLocalizedString("Enter a behavior name before renaming.", comment: "")
    case .unchangedName:
        return NSLocalizedString("Change the behavior name before applying Rename.", comment: "")
    }
}

enum BatchCoordinateAlignmentReadiness: String, Codable, Equatable, Sendable {
    case ready
    case needsMultipleActions
    case firstActionHasNoCoordinate
    case noOtherCoordinateActions
    case alreadyAligned

    var canAlign: Bool {
        self == .ready
    }
}

func batchCoordinateAlignmentReadiness(
    for groups: [ActionGroup],
    alignsXCoordinate: Bool
) -> BatchCoordinateAlignmentReadiness {
    guard groups.count > 1 else { return .needsMultipleActions }
    guard let firstPoint = groups.first?.startPoint else {
        return .firstActionHasNoCoordinate
    }

    let movablePoints = groups.dropFirst().compactMap { group -> CGPoint? in
        guard !group.eventIndices.isEmpty else { return nil }
        return group.startPoint
    }
    guard !movablePoints.isEmpty else { return .noOtherCoordinateActions }

    let target = alignsXCoordinate ? firstPoint.x : firstPoint.y
    let needsMovement = movablePoints.contains { point in
        let current = alignsXCoordinate ? point.x : point.y
        return abs(current - target) > 0.0001
    }
    return needsMovement ? .ready : .alreadyAligned
}

func batchCoordinateAlignmentReadinessHelp(_ readiness: BatchCoordinateAlignmentReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Align selected coordinate actions to the first selected action.", comment: "")
    case .needsMultipleActions:
        return NSLocalizedString("Select at least two actions to align coordinates.", comment: "")
    case .firstActionHasNoCoordinate:
        return NSLocalizedString("The first selected action has no coordinate to align to.", comment: "")
    case .noOtherCoordinateActions:
        return NSLocalizedString("Select another coordinate action to align.", comment: "")
    case .alreadyAligned:
        return NSLocalizedString("Selected coordinate actions are already aligned.", comment: "")
    }
}

enum BatchTimeoutReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noTimeoutActions
    case invalidTimeout

    var canApply: Bool {
        self == .ready
    }
}

func batchTimeoutEditableGroups(
    for groups: [ActionGroup],
    events: [RecordedEvent]
) -> [ActionGroup] {
    groups.filter { group in
        guard !group.eventIndices.isEmpty else { return false }
        if group.kind.editsSemanticTextTarget { return true }
        return ActionGroupProjection.isTextTargetGroup(
            group,
            events: events,
            includesCoordinateClickCandidates: false
        )
    }
}

func batchTimeoutReadiness(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    timeout: Double
) -> BatchTimeoutReadiness {
    guard !batchTimeoutEditableGroups(for: groups, events: events).isEmpty else {
        return .noTimeoutActions
    }
    guard nonNegativeInspectorDouble(timeout) != nil else {
        return .invalidTimeout
    }
    return .ready
}

func batchTimeoutReadinessHelp(_ readiness: BatchTimeoutReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Apply this timeout to selected text-target actions.", comment: "")
    case .noTimeoutActions:
        return NSLocalizedString("Select Wait Text, Verify Text, or Click Text actions with a target to set a timeout.", comment: "")
    case .invalidTimeout:
        return NSLocalizedString("Enter a timeout of 0 or greater before applying to selected actions.", comment: "")
    }
}

enum BatchTextTargetReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noTextTargetActions
    case missingTargetText

    var canApply: Bool {
        self == .ready
    }
}

func batchTextTargetReadiness(
    for groups: [ActionGroup],
    targetText: String
) -> BatchTextTargetReadiness {
    guard !groups.isEmpty else { return .noTextTargetActions }
    guard !targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .missingTargetText
    }
    return .ready
}

func batchTextTargetReadinessHelp(_ readiness: BatchTextTargetReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Apply this target text to selected text-target actions.", comment: "")
    case .noTextTargetActions:
        return NSLocalizedString("Select text-capable actions before applying a shared target.", comment: "")
    case .missingTargetText:
        return NSLocalizedString("Enter or pick target text before applying to selected actions.", comment: "")
    }
}

func finiteInspectorDouble(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Double(trimmed), value.isFinite else { return nil }
    return value
}

func nonNegativeInspectorDouble(_ value: Double) -> Double? {
    guard value.isFinite, value >= 0 else { return nil }
    return value
}

func inspectorKeyCode(_ text: String) -> UInt16? {
    UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

enum ActionInspectorInputWarning: String, Codable, Equatable, Sendable {
    case none
    case invalidTime
    case invalidTimeout
    case invalidStartCoordinate
    case invalidEndCoordinate
    case invalidKeyCode

    var isWarning: Bool {
        self != .none
    }
}

func actionInspectorInputWarning(
    for group: ActionGroup,
    timeText: String,
    xText: String,
    yText: String,
    endXText: String,
    endYText: String,
    keyText: String,
    strategy: CoordinateStrategy,
    timeout: Double
) -> ActionInspectorInputWarning {
    guard let time = finiteInspectorDouble(timeText), time >= 0 else {
        return .invalidTime
    }

    if group.kind.editsSemanticTextTarget || (group.kind.canUseLocatorStrategy && strategy == .locatorOnly) {
        guard nonNegativeInspectorDouble(timeout) != nil else {
            return .invalidTimeout
        }
    }

    if (group.kind.editsPointTarget || group.kind.editsPathTarget),
       strategy != .locatorOnly,
       group.startPoint != nil {
        guard finiteInspectorDouble(xText) != nil,
              finiteInspectorDouble(yText) != nil else {
            return .invalidStartCoordinate
        }
    }

    if group.kind.editsPathTarget, strategy != .locatorOnly, group.endPoint != nil {
        guard finiteInspectorDouble(endXText) != nil,
              finiteInspectorDouble(endYText) != nil else {
            return .invalidEndCoordinate
        }
    }

    if group.kind.editsKeyboardInput, inspectorKeyCode(keyText) == nil {
        return .invalidKeyCode
    }

    return .none
}

func actionInspectorInputWarningHelp(_ warning: ActionInspectorInputWarning) -> String {
    switch warning {
    case .none:
        return NSLocalizedString("Inspector inputs are ready to apply.", comment: "")
    case .invalidTime:
        return NSLocalizedString("Enter a valid time or duration of 0 or greater.", comment: "")
    case .invalidTimeout:
        return NSLocalizedString("Enter a timeout of 0 or greater.", comment: "")
    case .invalidStartCoordinate:
        return NSLocalizedString("Enter valid X and Y coordinates for the action start.", comment: "")
    case .invalidEndCoordinate:
        return NSLocalizedString("Enter valid X and Y coordinates for the action end.", comment: "")
    case .invalidKeyCode:
        return NSLocalizedString("Enter a valid key code.", comment: "")
    }
}

enum ActionSelectionDeletionReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case noDeletableActions

    var canDelete: Bool {
        self == .ready
    }
}

func actionSelectionDeletionReadiness(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    liveDuration: TimeInterval
) -> ActionSelectionDeletionReadiness {
    guard !groups.isEmpty else { return .noSelection }
    let plan = ActionGroupDeletionPlanner.plan(
        for: groups,
        events: events,
        liveDuration: liveDuration
    )
    guard !plan.isEmpty else { return .noDeletableActions }
    return .ready
}

func actionSelectionDeletionReadinessHelp(_ readiness: ActionSelectionDeletionReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Delete selected actions from the macro.", comment: "")
    case .noSelection:
        return NSLocalizedString("Select actions to delete.", comment: "")
    case .noDeletableActions:
        return NSLocalizedString("Select recorded actions or wait gaps with duration to delete.", comment: "")
    }
}

enum ActionSelectionDuplicationReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case noDuplicatableActions

    var canDuplicate: Bool {
        self == .ready
    }
}

func actionSelectionDuplicationReadiness(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    liveDuration: TimeInterval
) -> ActionSelectionDuplicationReadiness {
    guard !groups.isEmpty else { return .noSelection }
    let hasEventBackedActions = groups.contains { !$0.eventIndices.isEmpty }
    let waitPlan = ActionGroupPassiveWaitDuplicationPlanner.plan(
        for: groups,
        events: events,
        liveDuration: liveDuration
    )
    guard hasEventBackedActions || !waitPlan.isEmpty else {
        return .noDuplicatableActions
    }
    return .ready
}

func actionSelectionDuplicationReadinessHelp(_ readiness: ActionSelectionDuplicationReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Duplicate selected actions or wait gaps.", comment: "")
    case .noSelection:
        return NSLocalizedString("Select actions to duplicate.", comment: "")
    case .noDuplicatableActions:
        return NSLocalizedString("Select recorded actions or wait gaps with duration to duplicate.", comment: "")
    }
}

enum ActionTrimDirection: String, Codable, Equatable, Sendable {
    case before
    case after
}

enum ActionTrimReadiness: String, Codable, Equatable, Sendable {
    case ready
    case needsSingleAction
    case noContentBefore
    case noContentAfter

    var canTrim: Bool {
        self == .ready
    }
}

func actionTrimReadiness(
    for groups: [ActionGroup],
    events: [RecordedEvent],
    liveDuration: TimeInterval,
    direction: ActionTrimDirection
) -> ActionTrimReadiness {
    guard groups.count == 1, let group = groups.first else {
        return .needsSingleAction
    }

    let epsilon: TimeInterval = 0.000_001
    switch direction {
    case .before:
        return max(0, group.startTime) > epsilon ? .ready : .noContentBefore
    case .after:
        let cutoff = max(0, group.endTime)
        let hasEventAfter: Bool
        if group.kind.isPassiveWait {
            hasEventAfter = events.contains { event in
                event.time >= cutoff - epsilon
            }
        } else {
            hasEventAfter = events.contains { event in
                event.time > cutoff + epsilon
            }
        }
        return (hasEventAfter || liveDuration > cutoff + epsilon) ? .ready : .noContentAfter
    }
}

func actionTrimReadinessHelp(
    _ readiness: ActionTrimReadiness,
    direction: ActionTrimDirection
) -> String {
    switch readiness {
    case .ready:
        switch direction {
        case .before:
            return NSLocalizedString("Remove everything before the selected action and start it at 0.", comment: "")
        case .after:
            return NSLocalizedString("Remove everything after the selected action.", comment: "")
        }
    case .needsSingleAction:
        return NSLocalizedString("Select exactly one action to trim the macro.", comment: "")
    case .noContentBefore:
        return NSLocalizedString("The selected action is already at the beginning.", comment: "")
    case .noContentAfter:
        return NSLocalizedString("The selected action is already at the end.", comment: "")
    }
}

enum ActionShiftDirection: String, Codable, Equatable, Sendable {
    case earlier
    case later
}

enum ActionShiftReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case noEventBackedActions
    case alreadyAtStart

    var canShift: Bool {
        self == .ready
    }
}

func actionShiftReadiness(
    for groups: [ActionGroup],
    direction: ActionShiftDirection
) -> ActionShiftReadiness {
    guard !groups.isEmpty else { return .noSelection }
    let eventBackedGroups = groups.filter { !$0.eventIndices.isEmpty }
    guard !eventBackedGroups.isEmpty else { return .noEventBackedActions }

    if direction == .earlier {
        let earliestStart = eventBackedGroups.map(\.startTime).min() ?? 0
        guard earliestStart > 0.000_001 else { return .alreadyAtStart }
    }

    return .ready
}

func actionShiftReadinessHelp(
    _ readiness: ActionShiftReadiness,
    direction: ActionShiftDirection
) -> String {
    switch readiness {
    case .ready:
        switch direction {
        case .earlier:
            return NSLocalizedString("Move selected recorded actions earlier.", comment: "")
        case .later:
            return NSLocalizedString("Move selected recorded actions later.", comment: "")
        }
    case .noSelection:
        return NSLocalizedString("Select recorded actions to shift their timing.", comment: "")
    case .noEventBackedActions:
        return NSLocalizedString("Wait gaps are edited with Wait Duration instead of Shift Selected.", comment: "")
    case .alreadyAtStart:
        return NSLocalizedString("The selected action is already at the beginning.", comment: "")
    }
}

enum ActionTimeStretchReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noActions
    case invalidFactor
    case unchangedFactor

    var canApply: Bool {
        self == .ready
    }
}

func actionTimeStretchReadiness(
    hasActions: Bool,
    factor: Double
) -> ActionTimeStretchReadiness {
    guard hasActions else { return .noActions }
    guard factor.isFinite, factor > 0 else {
        return .invalidFactor
    }
    guard abs(factor - 1.0) >= 0.001 else {
        return .unchangedFactor
    }
    return .ready
}

func actionTimeStretchReadinessHelp(_ readiness: ActionTimeStretchReadiness) -> String {
    switch readiness {
    case .ready:
        return NSLocalizedString("Apply this stretch factor to the full macro timeline.", comment: "")
    case .noActions:
        return NSLocalizedString("Record or insert actions before stretching time.", comment: "")
    case .invalidFactor:
        return NSLocalizedString("Choose a stretch factor greater than 0.", comment: "")
    case .unchangedFactor:
        return NSLocalizedString("Choose a stretch factor other than 1.00x.", comment: "")
    }
}

enum ActionRowReorderDirection: String, Codable, Equatable, Sendable {
    case up
    case down
}

enum ActionRowReorderReadiness: String, Codable, Equatable, Sendable {
    case ready
    case noSelection
    case noRecordedActions
    case alreadyAtTop
    case alreadyAtBottom

    var canMove: Bool {
        self == .ready
    }
}

func actionRowReorderReadiness(
    for groups: [ActionGroup],
    canMove: Bool,
    direction: ActionRowReorderDirection
) -> ActionRowReorderReadiness {
    guard !groups.isEmpty else { return .noSelection }
    guard groups.contains(where: { $0.kind.isReorderableAction && !$0.eventIndices.isEmpty }) else {
        return .noRecordedActions
    }
    guard canMove else {
        switch direction {
        case .up:
            return .alreadyAtTop
        case .down:
            return .alreadyAtBottom
        }
    }
    return .ready
}

func actionRowReorderReadinessHelp(
    _ readiness: ActionRowReorderReadiness,
    direction: ActionRowReorderDirection
) -> String {
    switch readiness {
    case .ready:
        switch direction {
        case .up:
            return NSLocalizedString("Move selected actions up", comment: "")
        case .down:
            return NSLocalizedString("Move selected actions down", comment: "")
        }
    case .noSelection:
        return NSLocalizedString("Select recorded actions to reorder them.", comment: "")
    case .noRecordedActions:
        return NSLocalizedString("Wait gaps are edited with Wait Duration instead of row reordering.", comment: "")
    case .alreadyAtTop:
        return NSLocalizedString("Selected actions are already at the top.", comment: "")
    case .alreadyAtBottom:
        return NSLocalizedString("Selected actions are already at the bottom.", comment: "")
    }
}

func actionRowReorderDisabledSummary(
    up: ActionRowReorderReadiness,
    down: ActionRowReorderReadiness
) -> String {
    if up == .noRecordedActions || down == .noRecordedActions {
        return NSLocalizedString("Wait gaps are edited with Wait Duration instead of row reordering.", comment: "")
    }
    if up == .noSelection || down == .noSelection {
        return NSLocalizedString("Select recorded actions to reorder them.", comment: "")
    }
    if up == .alreadyAtTop && down == .alreadyAtBottom {
        return NSLocalizedString("Selected actions cannot move farther.", comment: "")
    }
    if !up.canMove {
        return actionRowReorderReadinessHelp(up, direction: .up)
    }
    if !down.canMove {
        return actionRowReorderReadinessHelp(down, direction: .down)
    }
    return NSLocalizedString("Move selected actions up", comment: "")
}

func actionRowCountLabel(for group: ActionGroup) -> String? {
    guard group.eventIndices.count > 1 else { return nil }
    if group.kind.previewsPointSequence {
        return String(format: NSLocalizedString("%d points", comment: ""), max(group.path.count, group.clickCount))
    }
    if group.kind == .scroll {
        return String(format: NSLocalizedString("%d wheel ticks", comment: ""), group.eventIndices.count)
    }
    if group.kind == .sequence {
        return String(format: NSLocalizedString("%d actions", comment: ""), group.containedActionCount ?? group.eventIndices.count)
    }
    return String(format: NSLocalizedString("Merged (%d)", comment: ""), group.eventIndices.count)
}

func kindColor(_ k: RecordedEvent.Kind) -> Color {
    Brand.eventColor(k)
}

func keyName(_ code: UInt16) -> String? {
    let map: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 122: "F1", 120: "F2",
        99: "F3", 118: "F4",
        55: "⌘", 56: "⇧", 58: "⌥", 59: "⌃",
    ]
    return map[code]
}

func modifierString(flags: UInt64) -> String {
    var parts: [String] = []
    let flagsVal = NSEvent.ModifierFlags(rawValue: UInt(flags))
    if flagsVal.contains(.control) { parts.append("⌃") }
    if flagsVal.contains(.option) { parts.append("⌥") }
    if flagsVal.contains(.shift) { parts.append("⇧") }
    if flagsVal.contains(.command) { parts.append("⌘") }
    return parts.joined()
}

func shortcutName(keyCode: UInt16, flags: UInt64) -> String {
    let mods = modifierString(flags: flags)
    let key = keyName(keyCode) ?? "\(keyCode)"
    return mods + key
}

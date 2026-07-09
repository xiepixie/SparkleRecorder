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
    case .leftMouseDown:     return String(localized: "Left Click ↓", table: "EditorUX")
    case .leftMouseUp:       return String(localized: "Left Click ↑", table: "EditorUX")
    case .rightMouseDown:    return String(localized: "Right Click ↓", table: "EditorUX")
    case .rightMouseUp:      return String(localized: "Right Click ↑", table: "EditorUX")
    case .otherMouseDown:    return String(localized: "Other Click ↓", table: "EditorUX")
    case .otherMouseUp:      return String(localized: "Other Click ↑", table: "EditorUX")
    case .mouseMoved:        return String(localized: "Mouse Move", table: "Common")
    case .leftMouseDragged:  return String(localized: "Drag (L)", table: "EditorUX")
    case .rightMouseDragged: return String(localized: "Drag (R)", table: "EditorUX")
    case .otherMouseDragged: return String(localized: "Drag (Other)", table: "EditorUX")
    case .keyDown:           return String(localized: "Key Down", table: "Common")
    case .keyUp:             return String(localized: "Key Up", table: "Common")
    case .flagsChanged:      return String(localized: "Modifier", table: "Common")
    case .scrollWheel:       return String(localized: "Scroll", table: "Common")
    case .waitForText:       return String(localized: "Wait Text", table: "EditorUX")
    case .verifyText:        return String(localized: "Verify Text", table: "EditorUX")
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
    case .click: return String(localized: "Click", table: "EditorUX")
    case .doubleClick: return String(localized: "Double Click", table: "EditorUX")
    case .repeatedClick: return String(localized: "Repeated Click", table: "EditorUX")
    case .multiPointClick: return String(localized: "Multi Click", table: "EditorUX")
    case .longPress: return String(localized: "Long Press", table: "Common")
    case .drag: return String(localized: "Drag", table: "EditorUX")
    case .scroll: return String(localized: "Scroll", table: "Common")
    case .keyPress: return String(localized: "KeyPress", table: "Common")
    case .keyHold: return String(localized: "KeyHold", table: "Common")
    case .keyRepeat: return String(localized: "Key Repeat", table: "Common")
    case .shortcut: return String(localized: "Shortcut", table: "Common")
    case .modifierHold: return String(localized: "Modifier Hold", table: "Common")
    case .textInput: return String(localized: "Text Input", table: "EditorUX")
    case .waitForText: return String(localized: "Wait Text", table: "EditorUX")
    case .waitForTextGone: return String(localized: "Wait Text Gone", table: "EditorUX")
    case .verifyText: return String(localized: "Verify Text", table: "EditorUX")
    case .sequence: return String(localized: "Behavior", table: "Common")
    case .wait: return String(localized: "Wait", table: "EditorUX")
    case .mouseMove: return String(localized: "Mouse Move", table: "Common")
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
            return String(localized: "Needs target text before playback can wait.", table: "EditorUX")
        }
        return String(localized: "Waits until the target text appears, then continues. It does not click.", table: "EditorUX")
    }
    if group.kind == .waitForTextGone {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            return String(localized: "Needs target text before playback can wait.", table: "EditorUX")
        }
        return String(localized: "Waits until the target text disappears, then continues. It does not click.", table: "EditorUX")
    }
    if group.kind == .verifyText {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            return String(localized: "Needs target text before playback can verify.", table: "EditorUX")
        }
        return String(localized: "Checks the text condition once. Playback stops if the condition is not met.", table: "Automation")
    }
    if group.kind == .multiPointClick {
        return String(localized: "Clicks several coordinates in rapid sequence so they behave like one combined action.", table: "EditorUX")
    }
    if group.kind.canUseLocatorStrategy && ((event?.coordinateStrategy == .locatorOnly) || group.textAnchor != nil) {
        guard ActionGroupProjection.textAnchorIsReady(event?.textAnchor ?? group.textAnchor) else {
            if group.kind == .click {
                return String(localized: "Needs target text before playback can click.", table: "EditorUX")
            }
            return String(localized: "Needs target text before playback can locate this action.", table: "EditorUX")
        }
        if group.kind == .click {
            return String(localized: "Waits for the target text up to the timeout, then clicks the matched text box.", table: "EditorUX")
        }
        return String(localized: "Waits for the target text up to the timeout, then plays this action at the matched text box.", table: "EditorUX")
    }
    if group.kind.editsPathTarget {
        return String(localized: "Keeps the drag as one down-drag-up gesture; moving handles preserves the path shape.", table: "EditorUX")
    }
    if group.kind.isPassiveWait {
        return String(localized: "Adds time between actions without sending input.", table: "EditorUX")
    }
    if group.kind.editsKeyboardInput {
        return String(localized: "Edits the captured key and modifiers while keeping the action timing in place.", table: "Recording")
    }
    if group.kind == .sequence {
        return String(localized: "Keeps the selected events together as one behavior block while preserving their internal timing.", table: "EditorUX")
    }
    return String(localized: "Edits this action without changing the surrounding actions.", table: "EditorUX")
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
        return String(localized: "Remove the last point from this Multi Click.", table: "EditorUX")
    case .unsupportedAction:
        return String(localized: "Only Multi Click actions can remove click points.", table: "EditorUX")
    case .needsAtLeastThreePoints:
        return String(localized: "Multi Click keeps at least two points.", table: "EditorUX")
    }
}

func textClickConversionReadinessHelp(_ readiness: TextClickConversionReadiness) -> String {
    switch readiness {
    case .ready:
        return String(localized: "Replace this wait with a text click using the same target.", table: "EditorUX")
    case .unsupportedAction:
        return String(localized: "Only Wait Text actions can be converted to Click Text.", table: "EditorUX")
    case .missingSourceEvent:
        return String(localized: "This wait row has no recorded wait event to replace. Add Click Text instead.", table: "Recording")
    case .sourceEventMismatch:
        return String(localized: "This row no longer matches its recorded wait event. Refresh the action list, then try again.", table: "Recording")
    }
}

func textClickFollowUpInsertionReadinessHelp(_ readiness: TextClickConversionReadiness) -> String {
    switch readiness {
    case .ready:
        return String(localized: "Reuse this wait target for the next text click.", table: "EditorUX")
    case .unsupportedAction:
        return String(localized: "Only Wait Text actions can add a follow-up Click Text.", table: "EditorUX")
    case .missingSourceEvent:
        return String(localized: "This wait row has no recorded wait event to reuse. Insert Click Text manually instead.", table: "Recording")
    case .sourceEventMismatch:
        return String(localized: "This row no longer matches its recorded wait event. Refresh the action list, then try again.", table: "Recording")
    }
}

func actionRowTextTargetStatusLabel(_ readiness: TextTargetReadiness) -> String? {
    switch readiness {
    case .missingAnchor:
        return String(localized: "No text target", table: "EditorUX")
    case .missingText:
        return String(localized: "No target text", table: "EditorUX")
    case .notTextTarget, .ready:
        return nil
    }
}

func behaviorBindReadinessHelp(_ readiness: BehaviorBindReadiness) -> String {
    switch readiness {
    case .ready:
        return String(localized: "Create a named behavior from the selected actions.", table: "EditorUX")
    case .noSelection:
        return String(localized: "Select two or more recorded actions to create a behavior.", table: "Recording")
    case .needsTwoRecordedActions:
        return String(localized: "Select at least two recorded actions; wait gaps alone cannot create a behavior.", table: "Recording")
    case .nonContiguousRecordedActions:
        return String(localized: "Select one continuous block of recorded actions. Wait gaps can stay between them.", table: "Recording")
    case .containsBehavior:
        return String(localized: "This selection already contains a behavior. Rename or unbind it before creating another.", table: "Automation")
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
        return String(localized: "Rename the selected behavior.", table: "Common")
    case .noSelectedBehavior:
        return String(localized: "Select one behavior to rename.", table: "Automation")
    case .missingName:
        return String(localized: "Enter a behavior name before renaming.", table: "Automation")
    case .unchangedName:
        return String(localized: "Change the behavior name before applying Rename.", table: "Automation")
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
        return String(localized: "Align selected coordinate actions to the first selected action.", table: "EditorUX")
    case .needsMultipleActions:
        return String(localized: "Select at least two actions to align coordinates.", table: "EditorUX")
    case .firstActionHasNoCoordinate:
        return String(localized: "The first selected action has no coordinate to align to.", table: "EditorUX")
    case .noOtherCoordinateActions:
        return String(localized: "Select another coordinate action to align.", table: "EditorUX")
    case .alreadyAligned:
        return String(localized: "Selected coordinate actions are already aligned.", table: "EditorUX")
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
        return String(localized: "Apply this timeout to selected text-target actions.", table: "EditorUX")
    case .noTimeoutActions:
        return String(localized: "Select Wait Text, Verify Text, or Click Text actions with a target to set a timeout.", table: "EditorUX")
    case .invalidTimeout:
        return String(localized: "Enter a timeout of 0 or greater before applying to selected actions.", table: "EditorUX")
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
        return String(localized: "Apply this target text to selected text-target actions.", table: "EditorUX")
    case .noTextTargetActions:
        return String(localized: "Select text-capable actions before applying a shared target.", table: "EditorUX")
    case .missingTargetText:
        return String(localized: "Enter or pick target text before applying to selected actions.", table: "EditorUX")
    }
}

func finiteInspectorDouble(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let value = Double(trimmed), value.isFinite {
        return value
    }
    
    // Fallback: parse HH:MM:SS.s or MM:SS.s
    let parts = trimmed.split(separator: ":")
    if parts.count == 2 || parts.count == 3 {
        var totalSeconds: Double = 0
        let reversedParts = parts.reversed().map { String($0) }
        
        // seconds
        if let sec = Double(reversedParts[0]), sec.isFinite, sec >= 0, sec < 60 {
            totalSeconds += sec
        } else {
            return nil
        }
        
        // minutes
        if let min = Double(reversedParts[1]), min.isFinite, min >= 0 {
            totalSeconds += min * 60
        } else {
            return nil
        }
        
        // hours
        if reversedParts.count == 3 {
            if let hr = Double(reversedParts[2]), hr.isFinite, hr >= 0 {
                totalSeconds += hr * 3600
            } else {
                return nil
            }
        }
        
        return totalSeconds
    }
    
    return nil
}

func formatInspectorTime(_ time: Double) -> String {
    let isNegative = time < 0
    let absTime = abs(time)
    let totalSeconds = Int(absTime)
    let fractional = absTime.truncatingRemainder(dividingBy: 1)
    
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    
    let prefix = isNegative ? "-" : ""
    
    let fracStr = fractional > 0 ? String(String(format: "%.4f", fractional).dropFirst(1)) : ""
    
    if hours > 0 {
        return String(format: "%@%02d:%02d:%02d%@", prefix, hours, minutes, seconds, fracStr)
    } else if minutes > 0 {
        return String(format: "%@%02d:%02d%@", prefix, minutes, seconds, fracStr)
    } else {
        return String(format: "%@%.4f", prefix, absTime)
    }
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
        return String(localized: "Inspector inputs are ready to apply.", table: "Automation")
    case .invalidTime:
        return String(localized: "Enter a valid time or duration of 0 or greater.", table: "Automation")
    case .invalidTimeout:
        return String(localized: "Enter a timeout of 0 or greater.", table: "Automation")
    case .invalidStartCoordinate:
        return String(localized: "Enter valid X and Y coordinates for the action start.", table: "EditorUX")
    case .invalidEndCoordinate:
        return String(localized: "Enter valid X and Y coordinates for the action end.", table: "EditorUX")
    case .invalidKeyCode:
        return String(localized: "Enter a valid key code.", table: "Automation")
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
        return String(localized: "Delete selected actions from the macro.", table: "EditorUX")
    case .noSelection:
        return String(localized: "Select actions to delete.", table: "EditorUX")
    case .noDeletableActions:
        return String(localized: "Select recorded actions or wait gaps with duration to delete.", table: "Recording")
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
        return String(localized: "Duplicate selected actions or wait gaps.", table: "EditorUX")
    case .noSelection:
        return String(localized: "Select actions to duplicate.", table: "EditorUX")
    case .noDuplicatableActions:
        return String(localized: "Select recorded actions or wait gaps with duration to duplicate.", table: "Recording")
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
            return String(localized: "Remove everything before the selected action and start it at 0.", table: "EditorUX")
        case .after:
            return String(localized: "Remove everything after the selected action.", table: "EditorUX")
        }
    case .needsSingleAction:
        return String(localized: "Select exactly one action to trim the macro.", table: "EditorUX")
    case .noContentBefore:
        return String(localized: "The selected action is already at the beginning.", table: "EditorUX")
    case .noContentAfter:
        return String(localized: "The selected action is already at the end.", table: "EditorUX")
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
            return String(localized: "Move selected recorded actions earlier.", table: "Recording")
        case .later:
            return String(localized: "Move selected recorded actions later.", table: "Recording")
        }
    case .noSelection:
        return String(localized: "Select recorded actions to shift their timing.", table: "Recording")
    case .noEventBackedActions:
        return String(localized: "Wait gaps are edited with Wait Duration instead of Shift Selected.", table: "EditorUX")
    case .alreadyAtStart:
        return String(localized: "The selected action is already at the beginning.", table: "EditorUX")
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
        return String(localized: "Apply this stretch factor to the full macro timeline.", table: "EditorUX")
    case .noActions:
        return String(localized: "Record or insert actions before stretching time.", table: "Recording")
    case .invalidFactor:
        return String(localized: "Choose a stretch factor greater than 0.", table: "Automation")
    case .unchangedFactor:
        return String(localized: "Choose a stretch factor other than 1.00x.", table: "Automation")
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
            return String(localized: "Move selected actions up", table: "EditorUX")
        case .down:
            return String(localized: "Move selected actions down", table: "EditorUX")
        }
    case .noSelection:
        return String(localized: "Select recorded actions to reorder them.", table: "Recording")
    case .noRecordedActions:
        return String(localized: "Wait gaps are edited with Wait Duration instead of row reordering.", table: "EditorUX")
    case .alreadyAtTop:
        return String(localized: "Selected actions are already at the top.", table: "EditorUX")
    case .alreadyAtBottom:
        return String(localized: "Selected actions are already at the bottom.", table: "EditorUX")
    }
}

func actionRowReorderDisabledSummary(
    up: ActionRowReorderReadiness,
    down: ActionRowReorderReadiness
) -> String {
    if up == .noRecordedActions || down == .noRecordedActions {
        return String(localized: "Wait gaps are edited with Wait Duration instead of row reordering.", table: "EditorUX")
    }
    if up == .noSelection || down == .noSelection {
        return String(localized: "Select recorded actions to reorder them.", table: "Recording")
    }
    if up == .alreadyAtTop && down == .alreadyAtBottom {
        return String(localized: "Selected actions cannot move farther.", table: "EditorUX")
    }
    if !up.canMove {
        return actionRowReorderReadinessHelp(up, direction: .up)
    }
    if !down.canMove {
        return actionRowReorderReadinessHelp(down, direction: .down)
    }
    return String(localized: "Move selected actions up", table: "EditorUX")
}

func actionRowCountLabel(for group: ActionGroup) -> String? {
    guard group.eventIndices.count > 1 else { return nil }
    if group.kind.previewsPointSequence {
        return String(format: String(localized: "%d points", table: "Common"), max(group.path.count, group.clickCount))
    }
    if group.kind == .scroll {
        return String(format: String(localized: "%d wheel ticks", table: "Common"), group.eventIndices.count)
    }
    if group.kind == .sequence {
        return String(format: String(localized: "%d actions", table: "EditorUX"), group.containedActionCount ?? group.eventIndices.count)
    }
    return String(format: String(localized: "Merged (%d)", table: "Common"), group.eventIndices.count)
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

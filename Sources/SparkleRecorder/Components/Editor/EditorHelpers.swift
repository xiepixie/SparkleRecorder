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
    case .waitForText:       return NSLocalizedString("Wait for text", comment: "")
    case .verifyText:        return NSLocalizedString("Verify text", comment: "")
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
    case .waitForText: return Brand.sigAmber
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
    case .waitForText: return NSLocalizedString("Wait For Text", comment: "")
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
        self == .waitForText || self == .verifyText
    }

    var canUseLocatorStrategy: Bool {
        editsPointTarget && self != .multiPointClick
    }

    var canRetargetCoordinate: Bool {
        isClickFamily || editsPathTarget
    }

    var canConvertClickType: Bool {
        isClickFamily
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
        case .waitForText, .verifyText, .scroll:
            return 1
        default:
            return 0
        }
    }
}

func actionWorkflowMessage(for group: ActionGroup, event: RecordedEvent?) -> String {
    if group.kind == .waitForText {
        return NSLocalizedString("Waits until the target text appears, then continues. It does not click.", comment: "")
    }
    if group.kind == .verifyText {
        return NSLocalizedString("Checks the text condition once. Playback stops if the condition is not met.", comment: "")
    }
    if group.kind == .multiPointClick {
        return NSLocalizedString("Clicks several coordinates in rapid sequence so they behave like one combined action.", comment: "")
    }
    if group.kind.canUseLocatorStrategy && ((event?.coordinateStrategy == .locatorOnly) || group.textAnchor != nil) {
        if group.kind == .click {
            return NSLocalizedString("Finds the target text, then clicks the center of the matched text box.", comment: "")
        }
        return NSLocalizedString("Finds the target text, then plays this action at the matched text box.", comment: "")
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

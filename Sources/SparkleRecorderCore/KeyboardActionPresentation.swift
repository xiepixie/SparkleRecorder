import Foundation

/// Shared semantic presentation for recorded keyboard input.
///
/// Keyboard shortcuts must be derived from physical key code + modifier flags, not
/// `unicodeString`: Option/Command combinations can produce layout-dependent text
/// such as `™`, while special keys and modifier-only events may have no readable
/// Unicode payload at all. Keeping this logic in Core gives the Editor, AI review,
/// CLI/tests, and future surfaces one stable interpretation.
public enum KeyboardActionPresentation {
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    public static func keyName(_ code: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";",
            42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            54: "⌘", 55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥", 59: "⌃",
            60: "⇧", 61: "⌥", 62: "⌃", 63: "fn",
            65: ".", 67: "×", 69: "+", 71: "Clear", 75: "÷", 76: "Enter",
            78: "−", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
            87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up",
            117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
            121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[code]
    }

    public static func modifierGlyphs(flags: UInt64) -> String {
        var parts: [String] = []
        if flags & ModFlag.control != 0 { parts.append("⌃") }
        if flags & ModFlag.option != 0 { parts.append("⌥") }
        if flags & ModFlag.shift != 0 { parts.append("⇧") }
        if flags & ModFlag.command != 0 { parts.append("⌘") }
        if flags & ModFlag.fn != 0 { parts.append("fn") }
        return parts.joined()
    }

    public static func shortcutName(keyCode: UInt16, flags: UInt64) -> String {
        let key = keyName(keyCode) ?? "\(keyCode)"
        if modifierKeyCodes.contains(keyCode) {
            return key
        }
        return modifierGlyphs(flags: flags) + key
    }

    public static func label(
        kind: ActionGroupKind,
        eventIndices: [Int],
        events: [RecordedEvent]
    ) -> String? {
        let validEvents = eventIndices.compactMap { index in
            events.indices.contains(index) ? events[index] : nil
        }
        guard !validEvents.isEmpty else { return nil }

        if kind == .textInput {
            let text = validEvents
                .filter { $0.kind == .keyDown }
                .compactMap(\.unicodeString)
                .joined()
            if !text.isEmpty { return text }
        }

        let representative = validEvents.first(where: { event in
            event.kind == .keyDown && !modifierKeyCodes.contains(event.keyCode)
        }) ?? validEvents.first(where: { $0.kind == .keyDown })
            ?? validEvents.first(where: { $0.kind == .flagsChanged })
            ?? validEvents.first(where: { $0.kind == .keyUp })

        guard let representative else { return nil }
        return shortcutName(keyCode: representative.keyCode, flags: representative.flags)
    }
}

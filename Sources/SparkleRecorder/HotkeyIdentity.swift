import Carbon.HIToolbox
import SparkleRecorderCore

struct HotkeyIdentity: Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(_ binding: HotkeyBinding) {
        self.init(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }
}

extension HotkeyBinding {
    var hotkeyIdentity: HotkeyIdentity {
        HotkeyIdentity(self)
    }

    var recordingIgnoredKeyChord: RecordingIgnoredKeyChord {
        var flags: UInt64 = 0
        if modifiers & UInt32(cmdKey) != 0 { flags |= ModFlag.command }
        if modifiers & UInt32(shiftKey) != 0 { flags |= ModFlag.shift }
        if modifiers & UInt32(controlKey) != 0 { flags |= ModFlag.control }
        if modifiers & UInt32(optionKey) != 0 { flags |= ModFlag.option }
        return RecordingIgnoredKeyChord(
            keyCode: UInt16(clamping: keyCode),
            modifiers: flags
        )
    }
}

enum HotkeyConflictPolicy {
    static func conflicts(_ lhs: HotkeyBinding, _ rhs: HotkeyBinding) -> Bool {
        lhs.hotkeyIdentity == rhs.hotkeyIdentity
    }
}

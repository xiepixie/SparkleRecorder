import Foundation

public enum PlaybackMouseButton: Equatable, Sendable {
    case left
    case right
    case other(Int64)

    public var eventButtonNumber: Int64 {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        case .other(let buttonNumber):
            return buttonNumber
        }
    }
}

public struct PlaybackKeyboardSpec: Equatable, Sendable {
    public var keyCode: UInt16
    public var keyDown: Bool
    public var flags: UInt64

    public init(keyCode: UInt16, keyDown: Bool, flags: UInt64) {
        self.keyCode = keyCode
        self.keyDown = keyDown
        self.flags = flags
    }
}

public struct PlaybackFlagsChangedSpec: Equatable, Sendable {
    public var keyCode: UInt16
    public var flags: UInt64

    public init(keyCode: UInt16, flags: UInt64) {
        self.keyCode = keyCode
        self.flags = flags
    }
}

public struct PlaybackMouseSpec: Equatable, Sendable {
    public var button: PlaybackMouseButton
    public var buttonNumber: Int64
    public var clickState: Int64?
    public var flags: UInt64

    public init(
        button: PlaybackMouseButton,
        buttonNumber: Int64,
        clickState: Int64?,
        flags: UInt64
    ) {
        self.button = button
        self.buttonNumber = buttonNumber
        self.clickState = clickState
        self.flags = flags
    }
}

public enum PlaybackInputPlan: Equatable, Sendable {
    case keyboard(PlaybackKeyboardSpec)
    case flagsChanged(PlaybackFlagsChangedSpec)
    case scroll(PlaybackScrollSpec)
    case mouse(PlaybackMouseSpec)
}

public enum PlaybackInputPlanner {
    public static func plan(for event: RecordedEvent) -> PlaybackInputPlan? {
        switch event.kind {
        case .keyDown:
            return .keyboard(PlaybackKeyboardSpec(keyCode: event.keyCode, keyDown: true, flags: event.flags))
        case .keyUp:
            return .keyboard(PlaybackKeyboardSpec(keyCode: event.keyCode, keyDown: false, flags: event.flags))
        case .flagsChanged:
            return .flagsChanged(PlaybackFlagsChangedSpec(keyCode: event.keyCode, flags: event.flags))
        case .scrollWheel:
            return .scroll(PlaybackScrollPlanner.spec(for: event))
        case .waitForText, .verifyText:
            return nil
        default:
            return .mouse(mouseSpec(for: event))
        }
    }

    public static func mouseSpec(for event: RecordedEvent) -> PlaybackMouseSpec {
        let button = mouseButton(for: event)
        return PlaybackMouseSpec(
            button: button,
            buttonNumber: event.mouseButton,
            clickState: clickState(for: event),
            flags: event.flags
        )
    }

    public static func mouseButton(for event: RecordedEvent) -> PlaybackMouseButton {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved:
            return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return .other(event.mouseButton)
        default:
            return .left
        }
    }

    public static func clickState(for event: RecordedEvent) -> Int64? {
        if event.clickCount > 0 {
            return event.clickCount
        }

        return isClickOrDrag(event.kind) ? 1 : nil
    }

    public static func isClickOrDrag(_ kind: RecordedEvent.Kind) -> Bool {
        switch kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

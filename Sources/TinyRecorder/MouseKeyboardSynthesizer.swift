import Foundation
import CoreGraphics

public protocol EventPosting {
    func post(_ event: RecordedEvent, at point: CGPoint)
}

public final class CGEventPoster: EventPosting {
    public init() {}
    
    private func cgEventType(for kind: RecordedEvent.Kind) -> CGEventType? {
        switch kind {
        case .leftMouseDown: return .leftMouseDown
        case .leftMouseUp: return .leftMouseUp
        case .rightMouseDown: return .rightMouseDown
        case .rightMouseUp: return .rightMouseUp
        case .mouseMoved: return .mouseMoved
        case .leftMouseDragged: return .leftMouseDragged
        case .rightMouseDragged: return .rightMouseDragged
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .flagsChanged: return .flagsChanged
        case .scrollWheel: return .scrollWheel
        case .otherMouseDown: return .otherMouseDown
        case .otherMouseUp: return .otherMouseUp
        case .otherMouseDragged: return .otherMouseDragged
        }
    }

    public func post(_ ev: RecordedEvent, at point: CGPoint) {
        guard let cgType = cgEventType(for: ev.kind) else { return }

        if ev.kind.isMouse || ev.kind == .scrollWheel {
            CGWarpMouseCursorPosition(point)
            _ = CGAssociateMouseAndMouseCursorPosition(1)
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        switch ev.kind {
        case .keyDown, .keyUp:
            if let cgEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(ev.keyCode),
                keyDown: ev.kind == .keyDown
            ) {
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                cgEvent.post(tap: .cghidEventTap)
            }

        case .flagsChanged:
            if let cgEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(ev.keyCode),
                keyDown: false
            ) {
                cgEvent.type = .flagsChanged
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                cgEvent.post(tap: .cghidEventTap)
            }

        case .scrollWheel:
            if let cgEvent = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: ev.scrollDeltaY,
                wheel2: ev.scrollDeltaX,
                wheel3: 0
            ) {
                cgEvent.location = point
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                cgEvent.post(tap: .cghidEventTap)
            }

        default:
            // Mouse events
            let button: CGMouseButton
            switch ev.kind {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                button = .left
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                button = .right
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                button = CGMouseButton(rawValue: UInt32(ev.mouseButton)) ?? .center
            case .mouseMoved:
                button = .left
            default:
                button = .left
            }

            if let cgEvent = CGEvent(
                mouseEventSource: source,
                mouseType: cgType,
                mouseCursorPosition: point,
                mouseButton: button
            ) {
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: ev.mouseButton)
                
                let isClickOrDrag = ev.kind == .leftMouseDown || ev.kind == .leftMouseUp || ev.kind == .leftMouseDragged ||
                                    ev.kind == .rightMouseDown || ev.kind == .rightMouseUp || ev.kind == .rightMouseDragged ||
                                    ev.kind == .otherMouseDown || ev.kind == .otherMouseUp || ev.kind == .otherMouseDragged
                let clickState = ev.clickCount > 0 ? ev.clickCount : (isClickOrDrag ? 1 : 0)
                if clickState > 0 {
                    cgEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
                }
                
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                cgEvent.post(tap: .cghidEventTap)
            }
        }
    }
}

public final class MouseKeyboardSynthesizer {
    private let poster: EventPosting

    public init(poster: EventPosting = CGEventPoster()) {
        self.poster = poster
    }

    public func synthesize(_ event: RecordedEvent, at point: CGPoint) {
        poster.post(event, at: point)
    }
}

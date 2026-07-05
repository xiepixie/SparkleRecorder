import Foundation
import CoreGraphics

public protocol EventPosting {
    func post(_ event: RecordedEvent, at point: CGPoint)
}

public final class CGEventPoster: EventPosting {
    public init() {}

    private let loopbackMagic: Int64 = 0x535041524B4C4521
    private var lastScrollCursorPoint: CGPoint?
    
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
        case .waitForText, .verifyText: return nil
        }
    }

    public func post(_ ev: RecordedEvent, at point: CGPoint) {
        guard let cgType = cgEventType(for: ev.kind) else { return }

        // Removed CGWarpMouseCursorPosition because it stalls WindowServer at 60Hz.
        // CGEvent(mouseEventSource:...) natively updates the cursor location on macOS.

        let source = CGEventSource(stateID: .combinedSessionState)

        switch ev.kind {
        case .keyDown, .keyUp:
            if let cgEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(ev.keyCode),
                keyDown: ev.kind == .keyDown
            ) {
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
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
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
                cgEvent.post(tap: .cghidEventTap)
            }

        case .scrollWheel:
            let scrollSource = Self.makeScrollEventSource(loopbackMagic: loopbackMagic)
            placeCursorForScroll(at: point, source: scrollSource, flags: ev.flags)
            let spec = Self.scrollPlaybackSpec(for: ev)
            if let cgEvent = CGEvent(
                scrollWheelEvent2Source: scrollSource,
                units: spec.units,
                wheelCount: 2,
                wheel1: spec.wheelY,
                wheel2: spec.wheelX,
                wheel3: 0
            ) {
                cgEvent.location = point
                cgEvent.flags = CGEventFlags(rawValue: ev.flags)
                if spec.isContinuous {
                    cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    if let phase = spec.phase, phase != 0 {
                        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
                    }
                    if let momentum = spec.momentumPhase {
                        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum))
                    }
                }
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
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
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
                cgEvent.post(tap: .cghidEventTap)
            }
        }
    }

    static func effectiveScrollPointDelta(recorded: Int32, payload: CGFloat?) -> Int32 {
        guard let payload else { return recorded }
        let rounded = Int32(payload.rounded())
        return rounded == 0 ? recorded : rounded
    }

    static func effectiveScrollLineDelta(recorded: Int32, payload: Int32?) -> Int32 {
        if let payload, payload != 0 { return payload }
        guard recorded != 0 else { return 0 }
        let scaled = Double(recorded) / 12.0
        if abs(scaled) >= 1 {
            return Int32(scaled.rounded())
        }
        return recorded > 0 ? 1 : -1
    }

    static func shouldUseLineScroll(payload: ScrollPayload?, lineY: Int32, lineX: Int32) -> Bool {
        guard let payload else { return false }
        guard !payload.isContinuous else { return false }
        return (lineY != 0 || lineX != 0)
    }

    struct ScrollPlaybackSpec: Equatable {
        var units: CGScrollEventUnit
        var wheelY: Int32
        var wheelX: Int32
        var isContinuous: Bool
        var phase: Int?
        var momentumPhase: Int?
    }

    static func scrollPlaybackSpec(for event: RecordedEvent) -> ScrollPlaybackSpec {
        let lineY = effectiveScrollLineDelta(recorded: event.scrollDeltaY, payload: event.scrollPayload?.lineDeltaY)
        let lineX = effectiveScrollLineDelta(recorded: event.scrollDeltaX, payload: event.scrollPayload?.lineDeltaX)
        let useLineUnits = shouldUseLineScroll(payload: event.scrollPayload, lineY: lineY, lineX: lineX)
        if useLineUnits {
            return ScrollPlaybackSpec(
                units: .line,
                wheelY: lineY,
                wheelX: lineX,
                isContinuous: false,
                phase: nil,
                momentumPhase: nil
            )
        }

        let pointY = effectiveScrollPointDelta(recorded: event.scrollDeltaY, payload: event.scrollPayload?.deltaY)
        let pointX = effectiveScrollPointDelta(recorded: event.scrollDeltaX, payload: event.scrollPayload?.deltaX)
        return ScrollPlaybackSpec(
            units: .pixel,
            wheelY: pointY,
            wheelX: pointX,
            isContinuous: event.scrollPayload?.isContinuous ?? false,
            phase: event.scrollPayload?.phase,
            momentumPhase: event.scrollPayload?.momentumPhase
        )
    }

    private static func makeScrollEventSource(loopbackMagic: Int64) -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState) ?? CGEventSource(stateID: .combinedSessionState)
        source?.pixelsPerLine = 12
        source?.localEventsSuppressionInterval = 0
        source?.userData = loopbackMagic
        return source
    }

    private func placeCursorForScroll(at point: CGPoint, source: CGEventSource?, flags: UInt64) {
        let shouldMove: Bool = {
            guard let last = lastScrollCursorPoint else { return true }
            return hypot(last.x - point.x, last.y - point.y) > 1.0
        }()
        
        if shouldMove {
            // macOS WindowServer will suppress scroll events immediately after a sudden 
            // CGWarpMouseCursorPosition jump. By posting a standard mouseMoved event instead, 
            // we bypass the strict warp suppression.
            postMouseMove(to: point, source: source, flags: flags)
            lastScrollCursorPoint = point
            
            // Wait 50ms to ensure the target app's hit-testing and Hover states are updated.
            // Without this, the scroll might visually happen at the cursor, but the app 
            // ignores it because its internal state hasn't registered the cursor's presence.
            Thread.sleep(forTimeInterval: 0.05)
        } else {
            // For continuous scroll wheel events that don't move the cursor, just a tiny delay.
            Thread.sleep(forTimeInterval: 0.004)
        }
    }

    private func postMouseMove(to point: CGPoint, source: CGEventSource?, flags: UInt64) {
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        move.flags = CGEventFlags(rawValue: flags)
        move.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
        move.post(tap: .cghidEventTap)
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

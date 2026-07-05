import CoreGraphics
import Foundation
import os
import SparkleRecorderCore

public protocol EventPosting: AnyObject {
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
        guard let plan = PlaybackInputPlanner.plan(for: ev) else { return }

        // Removed CGWarpMouseCursorPosition because it stalls WindowServer at 60Hz.
        // CGEvent(mouseEventSource:...) natively updates the cursor location on macOS.

        let source = CGEventSource(stateID: .combinedSessionState)

        switch plan {
        case .keyboard(let spec):
            if let cgEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(spec.keyCode),
                keyDown: spec.keyDown
            ) {
                cgEvent.flags = CGEventFlags(rawValue: spec.flags)
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
                cgEvent.post(tap: .cghidEventTap)
            }

        case .flagsChanged(let spec):
            if let cgEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(spec.keyCode),
                keyDown: false
            ) {
                cgEvent.type = .flagsChanged
                cgEvent.flags = CGEventFlags(rawValue: spec.flags)
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
                cgEvent.post(tap: .cghidEventTap)
            }

        case .scroll(let spec):
            let scrollSource = Self.makeScrollEventSource(loopbackMagic: loopbackMagic)
            placeCursorForScroll(at: point, source: scrollSource, flags: ev.flags)
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

        case .mouse(let spec):
            if let cgEvent = CGEvent(
                mouseEventSource: source,
                mouseType: cgType,
                mouseCursorPosition: point,
                mouseButton: spec.button.cgMouseButton
            ) {
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: spec.buttonNumber)

                if let clickState = spec.clickState {
                    cgEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
                }
                
                cgEvent.flags = CGEventFlags(rawValue: spec.flags)
                cgEvent.setIntegerValueField(.eventSourceUserData, value: loopbackMagic)
                cgEvent.post(tap: .cghidEventTap)
            }
        }
    }

    static func effectiveScrollPointDelta(recorded: Int32, payload: CGFloat?) -> Int32 {
        PlaybackScrollPlanner.effectivePointDelta(recorded: recorded, payload: payload)
    }

    static func effectiveScrollLineDelta(recorded: Int32, payload: Int32?) -> Int32 {
        PlaybackScrollPlanner.effectiveLineDelta(recorded: recorded, payload: payload)
    }

    static func shouldUseLineScroll(payload: ScrollPayload?, lineY: Int32, lineX: Int32) -> Bool {
        PlaybackScrollPlanner.shouldUseLineScroll(payload: payload, lineY: lineY, lineX: lineX)
    }

    static func scrollPlaybackSpec(for event: RecordedEvent) -> PlaybackScrollSpec {
        PlaybackScrollPlanner.spec(for: event)
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

private extension PlaybackMouseButton {
    var cgMouseButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .other(let buttonNumber):
            return CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center
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

public final class LockedEventPoster: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let synthesizer: MouseKeyboardSynthesizer

    public init(synthesizer: MouseKeyboardSynthesizer = MouseKeyboardSynthesizer()) {
        self.synthesizer = synthesizer
    }

    public func post(_ event: RecordedEvent, at point: CGPoint) {
        lock.withLock {
            synthesizer.synthesize(event, at: point)
        }
    }
}

public extension EventPosterClient {
    static func live(poster: LockedEventPoster = LockedEventPoster()) -> EventPosterClient {
        EventPosterClient { event, point in
            poster.post(event, at: point)
        }
    }
}

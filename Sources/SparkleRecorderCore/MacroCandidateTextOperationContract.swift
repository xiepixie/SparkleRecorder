import Foundation

public enum MacroCandidateTextOperationViolation: Equatable, Sendable {
    case missingTextAnchor(index: Int)
    case missingSurface(index: Int)
    case unknownSurface(index: Int, id: String)
    case locatorRequiresMouseEvent(index: Int)
    case locatorRequiresTargetWindowBinding(index: Int)
    case locatorRequiresLocatorOnlyStrategy(index: Int)
    case pointerGestureLocatorMismatch(index: Int, downIndex: Int)
    case locatorDrivenPointerGestureCannotDrag(index: Int, downIndex: Int)
}

/// Owns the executable semantics of text-backed candidate operations. Schema and
/// numeric validation remain in MacroCandidateValidator; this Module answers the
/// higher-level question "would these fields execute as one coherent text action?".
public enum MacroCandidateTextOperationContract {
    private struct LocatorSignature: Equatable {
        var surfaceID: String
        var anchor: TextAnchor
        var fallbackPolicy: LocatorFallbackPolicy
        var timeout: TimeInterval?
    }

    private struct ActivePointer {
        var downIndex: Int
        var locator: LocatorSignature?
    }

    public static func violation(
        events: [RecordedEvent],
        surfaces: [String: PlaybackSurface]
    ) -> MacroCandidateTextOperationViolation? {
        var activePointers: [Int64: ActivePointer] = [:]

        for (index, event) in events.enumerated() {
            let isObservation = event.kind == .waitForText || event.kind == .verifyText
            let hasTextTarget = event.textAnchor != nil || event.coordinateStrategy == .locatorOnly || isObservation

            if hasTextTarget {
                guard event.textAnchor != nil else {
                    return .missingTextAnchor(index: index)
                }
                guard let surfaceID = event.surfaceId else {
                    return .missingSurface(index: index)
                }
                guard surfaces[surfaceID] != nil else {
                    return .unknownSurface(index: index, id: surfaceID)
                }

                if !isObservation {
                    guard event.kind.isMouse else {
                        return .locatorRequiresMouseEvent(index: index)
                    }
                    guard event.coordinateStrategy == .locatorOnly else {
                        return .locatorRequiresLocatorOnlyStrategy(index: index)
                    }
                    guard event.coordinateBinding == .targetWindow else {
                        return .locatorRequiresTargetWindowBinding(index: index)
                    }
                }
            }

            guard event.isDisabled != true else { continue }

            switch event.kind {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                let button = buttonNumber(event)
                activePointers[button] = ActivePointer(
                    downIndex: index,
                    locator: locatorSignature(event)
                )

            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                let button = buttonNumber(event)
                if let active = activePointers[button], active.locator != nil {
                    return .locatorDrivenPointerGestureCannotDrag(index: index, downIndex: active.downIndex)
                }

            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                let button = buttonNumber(event)
                if let active = activePointers[button] {
                    let releaseLocator = locatorSignature(event)
                    if active.locator != releaseLocator {
                        return .pointerGestureLocatorMismatch(index: index, downIndex: active.downIndex)
                    }
                    activePointers.removeValue(forKey: button)
                }

            default:
                break
            }
        }
        return nil
    }

    private static func locatorSignature(_ event: RecordedEvent) -> LocatorSignature? {
        guard let anchor = event.textAnchor,
              event.coordinateStrategy == .locatorOnly,
              event.coordinateBinding == .targetWindow,
              let surfaceID = event.surfaceId else {
            return nil
        }
        return LocatorSignature(
            surfaceID: surfaceID,
            anchor: anchor,
            fallbackPolicy: event.locatorFallbackPolicy ?? .fail,
            timeout: event.textTimeout
        )
    }

    private static func buttonNumber(_ event: RecordedEvent) -> Int64 {
        switch event.kind {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return 0
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return 1
        default:
            return event.mouseButton
        }
    }
}

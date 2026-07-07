import CoreGraphics
import Foundation

public enum PlaybackScrollUnit: Equatable, Sendable {
    case line
    case pixel
}

public struct PlaybackScrollSpec: Equatable, Sendable {
    public var unit: PlaybackScrollUnit
    public var wheelY: Int32
    public var wheelX: Int32
    public var isContinuous: Bool
    public var phase: Int?
    public var momentumPhase: Int?

    public init(
        unit: PlaybackScrollUnit,
        wheelY: Int32,
        wheelX: Int32,
        isContinuous: Bool,
        phase: Int? = nil,
        momentumPhase: Int? = nil
    ) {
        self.unit = unit
        self.wheelY = wheelY
        self.wheelX = wheelX
        self.isContinuous = isContinuous
        self.phase = phase
        self.momentumPhase = momentumPhase
    }

    public var units: CGScrollEventUnit {
        switch unit {
        case .line:
            return .line
        case .pixel:
            return .pixel
        }
    }
}

public enum PlaybackScrollPlanner {
    public static let lineToPointScale = 12.0

    public static func effectivePointDelta(recorded: Int32, payload: CGFloat?) -> Int32 {
        guard let payload, payload.isFinite else { return recorded }
        let rounded = clampedInt32(payload.rounded())
        return rounded == 0 ? recorded : rounded
    }

    public static func effectiveLineDelta(recorded: Int32, payload: Int32?) -> Int32 {
        if let payload, payload != 0 { return payload }
        guard recorded != 0 else { return 0 }

        let scaled = Double(recorded) / lineToPointScale
        if abs(scaled) >= 1 {
            return clampedInt32(scaled.rounded())
        }
        return recorded > 0 ? 1 : -1
    }

    public static func shouldUseLineScroll(payload: ScrollPayload?, lineY: Int32, lineX: Int32) -> Bool {
        guard let payload else { return false }
        guard !payload.isContinuous else { return false }
        return lineY != 0 || lineX != 0
    }

    public static func spec(for event: RecordedEvent) -> PlaybackScrollSpec {
        let lineY = effectiveLineDelta(recorded: event.scrollDeltaY, payload: event.scrollPayload?.lineDeltaY)
        let lineX = effectiveLineDelta(recorded: event.scrollDeltaX, payload: event.scrollPayload?.lineDeltaX)
        let useLineUnits = shouldUseLineScroll(payload: event.scrollPayload, lineY: lineY, lineX: lineX)

        if useLineUnits {
            return PlaybackScrollSpec(
                unit: .line,
                wheelY: lineY,
                wheelX: lineX,
                isContinuous: false
            )
        }

        return PlaybackScrollSpec(
            unit: .pixel,
            wheelY: effectivePointDelta(recorded: event.scrollDeltaY, payload: event.scrollPayload?.deltaY),
            wheelX: effectivePointDelta(recorded: event.scrollDeltaX, payload: event.scrollPayload?.deltaX),
            isContinuous: event.scrollPayload?.isContinuous ?? false,
            phase: event.scrollPayload?.phase,
            momentumPhase: event.scrollPayload?.momentumPhase
        )
    }

    private static func clampedInt32(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        if value > Double(Int32.max) { return Int32.max }
        if value < Double(Int32.min) { return Int32.min }
        return Int32(value)
    }

    private static func clampedInt32(_ value: CGFloat) -> Int32 {
        guard value.isFinite else { return 0 }
        if value > CGFloat(Int32.max) { return Int32.max }
        if value < CGFloat(Int32.min) { return Int32.min }
        return Int32(value)
    }
}

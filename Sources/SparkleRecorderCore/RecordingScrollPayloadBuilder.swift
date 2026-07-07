import CoreGraphics
import Foundation

public struct RecordingScrollSample: Equatable, Sendable {
    public var pointDeltaX: Int32
    public var pointDeltaY: Int32
    public var lineDeltaX: Int32
    public var lineDeltaY: Int32
    public var phase: Int
    public var momentumPhase: Int
    public var fixedRawX: Int64
    public var fixedRawY: Int64
    public var isContinuous: Bool

    public init(
        pointDeltaX: Int32,
        pointDeltaY: Int32,
        lineDeltaX: Int32,
        lineDeltaY: Int32,
        phase: Int,
        momentumPhase: Int,
        fixedRawX: Int64,
        fixedRawY: Int64,
        isContinuous: Bool
    ) {
        self.pointDeltaX = pointDeltaX
        self.pointDeltaY = pointDeltaY
        self.lineDeltaX = lineDeltaX
        self.lineDeltaY = lineDeltaY
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.fixedRawX = fixedRawX
        self.fixedRawY = fixedRawY
        self.isContinuous = isContinuous
    }
}

public struct RecordingScrollResult: Equatable, Sendable {
    public var payload: ScrollPayload
    public var playbackDeltaX: Int32
    public var playbackDeltaY: Int32

    public init(payload: ScrollPayload, playbackDeltaX: Int32, playbackDeltaY: Int32) {
        self.payload = payload
        self.playbackDeltaX = playbackDeltaX
        self.playbackDeltaY = playbackDeltaY
    }
}

public enum RecordingScrollPayloadBuilder {
    public static let lineToPointScale: Int32 = 12
    public static let fixedPointScale = 65_536.0

    public static func build(from sample: RecordingScrollSample) -> RecordingScrollResult {
        RecordingScrollResult(
            payload: ScrollPayload(
                deltaX: CGFloat(sample.pointDeltaX),
                deltaY: CGFloat(sample.pointDeltaY),
                lineDeltaX: sample.lineDeltaX,
                lineDeltaY: sample.lineDeltaY,
                phase: sample.phase,
                momentumPhase: sample.momentumPhase,
                fixedDeltaX: fixedDelta(from: sample.fixedRawX),
                fixedDeltaY: fixedDelta(from: sample.fixedRawY),
                isContinuous: sample.isContinuous
            ),
            playbackDeltaX: playbackDelta(pointDelta: sample.pointDeltaX, lineDelta: sample.lineDeltaX),
            playbackDeltaY: playbackDelta(pointDelta: sample.pointDeltaY, lineDelta: sample.lineDeltaY)
        )
    }

    private static func fixedDelta(from rawValue: Int64) -> Double? {
        rawValue == 0 ? nil : Double(rawValue) / fixedPointScale
    }

    private static func playbackDelta(pointDelta: Int32, lineDelta: Int32) -> Int32 {
        guard pointDelta == 0 else { return pointDelta }
        let scaled = Int64(lineDelta) * Int64(lineToPointScale)
        return Int32(clamping: scaled)
    }
}

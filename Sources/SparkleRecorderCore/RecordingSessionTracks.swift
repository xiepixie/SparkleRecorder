import CoreGraphics
import Foundation

/// Privacy-safe high-resolution mechanical evidence retained independently from
/// the compact playable macro. Readable keyboard text, text anchors and editor
/// labels are intentionally absent from this type.
public struct RecordingEvidenceSample: Codable, Equatable, Sendable {
    public var index: Int
    public var sourcePlaybackTime: TimeInterval
    public var sessionTime: TimeInterval?
    public var kind: RecordedEvent.Kind
    public var x: CGFloat
    public var y: CGFloat
    public var flags: UInt64
    public var mouseButton: Int64
    public var clickCount: Int64
    public var scrollDeltaY: Int32
    public var scrollDeltaX: Int32
    public var scrollPayload: ScrollPayload?
    public var windowLocalX: CGFloat?
    public var windowLocalY: CGFloat?
    public var windowNormalizedX: CGFloat?
    public var windowNormalizedY: CGFloat?
    public var contentLocalX: CGFloat?
    public var contentLocalY: CGFloat?
    public var contentNormalizedX: CGFloat?
    public var contentNormalizedY: CGFloat?
    public var coordinateBinding: CoordinateBinding?
    public var surfaceId: String?

    public init(index: Int, event: RecordedEvent) {
        self.index = index
        self.sourcePlaybackTime = event.time
        self.sessionTime = nil
        self.kind = event.kind
        self.x = event.x
        self.y = event.y
        self.flags = event.flags
        self.mouseButton = event.mouseButton
        self.clickCount = event.clickCount
        self.scrollDeltaY = event.scrollDeltaY
        self.scrollDeltaX = event.scrollDeltaX
        self.scrollPayload = event.scrollPayload
        self.windowLocalX = event.windowLocalX
        self.windowLocalY = event.windowLocalY
        self.windowNormalizedX = event.windowNormalizedX
        self.windowNormalizedY = event.windowNormalizedY
        self.contentLocalX = event.contentLocalX
        self.contentLocalY = event.contentLocalY
        self.contentNormalizedX = event.contentNormalizedX
        self.contentNormalizedY = event.contentNormalizedY
        self.coordinateBinding = event.coordinateBinding
        self.surfaceId = event.surfaceId
    }

    public static func mechanical(index: Int, event: RecordedEvent) -> RecordingEvidenceSample? {
        guard event.kind.isMouse else { return nil }
        return RecordingEvidenceSample(index: index, event: event)
    }

    public func projectingSessionTime(offset: TimeInterval?) -> RecordingEvidenceSample {
        guard let offset else { return self }
        var projected = self
        let value = offset + sourcePlaybackTime
        projected.sessionTime = value.isFinite && value >= 0 ? value : nil
        return projected
    }
}

public struct RecordingPlayableEvidenceLink: Codable, Equatable, Sendable {
    public var playableEventIndex: Int
    public var evidenceSampleStartIndex: Int
    public var evidenceSampleEndIndex: Int

    public init(playableEventIndex: Int, evidenceSampleRange: ClosedRange<Int>) {
        self.playableEventIndex = playableEventIndex
        self.evidenceSampleStartIndex = evidenceSampleRange.lowerBound
        self.evidenceSampleEndIndex = evidenceSampleRange.upperBound
    }

    public var evidenceSampleRange: ClosedRange<Int> {
        evidenceSampleStartIndex...evidenceSampleEndIndex
    }
}

/// One drain of the Recording Session Module. Playable and evidence tracks are
/// intentionally separate so deterministic cleanup can change execution density
/// without destroying the higher-resolution reconstruction evidence.
public struct RecordingSessionTrackSnapshot: Equatable, Sendable {
    public var playableEvents: [RecordedEvent]
    public var evidenceSamples: [RecordingEvidenceSample]
    public var playableEvidenceLinks: [RecordingPlayableEvidenceLink]
    public var omittedEvidenceSampleCount: Int
    public var surfaces: [String: PlaybackSurface]

    public init(
        playableEvents: [RecordedEvent] = [],
        evidenceSamples: [RecordingEvidenceSample] = [],
        playableEvidenceLinks: [RecordingPlayableEvidenceLink] = [],
        omittedEvidenceSampleCount: Int = 0,
        surfaces: [String: PlaybackSurface] = [:]
    ) {
        self.playableEvents = playableEvents
        self.evidenceSamples = evidenceSamples
        self.playableEvidenceLinks = playableEvidenceLinks
        self.omittedEvidenceSampleCount = max(0, omittedEvidenceSampleCount)
        self.surfaces = surfaces
    }

}

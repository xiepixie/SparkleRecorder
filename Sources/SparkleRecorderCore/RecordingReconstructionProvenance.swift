import CryptoKit
import Foundation

/// Host time is mach absolute time converted to seconds, never wall-clock time.
public struct RecordingSourceEventTime: Codable, Equatable, Sendable {
    public var sourceEventIndex: Int
    public var sourcePlaybackTime: Double
    public var sessionTime: Double
    public init(sourceEventIndex: Int, sourcePlaybackTime: Double, sessionTime: Double) {
        self.sourceEventIndex = sourceEventIndex
        self.sourcePlaybackTime = sourcePlaybackTime
        self.sessionTime = sessionTime
    }
}

public struct RecordingCaptureSampleTiming: Codable, Equatable, Sendable {
    public var presentationTime: Double
    /// Present only after an app-owned writer accepted this sample and finalized the file.
    public var writtenVideoTime: Double?
    public var displayedHostTime: Double?
    public var receivedHostTime: Double
    public var duration: Double?
    public var screenRect: RectValue?
    public var contentRect: RectValue?
    public var imageSize: RecordingImageSize
    public var displayScale: Double?
    public init(presentationTime: Double, displayedHostTime: Double?, receivedHostTime: Double,
                duration: Double?, screenRect: RectValue?, contentRect: RectValue?,
                imageSize: RecordingImageSize, displayScale: Double?, writtenVideoTime: Double? = nil) {
        self.writtenVideoTime = writtenVideoTime
        self.presentationTime = presentationTime; self.displayedHostTime = displayedHostTime
        self.receivedHostTime = receivedHostTime; self.duration = duration
        self.screenRect = screenRect; self.contentRect = contentRect
        self.imageSize = imageSize; self.displayScale = displayScale
    }
}

public struct RecordingMovieTimingEvidence: Codable, Equatable, Sendable {
    public var segmentID: UUID
    public var samples: [RecordingCaptureSampleTiming]
    public var omittedSampleCount: Int
    public var fileTrackStartPTS: Double?
    public var fileTrackDuration: Double?
    public var alignmentUnavailableReason: String
    public init(segmentID: UUID, samples: [RecordingCaptureSampleTiming] = [], omittedSampleCount: Int = 0,
                fileTrackStartPTS: Double? = nil, fileTrackDuration: Double? = nil,
                alignmentUnavailableReason: String = "File presentation origin has no verified correspondence to stream samples.") {
        self.segmentID = segmentID; self.samples = samples; self.omittedSampleCount = omittedSampleCount
        self.fileTrackStartPTS = fileTrackStartPTS; self.fileTrackDuration = fileTrackDuration
        self.alignmentUnavailableReason = alignmentUnavailableReason
    }
}

public struct RecordingFrameTimingEvidence: Codable, Equatable, Sendable {
    public var frameID: UUID
    public var requestedSessionTime: Double
    public var capturedSessionTime: Double?
    public var uncertainty: Double?
    public init(frameID: UUID, requestedSessionTime: Double, capturedSessionTime: Double?, uncertainty: Double?) {
        self.frameID = frameID; self.requestedSessionTime = requestedSessionTime
        self.capturedSessionTime = capturedSessionTime; self.uncertainty = uncertainty
    }
}

/// Absent in legacy bundles. Raw stream PTS are evidence, not movie-local anchors.
public struct RecordingReconstructionProvenance: Codable, Equatable, Sendable {
    public var sessionOriginHostTime: Double
    public var sessionEndTime: Double
    public var sourceEvents: [RecordingSourceEventTime]
    /// Digest of the exact captured playable event sequence, before session-time projection.
    /// Missing in legacy provenance; index/time equality alone never binds an edited macro.
    public var sourceEventDigest: String?
    public var movieEvidence: [RecordingMovieTimingEvidence]
    public var frameTimings: [RecordingFrameTimingEvidence]
    public var clockSegments: [RecordingVideoClockSegment]
    public var geometrySnapshots: [RecordingGeometrySnapshot]
    public init(sessionOriginHostTime: Double, sessionEndTime: Double,
                sourceEvents: [RecordingSourceEventTime] = [], movieEvidence: [RecordingMovieTimingEvidence] = [],
                frameTimings: [RecordingFrameTimingEvidence] = [], clockSegments: [RecordingVideoClockSegment] = [],
                geometrySnapshots: [RecordingGeometrySnapshot] = [], sourceEventDigest: String? = nil) {
        self.sessionOriginHostTime = sessionOriginHostTime; self.sessionEndTime = sessionEndTime
        self.sourceEvents = sourceEvents; self.sourceEventDigest = sourceEventDigest
        self.movieEvidence = movieEvidence; self.frameTimings = frameTimings
        self.clockSegments = clockSegments; self.geometrySnapshots = geometrySnapshots
    }
}

public extension RecordingReconstructionProvenance {
    /// Full event content is intentional: changed coordinates, keys, readable text,
    /// timing or disabled state invalidate the recording association. This digest
    /// is independent of macro statistics, configuration and display metadata.
    static func digest(ofSourceEvents events: [RecordedEvent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(events)
        return "recording-source-events/v1/" + SHA256.hash(data: bytes).map {
            String(format: "%02x", $0)
        }.joined()
    }

    func matchesSourceEvents(_ events: [RecordedEvent]) -> Bool {
        guard let sourceEventDigest, let actual = try? Self.digest(ofSourceEvents: events) else { return false }
        return sourceEventDigest == actual
    }


    /// File times are explicit successful writer receipts, never inferred from raw PTS.
    /// A missing host timestamp or backwards clock invalidates the segment instead
    /// of interpolating across an interval whose correspondence is unknown.
    static func writtenMovieClocks(movieEvidence: [RecordingMovieTimingEvidence], origin: Double) -> [RecordingVideoClockSegment] {
        guard origin.isFinite, origin >= 0 else { return [] }
        let segments = movieEvidence.compactMap { evidence -> RecordingVideoClockSegment? in
            guard evidence.alignmentUnavailableReason.isEmpty,
                  evidence.fileTrackStartPTS == 0,
                  let duration = evidence.fileTrackDuration, duration.isFinite, duration > 0,
                  evidence.samples.count >= 2 else { return nil }
            var anchors: [RecordingVideoClockAnchor] = []
            for sample in evidence.samples {
                guard let host = sample.displayedHostTime, host.isFinite, host >= origin,
                      let video = sample.writtenVideoTime, video.isFinite, video >= 0, video <= duration else { return nil }
                anchors.append(.init(recordingTime: host - origin, videoTime: video))
            }
            let segment = RecordingVideoClockSegment(id: evidence.segmentID.uuidString,
                anchors: anchors, maximumError: 0)
            guard (try? RecordingVideoClockMapping(segments: [segment], tolerance: 0)) != nil else { return nil }
            return segment
        }
        guard (try? RecordingVideoClockMapping(segments: segments, tolerance: 0)) != nil else { return [] }
        return segments
    }

    /// Use only full-frame, measured geometry with an explicit sample duration.
    /// Unknown duration/padding yields no projection interval.
    static func measuredGeometry(movieEvidence: [RecordingMovieTimingEvidence], origin: Double, surfaceID: String?) -> [RecordingGeometrySnapshot] {
        guard let surfaceID, !surfaceID.isEmpty else { return [] }
        var snapshots: [RecordingGeometrySnapshot] = []
        for sample in movieEvidence.flatMap(\.samples) {
            guard let host = sample.displayedHostTime, host >= origin,
                  let duration = sample.duration, duration > 0,
                  let screen = sample.screenRect, let content = sample.contentRect,
                  let scale = sample.displayScale, scale > 0,
                  content.x == 0, content.y == 0,
                  abs(Double(content.width) * scale - Double(sample.imageSize.width)) < 1,
                  abs(Double(content.height) * scale - Double(sample.imageSize.height)) < 1 else { continue }
            let time = host - origin
            if let last = snapshots.last, last.validUntil > time { continue }
            snapshots.append(.init(surfaceID: surfaceID, recordingTime: time, validUntil: time + duration,
                                   captureBounds: screen, frameSize: sample.imageSize))
        }
        return snapshots
    }
}

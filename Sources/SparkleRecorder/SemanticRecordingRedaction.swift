import Foundation

public struct SemanticRecordingRedactionMask: Codable, Equatable, Sendable {
    public var bounds: RecordingBounds
    public var reason: RecordingSuppressionReason
    public var sourceSuppressionID: UUID
    public var sourceObservationID: UUID?

    public init(
        bounds: RecordingBounds,
        reason: RecordingSuppressionReason,
        sourceSuppressionID: UUID,
        sourceObservationID: UUID? = nil
    ) {
        self.bounds = bounds
        self.reason = reason
        self.sourceSuppressionID = sourceSuppressionID
        self.sourceObservationID = sourceObservationID
    }
}

public struct SemanticRecordingFrameRedaction: Codable, Equatable, Sendable {
    public var frameID: UUID
    public var recordingTime: TimeInterval
    public var sourceImageRef: RecordingArtifactRef
    public var redactedImageRef: RecordingArtifactRef
    public var sourceSuppressionIDs: [UUID]
    public var masks: [SemanticRecordingRedactionMask]

    public init(
        frameID: UUID,
        recordingTime: TimeInterval,
        sourceImageRef: RecordingArtifactRef,
        redactedImageRef: RecordingArtifactRef,
        sourceSuppressionIDs: [UUID],
        masks: [SemanticRecordingRedactionMask]
    ) {
        self.frameID = frameID
        self.recordingTime = max(0, recordingTime)
        self.sourceImageRef = sourceImageRef
        self.redactedImageRef = redactedImageRef
        self.sourceSuppressionIDs = sourceSuppressionIDs
        self.masks = masks
    }
}

public struct SemanticRecordingRenderedFrameRedaction: Codable, Equatable, Sendable {
    public var frameID: UUID
    public var sourceImageRef: RecordingArtifactRef
    public var redactedImageRef: RecordingArtifactRef
    public var renderedMaskCount: Int
    public var sourceSuppressionIDs: [UUID]

    public init(
        frameID: UUID,
        sourceImageRef: RecordingArtifactRef,
        redactedImageRef: RecordingArtifactRef,
        renderedMaskCount: Int,
        sourceSuppressionIDs: [UUID] = []
    ) {
        self.frameID = frameID
        self.sourceImageRef = sourceImageRef
        self.redactedImageRef = redactedImageRef
        self.renderedMaskCount = max(0, renderedMaskCount)
        self.sourceSuppressionIDs = sourceSuppressionIDs
    }
}

public struct SemanticRecordingVideoRangeRedaction: Codable, Equatable, Sendable {
    public var videoSegmentID: UUID
    public var timeRange: RecordingTimeRange
    public var sourceSuppressionIDs: [UUID]
    public var reasons: [RecordingSuppressionReason]

    public init(
        videoSegmentID: UUID,
        timeRange: RecordingTimeRange,
        sourceSuppressionIDs: [UUID],
        reasons: [RecordingSuppressionReason]
    ) {
        self.videoSegmentID = videoSegmentID
        self.timeRange = timeRange
        self.sourceSuppressionIDs = sourceSuppressionIDs
        self.reasons = reasons
    }
}

public struct SemanticRecordingRenderedVideoRedaction: Codable, Equatable, Sendable {
    public var videoSegmentID: UUID
    public var sourceVideoRef: RecordingArtifactRef
    public var redactedVideoRef: RecordingArtifactRef
    public var renderedRangeCount: Int
    public var sourceSuppressionIDs: [UUID]
    public var reasons: [RecordingSuppressionReason]

    public init(
        videoSegmentID: UUID,
        sourceVideoRef: RecordingArtifactRef,
        redactedVideoRef: RecordingArtifactRef,
        renderedRangeCount: Int,
        sourceSuppressionIDs: [UUID] = [],
        reasons: [RecordingSuppressionReason] = []
    ) {
        self.videoSegmentID = videoSegmentID
        self.sourceVideoRef = sourceVideoRef
        self.redactedVideoRef = redactedVideoRef
        self.renderedRangeCount = max(0, renderedRangeCount)
        self.sourceSuppressionIDs = sourceSuppressionIDs
        self.reasons = reasons
    }
}

public struct SemanticRecordingRedactionPlan: Codable, Equatable, Sendable {
    public var recordingID: UUID
    public var frameRedactions: [SemanticRecordingFrameRedaction]
    public var videoRangeRedactions: [SemanticRecordingVideoRangeRedaction]

    public init(
        recordingID: UUID,
        frameRedactions: [SemanticRecordingFrameRedaction] = [],
        videoRangeRedactions: [SemanticRecordingVideoRangeRedaction] = []
    ) {
        self.recordingID = recordingID
        self.frameRedactions = frameRedactions
        self.videoRangeRedactions = videoRangeRedactions
    }

    public var isEmpty: Bool {
        frameRedactions.isEmpty && videoRangeRedactions.isEmpty
    }
}

public enum SemanticRecordingRedactionPlanner {
    public static func plan(
        for bundle: SemanticRecordingBundle
    ) -> SemanticRecordingRedactionPlan {
        let suppressions = bundle.suppressions
            .filter { $0.reason.redactsSemanticEvidence }
        guard !suppressions.isEmpty else {
            return SemanticRecordingRedactionPlan(recordingID: bundle.id)
        }

        return SemanticRecordingRedactionPlan(
            recordingID: bundle.id,
            frameRedactions: frameRedactions(
                for: bundle,
                suppressions: suppressions
            ),
            videoRangeRedactions: videoRangeRedactions(
                for: bundle,
                suppressions: suppressions
            )
        )
    }

    private static func frameRedactions(
        for bundle: SemanticRecordingBundle,
        suppressions: [RecordingSuppressionRecord]
    ) -> [SemanticRecordingFrameRedaction] {
        var redactions: [UUID: SemanticRecordingFrameRedaction] = [:]

        for suppression in suppressions {
            for frame in frames(in: bundle, matching: suppression) {
                let masks = masks(
                    for: frame,
                    bundle: bundle,
                    suppression: suppression
                )
                guard !masks.isEmpty else {
                    continue
                }

                if var existing = redactions[frame.id] {
                    existing.sourceSuppressionIDs = appendUnique(
                        suppression.id,
                        to: existing.sourceSuppressionIDs
                    )
                    existing.masks.append(contentsOf: masks)
                    redactions[frame.id] = existing
                } else {
                    redactions[frame.id] = SemanticRecordingFrameRedaction(
                        frameID: frame.id,
                        recordingTime: frame.recordingTime,
                        sourceImageRef: frame.imageRef,
                        redactedImageRef: redactedFrameArtifactRef(frameID: frame.id),
                        sourceSuppressionIDs: [suppression.id],
                        masks: masks
                    )
                }
            }
        }

        return redactions.values.sorted {
            if $0.recordingTime == $1.recordingTime {
                return $0.frameID.uuidString < $1.frameID.uuidString
            }
            return $0.recordingTime < $1.recordingTime
        }
    }

    private static func videoRangeRedactions(
        for bundle: SemanticRecordingBundle,
        suppressions: [RecordingSuppressionRecord]
    ) -> [SemanticRecordingVideoRangeRedaction] {
        var redactions: [String: SemanticRecordingVideoRangeRedaction] = [:]

        for suppression in suppressions {
            guard let timeRange = suppression.timeRange
                ?? suppression.recordingTime.map({
                    RecordingTimeRange(startTime: $0, duration: 0)
                }) else {
                continue
            }

            for segment in bundle.videoSegments {
                guard let intersection = intersection(
                    timeRange,
                    with: segment
                ) else {
                    continue
                }

                let key = "\(segment.id.uuidString)|\(intersection.startTime)|\(intersection.duration)"
                if var existing = redactions[key] {
                    existing.sourceSuppressionIDs = appendUnique(
                        suppression.id,
                        to: existing.sourceSuppressionIDs
                    )
                    existing.reasons = appendUnique(
                        suppression.reason,
                        to: existing.reasons
                    )
                    redactions[key] = existing
                } else {
                    redactions[key] = SemanticRecordingVideoRangeRedaction(
                        videoSegmentID: segment.id,
                        timeRange: intersection,
                        sourceSuppressionIDs: [suppression.id],
                        reasons: [suppression.reason]
                    )
                }
            }
        }

        return redactions.values.sorted {
            if $0.videoSegmentID == $1.videoSegmentID {
                return $0.timeRange.startTime < $1.timeRange.startTime
            }
            return $0.videoSegmentID.uuidString < $1.videoSegmentID.uuidString
        }
    }

    private static func frames(
        in bundle: SemanticRecordingBundle,
        matching suppression: RecordingSuppressionRecord
    ) -> [RecordingFrameReference] {
        var frameIDs = Set<UUID>()

        if let frameID = suppression.frameID {
            frameIDs.insert(frameID)
        }

        if let eventID = suppression.eventID {
            for event in bundle.timelineEvents where event.id == eventID {
                if let frameID = event.frameID {
                    frameIDs.insert(frameID)
                }
            }
            for frame in bundle.frames where frame.relatedEventIDs.contains(eventID) {
                frameIDs.insert(frame.id)
            }
        }

        let directMatches = bundle.frames.filter { frameIDs.contains($0.id) }
        if !directMatches.isEmpty {
            return directMatches.sorted { $0.recordingTime < $1.recordingTime }
        }

        return bundle.frames.filter { frame in
            suppressionMatches(suppression, recordingTime: frame.recordingTime)
        }
        .sorted { $0.recordingTime < $1.recordingTime }
    }

    private static func masks(
        for frame: RecordingFrameReference,
        bundle: SemanticRecordingBundle,
        suppression: RecordingSuppressionRecord
    ) -> [SemanticRecordingRedactionMask] {
        let observationMasks = bundle.visualObservations
            .filter { $0.frameID == frame.id }
            .compactMap { observation -> SemanticRecordingRedactionMask? in
                guard let bounds = observation.bounds else {
                    return nil
                }
                return SemanticRecordingRedactionMask(
                    bounds: bounds,
                    reason: suppression.reason,
                    sourceSuppressionID: suppression.id,
                    sourceObservationID: observation.id
                )
            }

        if !observationMasks.isEmpty {
            return observationMasks
        }

        guard let imageSize = frame.imageSize else {
            return []
        }
        return [
            SemanticRecordingRedactionMask(
                bounds: RecordingBounds(
                    rect: RecordingRect(
                        x: 0,
                        y: 0,
                        width: Double(imageSize.width),
                        height: Double(imageSize.height)
                    ),
                    coordinateSpace: .framePixels
                ),
                reason: suppression.reason,
                sourceSuppressionID: suppression.id
            )
        ]
    }

    private static func suppressionMatches(
        _ suppression: RecordingSuppressionRecord,
        recordingTime: TimeInterval
    ) -> Bool {
        if let timeRange = suppression.timeRange {
            return timeRange.contains(recordingTime)
        }
        if let suppressionTime = suppression.recordingTime {
            return abs(max(0, recordingTime) - max(0, suppressionTime)) <= 0.001
        }
        return false
    }

    private static func intersection(
        _ range: RecordingTimeRange,
        with segment: RecordingVideoSegment
    ) -> RecordingTimeRange? {
        let start = max(range.startTime, segment.startTime)
        let end = min(range.endTime, segment.endTime)
        guard end >= start else {
            return nil
        }
        return RecordingTimeRange(startTime: start, duration: end - start)
    }

    private static func redactedFrameArtifactRef(
        frameID: UUID
    ) -> RecordingArtifactRef {
        do {
            return try RecordingArtifactRef(
                "redacted/frames/\(frameID.uuidString.lowercased()).png"
            )
        } catch {
            preconditionFailure("Invalid generated redacted frame artifact ref")
        }
    }

    private static func appendUnique<T: Equatable>(
        _ value: T,
        to values: [T]
    ) -> [T] {
        values.contains(value) ? values : values + [value]
    }
}

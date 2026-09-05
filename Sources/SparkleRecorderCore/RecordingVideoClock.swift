/// A provider-supplied correspondence between session time and segment-local video time.
public struct RecordingVideoClockAnchor: Codable, Equatable, Sendable {
    public let recordingTime: Double
    public let videoTime: Double

    public init(recordingTime: Double, videoTime: Double) {
        self.recordingTime = recordingTime
        self.videoTime = videoTime
    }
}

/// One continuously covered interval. Discontinuities require separate segments.
public struct RecordingVideoClockSegment: Codable, Equatable, Sendable {
    public let id: String
    public let anchors: [RecordingVideoClockAnchor]
    /// Provider-supplied uncertainty; anchors alone do not prove alignment accuracy.
    public let maximumError: Double

    public init(id: String, anchors: [RecordingVideoClockAnchor], maximumError: Double) {
        self.id = id
        self.anchors = anchors
        self.maximumError = maximumError
    }
}

/// Immutable validated evidence. Degraded segments are retained but cannot map queries.
public struct RecordingVideoClockMapping: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidTolerance
        case emptySegmentID
        case duplicateSegmentID(String)
        case insufficientAnchors(segmentID: String)
        case invalidMaximumError(segmentID: String)
        case invalidAnchor(segmentID: String, index: Int)
        case nonIncreasingAnchors(segmentID: String, index: Int)
        case overlappingRecordingIntervals(firstSegmentID: String, secondSegmentID: String)
    }

    public let segments: [RecordingVideoClockSegment]
    public let tolerance: Double
    private let segmentsByID: [String: RecordingVideoClockSegment]

    public init(segments: [RecordingVideoClockSegment], tolerance: Double = 0.05) throws {
        guard tolerance.isFinite, tolerance >= 0 else {
            throw ValidationError.invalidTolerance
        }
        var ids = Set<String>()
        for segment in segments {
            guard !segment.id.isEmpty else { throw ValidationError.emptySegmentID }
            guard ids.insert(segment.id).inserted else {
                throw ValidationError.duplicateSegmentID(segment.id)
            }
            guard segment.anchors.count >= 2 else {
                throw ValidationError.insufficientAnchors(segmentID: segment.id)
            }
            guard segment.maximumError.isFinite, segment.maximumError >= 0 else {
                throw ValidationError.invalidMaximumError(segmentID: segment.id)
            }
            for (index, anchor) in segment.anchors.enumerated() {
                guard anchor.recordingTime.isFinite, anchor.recordingTime >= 0,
                      anchor.videoTime.isFinite, anchor.videoTime >= 0 else {
                    throw ValidationError.invalidAnchor(segmentID: segment.id, index: index)
                }
                if index > 0 {
                    let previous = segment.anchors[index - 1]
                    guard anchor.recordingTime > previous.recordingTime,
                          anchor.videoTime > previous.videoTime else {
                        throw ValidationError.nonIncreasingAnchors(segmentID: segment.id, index: index)
                    }
                }
            }
        }
        let ordered = segments.sorted { $0.anchors[0].recordingTime < $1.anchors[0].recordingTime }
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            if previous.anchors[previous.anchors.count - 1].recordingTime > next.anchors[0].recordingTime {
                throw ValidationError.overlappingRecordingIntervals(
                    firstSegmentID: previous.id, secondSegmentID: next.id
                )
            }
        }
        self.segments = ordered
        self.segmentsByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        self.tolerance = tolerance
    }

    public func videoTime(forRecordingTime time: Double, segmentID: String) -> Double? {
        interpolate(time, segmentID: segmentID, source: \.recordingTime, destination: \.videoTime)
    }

    public func recordingTime(forVideoTime time: Double, segmentID: String) -> Double? {
        interpolate(time, segmentID: segmentID, source: \.videoTime, destination: \.recordingTime)
    }

    /// Returns only a unique usable interval; shared usable endpoints are ambiguous.
    public func segmentID(forRecordingTime time: Double) -> String? {
        guard time.isFinite, time >= 0 else { return nil }
        var match: String?
        for segment in segments where segment.maximumError <= tolerance {
            guard time >= segment.anchors[0].recordingTime,
                  time <= segment.anchors[segment.anchors.count - 1].recordingTime else { continue }
            guard match == nil else { return nil }
            match = segment.id
        }
        return match
    }

    private func interpolate(
        _ time: Double,
        segmentID: String,
        source: KeyPath<RecordingVideoClockAnchor, Double>,
        destination: KeyPath<RecordingVideoClockAnchor, Double>
    ) -> Double? {
        guard time.isFinite, time >= 0,
              let segment = segmentsByID[segmentID],
              segment.maximumError <= tolerance else { return nil }
        let anchors = segment.anchors
        guard time >= anchors[0][keyPath: source],
              time <= anchors[anchors.count - 1][keyPath: source] else { return nil }
        var lowerIndex = 0
        var upperIndex = anchors.count
        while lowerIndex < upperIndex {
            let middle = lowerIndex + (upperIndex - lowerIndex) / 2
            if anchors[middle][keyPath: source] < time { lowerIndex = middle + 1 }
            else { upperIndex = middle }
        }
        let anchor = anchors[lowerIndex]
        let upperTime = anchor[keyPath: source]
        if time == upperTime { return anchor[keyPath: destination] }
        guard lowerIndex > 0 else { return nil }
        let lower = anchors[lowerIndex - 1]
        let fraction = (time - lower[keyPath: source]) / (upperTime - lower[keyPath: source])
        let result = lower[keyPath: destination] + fraction * (anchor[keyPath: destination] - lower[keyPath: destination])
        return result.isFinite ? result : nil
    }
}

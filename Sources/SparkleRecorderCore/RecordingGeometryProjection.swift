import Foundation

/// Capture geometry valid for a half-open interval on the recording clock.
/// Bounds use global screen points; frame size uses pixels, both with a top-left origin.
public struct RecordingGeometrySnapshot: Codable, Equatable, Sendable {
    public let surfaceID: String
    public let recordingTime: Double
    public let validUntil: Double
    public let captureBounds: RectValue
    public let frameSize: RecordingImageSize

    public init(
        surfaceID: String,
        recordingTime: Double,
        validUntil: Double,
        captureBounds: RectValue,
        frameSize: RecordingImageSize
    ) {
        self.surfaceID = surfaceID
        self.recordingTime = recordingTime
        self.validUntil = validUntil
        self.captureBounds = captureBounds
        self.frameSize = frameSize
    }
}

/// Validated historical geometry. Missing coverage never falls back to another interval.
public struct RecordingGeometryHistory: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidSurfaceID(snapshotIndex: Int)
        case invalidInterval(snapshotIndex: Int)
        case invalidCaptureBounds(snapshotIndex: Int)
        case invalidFrameSize(snapshotIndex: Int)
        case overlappingSnapshots(surfaceID: String)
    }

    private let snapshotsBySurface: [String: [RecordingGeometrySnapshot]]

    public init(snapshots: [RecordingGeometrySnapshot]) throws {
        for (index, snapshot) in snapshots.enumerated() {
            guard !snapshot.surfaceID.isEmpty else {
                throw ValidationError.invalidSurfaceID(snapshotIndex: index)
            }
            guard snapshot.recordingTime.isFinite, snapshot.validUntil.isFinite,
                  snapshot.recordingTime >= 0, snapshot.validUntil > snapshot.recordingTime else {
                throw ValidationError.invalidInterval(snapshotIndex: index)
            }
            let bounds = snapshot.captureBounds
            guard bounds.x.isFinite, bounds.y.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0,
                  (bounds.x + bounds.width).isFinite,
                  (bounds.y + bounds.height).isFinite else {
                throw ValidationError.invalidCaptureBounds(snapshotIndex: index)
            }
            guard snapshot.frameSize.width > 0, snapshot.frameSize.height > 0 else {
                throw ValidationError.invalidFrameSize(snapshotIndex: index)
            }
        }

        let sorted = snapshots.sorted {
            if $0.surfaceID != $1.surfaceID { return $0.surfaceID < $1.surfaceID }
            return $0.recordingTime < $1.recordingTime
        }
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            if previous.surfaceID == current.surfaceID,
               previous.validUntil > current.recordingTime {
                throw ValidationError.overlappingSnapshots(surfaceID: current.surfaceID)
            }
        }
        self.snapshotsBySurface = Dictionary(grouping: sorted, by: \.surfaceID)
    }

    /// Returns pixels only when the requested surface and time have valid capture coverage.
    /// Capture bounds include all edges; the temporal upper bound is excluded.
    public func framePoint(
        forGlobalPoint point: PointValue,
        surfaceID: String,
        recordingTime: Double
    ) -> PointValue? {
        guard recordingTime.isFinite, recordingTime >= 0,
              point.x.isFinite, point.y.isFinite,
              let snapshots = snapshotsBySurface[surfaceID] else { return nil }
        var lower = 0
        var upper = snapshots.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if snapshots[middle].recordingTime <= recordingTime { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let snapshot = snapshots[lower - 1]
        guard recordingTime < snapshot.validUntil else { return nil }

        let bounds = snapshot.captureBounds
        guard point.x >= bounds.x, point.x <= bounds.x + bounds.width,
              point.y >= bounds.y, point.y <= bounds.y + bounds.height else { return nil }

        // Normalize before multiplying to avoid overflowing otherwise valid large coordinates
        // or creating an infinite scale factor for a very small capture extent.
        let x = ((point.x - bounds.x) / bounds.width) * CGFloat(snapshot.frameSize.width)
        let y = ((point.y - bounds.y) / bounds.height) * CGFloat(snapshot.frameSize.height)
        guard x.isFinite, y.isFinite else { return nil }
        return PointValue(x: x, y: y)
    }
}

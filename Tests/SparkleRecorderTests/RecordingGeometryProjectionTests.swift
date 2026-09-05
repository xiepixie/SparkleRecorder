import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording historical geometry")
struct RecordingGeometryProjectionTests {
    private func snapshot(
        surface: String = "main", start: Double = 0, end: Double = 10,
        bounds: RectValue = RectValue(x: 100, y: 200, width: 400, height: 300),
        size: RecordingImageSize = RecordingImageSize(width: 800, height: 600)
    ) -> RecordingGeometrySnapshot {
        RecordingGeometrySnapshot(surfaceID: surface, recordingTime: start, validUntil: end,
                                  captureBounds: bounds, frameSize: size)
    }

    @Test func projectsTopLeftCoordinatesAndInclusiveCaptureEdges() throws {
        let history = try RecordingGeometryHistory(snapshots: [snapshot()])
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 100, y: 200), surfaceID: "main", recordingTime: 0) == PointValue(x: 0, y: 0))
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 300, y: 350), surfaceID: "main", recordingTime: 1) == PointValue(x: 400, y: 300))
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 500, y: 500), surfaceID: "main", recordingTime: 9) == PointValue(x: 800, y: 600))
    }

    @Test func selectsHistoricalMoveResizeFromUnsortedSnapshots() throws {
        let initial = snapshot(end: 2)
        let moved = snapshot(start: 2, end: 4, bounds: RectValue(x: -100, y: -50, width: 200, height: 100), size: RecordingImageSize(width: 1000, height: 200))
        let history = try RecordingGeometryHistory(snapshots: [moved, initial])
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 300, y: 350), surfaceID: "main", recordingTime: 1) == PointValue(x: 400, y: 300))
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 0, y: 0), surfaceID: "main", recordingTime: 2) == PointValue(x: 500, y: 100))
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 300, y: 350), surfaceID: "main", recordingTime: 2) == nil)
    }

    @Test func halfOpenCoverageHasNoFinalSnapshotFallback() throws {
        let history = try RecordingGeometryHistory(snapshots: [snapshot(start: 1, end: 2), snapshot(start: 3, end: 4)])
        let point = PointValue(x: 100, y: 200)
        for time in [0.0, 2, 2.5, 4, 100] {
            #expect(history.framePoint(forGlobalPoint: point, surfaceID: "main", recordingTime: time) == nil)
        }
        for time in [1.0, 3] {
            #expect(history.framePoint(forGlobalPoint: point, surfaceID: "main", recordingTime: time) == PointValue(x: 0, y: 0))
        }
    }

    @Test func concurrentSurfacesAreIndependent() throws {
        let history = try RecordingGeometryHistory(snapshots: [snapshot(), snapshot(surface: "other", bounds: RectValue(x: 0, y: 0, width: 400, height: 300))])
        let point = PointValue(x: 100, y: 200)
        #expect(history.framePoint(forGlobalPoint: point, surfaceID: "main", recordingTime: 1) == PointValue(x: 0, y: 0))
        #expect(history.framePoint(forGlobalPoint: point, surfaceID: "other", recordingTime: 1) == PointValue(x: 200, y: 400))
        #expect(history.framePoint(forGlobalPoint: point, surfaceID: "missing", recordingTime: 1) == nil)
        let empty = try RecordingGeometryHistory(snapshots: [])
        #expect(empty.framePoint(forGlobalPoint: point, surfaceID: "main", recordingTime: 0) == nil)
    }

    @Test func rejectsOverlapsAndInvalidIntervals() {
        #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(start: 2, end: 5), snapshot(start: 1, end: 3)]) }
        #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(), snapshot()]) }
        for (start, end) in [(-1.0, 2.0), (2, 1), (1, 1), (.nan, 2), (0, .infinity), (0, .nan)] {
            #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(start: start, end: end)]) }
        }
        #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(surface: "")]) }
    }

    @Test func rejectsInvalidBoundsAndFrameDimensions() {
        let invalidBounds: [RectValue] = [
            RectValue(x: .nan, y: 0, width: 100, height: 100),
            RectValue(x: 0, y: .infinity, width: 100, height: 100),
            RectValue(x: 0, y: 0, width: 0, height: 100),
            RectValue(x: 0, y: 0, width: 100, height: -1),
            RectValue(x: 0, y: 0, width: .infinity, height: 100),
            RectValue(x: 0, y: 0, width: 100, height: .nan),
            RectValue(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 100)
        ]
        for bounds in invalidBounds {
            #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(bounds: bounds)]) }
        }
        for size in [RecordingImageSize(width: 0, height: 1), RecordingImageSize(width: 1, height: 0)] {
            #expect(throws: (any Error).self) { try RecordingGeometryHistory(snapshots: [snapshot(size: size)]) }
        }
    }

    @Test func rejectsInvalidQueriesAndPointsOutsideCapture() throws {
        let history = try RecordingGeometryHistory(snapshots: [snapshot()])
        for point in [PointValue(x: 99, y: 200), PointValue(x: 100, y: 199), PointValue(x: 501, y: 500), PointValue(x: 500, y: 501), PointValue(x: .nan, y: 200), PointValue(x: 100, y: .infinity)] {
            #expect(history.framePoint(forGlobalPoint: point, surfaceID: "main", recordingTime: 1) == nil)
        }
        for time in [-1.0, .nan, .infinity] {
            #expect(history.framePoint(forGlobalPoint: PointValue(x: 100, y: 200), surfaceID: "main", recordingTime: time) == nil)
        }
    }

    @Test func finiteHugeAndTinyBoundsDoNotOverflowProjection() throws {
        let large = snapshot(bounds: RectValue(x: 0, y: 0, width: .greatestFiniteMagnitude, height: 100))
        let largeHistory = try RecordingGeometryHistory(snapshots: [large])
        #expect(largeHistory.framePoint(forGlobalPoint: PointValue(x: .greatestFiniteMagnitude / 2, y: 50), surfaceID: "main", recordingTime: 1) == PointValue(x: 400, y: 300))
        let tiny = snapshot(bounds: RectValue(x: 0, y: 0, width: .leastNonzeroMagnitude, height: .leastNonzeroMagnitude))
        let tinyHistory = try RecordingGeometryHistory(snapshots: [tiny])
        #expect(tinyHistory.framePoint(forGlobalPoint: PointValue(x: .leastNonzeroMagnitude, y: .leastNonzeroMagnitude), surfaceID: "main", recordingTime: 1) == PointValue(x: 800, y: 600))
    }

    @Test func snapshotRoundTripsAndHistoryRetainsValidatedValues() throws {
        let original = snapshot()
        let decoded = try JSONDecoder().decode(RecordingGeometrySnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        var input = [original]
        let history = try RecordingGeometryHistory(snapshots: input)
        input.removeAll()
        #expect(history.framePoint(forGlobalPoint: PointValue(x: 100, y: 200), surfaceID: "main", recordingTime: 1) == PointValue(x: 0, y: 0))
    }
}

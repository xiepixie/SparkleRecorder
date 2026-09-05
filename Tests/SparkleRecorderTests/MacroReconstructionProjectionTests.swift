import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro Reconstruction Projection Tests")
struct MacroReconstructionProjectionTests {
    @Test("Initial recording idle uses explicit session times for video and geometry")
    func initialIdleMapsToSession() throws {
        let rows = try project(sessionTimes: [0: 5, 1: 5.1])
        let row = try #require(rows.first)
        #expect(try #require(row.sessionRange).startTime == 5)
        #expect(abs(try #require(row.sessionRange).duration - 0.1) < 0.000001)
        #expect(row.videoSegmentID == "movie")
        #expect(abs(try #require(row.videoRange).startTime - 4) < 0.000001)
        #expect(row.startFramePoint == PointValue(x: 40, y: 80))
        #expect(row.issues.isEmpty)
    }

    @Test("Missing event mapping never silently uses playback time")
    func missingSessionMapping() throws {
        let row = try #require(project(sessionTimes: [0: 5]).first)
        #expect(row.sessionRange == nil)
        #expect(row.videoRange == nil)
        #expect(row.startFramePoint == nil)
        #expect(row.issues == [.missingSourceTime])
    }

    @Test("Missing intermediate gesture timestamps cannot claim a fully aligned action")
    func missingIntermediateMapping() throws {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0, x: 120, y: 140),
            RecordedEvent.make(.leftMouseDragged, time: 0.1, x: 140, y: 140),
            RecordedEvent.make(.leftMouseUp, time: 0.2, x: 160, y: 140)
        ]
        let rows = try MacroReconstructionProjector.project(
            events: events, sourceRevision: "revision-7",
            sessionTimesByEventIndex: [0: 5, 2: 5.2],
            videoClock: clock(), geometry: geometry()
        )
        let row = try #require(rows.first { $0.action.kind == .drag })
        #expect(row.sessionRange == nil)
        #expect(row.issues == [.missingSourceTime])
    }

    @Test("An action across recording segments has no invented continuous video range")
    func crossedSegments() throws {
        let clock = try RecordingVideoClockMapping(segments: [
            segment("before", start: 1, end: 5), segment("after", start: 5.05, end: 10)
        ])
        let row = try #require(project(sessionTimes: [0: 5, 1: 5.1], clock: clock).first)
        #expect(row.videoRange == nil)
        #expect(row.issues.contains(.crossesVideoSegments))
        #expect(row.sessionRange != nil)
    }

    @Test("Unavailable video preserves source actions and independent geometry")
    func unavailableVideo() throws {
        let row = try #require(project(sessionTimes: [0: 5, 1: 5.1], clock: RecordingVideoClockMapping(segments: [])).first)
        #expect(row.action.sourceEventIndices == [0, 1])
        #expect(row.videoRange == nil)
        #expect(row.startFramePoint != nil)
        #expect(row.issues == [.videoUnavailable])
    }

    @Test("Expired geometry is visible even when the video clock is valid")
    func expiredGeometry() throws {
        let row = try #require(project(sessionTimes: [0: 5, 1: 5.1], geometry: RecordingGeometryHistory(snapshots: [])).first)
        #expect(row.videoRange != nil)
        #expect(row.startFramePoint == nil)
        #expect(row.issues == [.geometryUnavailable])
    }

    @Test("Derived wait maps to adjacent source event session times")
    func derivedWait() throws {
        let events = clickEvents() + clickEvents(offset: 2)
        let rows = try MacroReconstructionProjector.project(
            events: events, sourceRevision: "revision-7",
            sessionTimesByEventIndex: [0: 5, 1: 5.1, 2: 8, 3: 8.1],
            videoClock: clock(), geometry: geometry()
        )
        let wait = try #require(rows.first { $0.action.kind == .wait })
        #expect(wait.action.sourceEventIndices.isEmpty)
        #expect(abs(try #require(wait.sessionRange).duration - 2.9) < 0.000001)
        #expect(wait.issues.isEmpty)
    }

    @Test("Scroll endpoint uses the source event at the endpoint time after geometry changes")
    func scrollEndpointProvenance() throws {
        let events = [(0.0, 10.0), (0.3, 20.0), (0.4, 30.0)].map { time, x in
            var event = RecordedEvent.make(.scrollWheel, time: time, x: x, y: 20)
            event.scrollDeltaY = 1
            event.surfaceId = "main"
            return event
        }
        let history = try RecordingGeometryHistory(snapshots: [
            RecordingGeometrySnapshot(surfaceID: "main", recordingTime: 0, validUntil: 0.35,
                captureBounds: RectValue(x: 0, y: 0, width: 100, height: 100),
                frameSize: RecordingImageSize(width: 200, height: 200)),
            RecordingGeometrySnapshot(surfaceID: "main", recordingTime: 0.35, validUntil: 1,
                captureBounds: RectValue(x: 20, y: 0, width: 100, height: 100),
                frameSize: RecordingImageSize(width: 200, height: 200))
        ])
        let rows = try MacroReconstructionProjector.project(
            events: events, sourceRevision: "revision-7",
            sessionTimesByEventIndex: [0: 0, 1: 0.3, 2: 0.4],
            videoClock: RecordingVideoClockMapping(segments: [segment("movie", start: 0, end: 1)]),
            geometry: history
        )
        #expect(rows.count == 1)
        #expect(rows.first?.endFramePoint == PointValue(x: 20, y: 40))
    }

    @Test("Invalid source-to-session mappings are rejected")
    func invalidMappings() throws {
        for times in [[0: Double.nan], [0: -1.0], [0: 5.0, 1: 4.0], [2: 5.0]] {
            #expect(throws: (any Error).self) { try project(sessionTimes: times) }
        }
    }

    @Test("Repeated projection keeps action identity and results stable")
    func stableProjection() throws {
        let first = try project(sessionTimes: [0: 5, 1: 5.1])
        #expect(first == (try project(sessionTimes: [0: 5, 1: 5.1])))
    }

    private func project(
        sessionTimes: [Int: Double],
        clock: RecordingVideoClockMapping? = nil,
        geometry: RecordingGeometryHistory? = nil
    ) throws -> [MacroReconstructionProjectedAction] {
        try MacroReconstructionProjector.project(
            events: clickEvents(), sourceRevision: "revision-7",
            sessionTimesByEventIndex: sessionTimes,
            videoClock: clock ?? self.clock(), geometry: geometry ?? self.geometry()
        )
    }

    private func clickEvents(offset: Double = 0) -> [RecordedEvent] {
        TestFixtures.clickPair(downTime: offset, upTime: offset + 0.1, x: 120, y: 140).map {
            var event = $0
            event.surfaceId = "main"
            return event
        }
    }

    private func segment(_ id: String, start: Double, end: Double) -> RecordingVideoClockSegment {
        RecordingVideoClockSegment(id: id, anchors: [
            RecordingVideoClockAnchor(recordingTime: start, videoTime: 0),
            RecordingVideoClockAnchor(recordingTime: end, videoTime: end - start)
        ], maximumError: 0.01)
    }

    private func clock() throws -> RecordingVideoClockMapping {
        try RecordingVideoClockMapping(segments: [segment("movie", start: 1, end: 10)])
    }

    private func geometry() throws -> RecordingGeometryHistory {
        try RecordingGeometryHistory(snapshots: [RecordingGeometrySnapshot(
            surfaceID: "main", recordingTime: 1, validUntil: 10,
            captureBounds: RectValue(x: 100, y: 100, width: 200, height: 100),
            frameSize: RecordingImageSize(width: 400, height: 200)
        )])
    }
}

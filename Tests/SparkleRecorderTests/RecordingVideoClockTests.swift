import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Video Clock Tests")
struct RecordingVideoClockTests {
    private func segment(
        _ id: String = "main",
        _ pairs: [(Double, Double)] = [(10, 2), (20, 12), (30, 32)],
        error: Double = 0.01
    ) -> RecordingVideoClockSegment {
        RecordingVideoClockSegment(
            id: id,
            anchors: pairs.map { RecordingVideoClockAnchor(recordingTime: $0.0, videoTime: $0.1) },
            maximumError: error
        )
    }

    @Test func interpolatesOffsetAndPiecewiseDriftInBothDirections() throws {
        let mapping = try RecordingVideoClockMapping(segments: [segment()])
        #expect(mapping.videoTime(forRecordingTime: 15, segmentID: "main") == 7)
        #expect(mapping.videoTime(forRecordingTime: 25, segmentID: "main") == 22)
        #expect(mapping.recordingTime(forVideoTime: 7, segmentID: "main") == 15)
        #expect(mapping.recordingTime(forVideoTime: 22, segmentID: "main") == 25)
        for (recording, video) in [(10.0, 2.0), (20, 12), (30, 32)] {
            #expect(mapping.videoTime(forRecordingTime: recording, segmentID: "main") == video)
            #expect(mapping.recordingTime(forVideoTime: video, segmentID: "main") == recording)
            #expect(mapping.segmentID(forRecordingTime: recording) == "main")
        }
    }

    @Test func neverExtrapolatesOrAcceptsInvalidQueries() throws {
        let mapping = try RecordingVideoClockMapping(segments: [segment()])
        for time in [-1.0, 0, 9.99, 30.01, .nan, .infinity, -.infinity] {
            #expect(mapping.videoTime(forRecordingTime: time, segmentID: "main") == nil)
            #expect(mapping.segmentID(forRecordingTime: time) == nil)
        }
        for time in [-1.0, 0, 1.99, 32.01, .nan, .infinity, -.infinity] {
            #expect(mapping.recordingTime(forVideoTime: time, segmentID: "main") == nil)
        }
        #expect(mapping.videoTime(forRecordingTime: 15, segmentID: "missing") == nil)
        #expect(mapping.recordingTime(forVideoTime: 7, segmentID: "missing") == nil)
    }

    @Test func distinctSegmentsPreserveGapsAndPermitVideoClockResets() throws {
        let mapping = try RecordingVideoClockMapping(segments: [
            segment("later", [(40, 0), (50, 10)]), segment()
        ])
        #expect(mapping.segmentID(forRecordingTime: 35) == nil)
        #expect(mapping.segmentID(forRecordingTime: 45) == "later")
        #expect(mapping.videoTime(forRecordingTime: 45, segmentID: "later") == 5)
        #expect(mapping.recordingTime(forVideoTime: 5, segmentID: "later") == 45)
        #expect(mapping.videoTime(forRecordingTime: 35, segmentID: "main") == nil)
        #expect(mapping.videoTime(forRecordingTime: 35, segmentID: "later") == nil)
    }

    @Test func touchingEndpointsRequireExplicitSegment() throws {
        let mapping = try RecordingVideoClockMapping(segments: [
            segment(), segment("later", [(30, 0), (40, 10)])
        ])
        #expect(mapping.segmentID(forRecordingTime: 30) == nil)
        #expect(mapping.videoTime(forRecordingTime: 30, segmentID: "main") == 32)
        #expect(mapping.videoTime(forRecordingTime: 30, segmentID: "later") == 0)
    }

    @Test func degradedSegmentsRemainRepresentableButUnavailable() throws {
        let mapping = try RecordingVideoClockMapping(segments: [
            segment("good", [(0, 0), (10, 10)], error: 0.05),
            segment("degraded", [(10, 10), (20, 20)], error: 0.05001)
        ])
        #expect(mapping.segmentID(forRecordingTime: 5) == "good")
        #expect(mapping.segmentID(forRecordingTime: 10) == "good")
        #expect(mapping.segmentID(forRecordingTime: 15) == nil)
        #expect(mapping.videoTime(forRecordingTime: 15, segmentID: "degraded") == nil)
        #expect(mapping.recordingTime(forVideoTime: 15, segmentID: "degraded") == nil)
        #expect(mapping.videoTime(forRecordingTime: 5, segmentID: "good") == 5)
        let accepted = try RecordingVideoClockMapping(segments: [segment(error: 0.1)], tolerance: 0.1)
        #expect(accepted.videoTime(forRecordingTime: 15, segmentID: "main") == 7)
    }

    @Test func rejectsInvalidIDsCountsAndOverlapsWithTypedErrors() {
        for segments in [
            [segment("")], [segment(), segment()], [segment("short", [])],
            [segment("short", [(0, 0)])],
            [segment(), segment("overlap", [(29, 0), (40, 10)])],
            [segment("outer", [(0, 0), (100, 100)]), segment()]
        ] {
            #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
                try RecordingVideoClockMapping(segments: segments)
            }
        }
    }

    @Test func rejectsNonIncreasingAnchorsInEitherDomain() {
        let invalidPairs: [[(Double, Double)]] = [
            [(1, 1), (1, 2)], [(2, 1), (1, 2)],
            [(1, 1), (2, 1)], [(1, 2), (2, 1)],
            [(0, 0), (2, 2), (1, 3)]
        ]
        for pairs in invalidPairs {
            #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
                try RecordingVideoClockMapping(segments: [segment("bad", pairs)])
            }
        }
    }

    @Test func rejectsNonfiniteAndNegativeEvidence() {
        for invalid in [-1.0, .nan, .infinity, -.infinity] {
            for pairs in [[(invalid, 0.0), (10.0, 10.0)], [(0.0, invalid), (10.0, 10.0)],
                          [(0.0, 0.0), (invalid, 10.0)], [(0.0, 0.0), (10.0, invalid)]] {
                #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
                    try RecordingVideoClockMapping(segments: [segment("bad", pairs)])
                }
            }
            #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
                try RecordingVideoClockMapping(segments: [segment(error: invalid)])
            }
            #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
                try RecordingVideoClockMapping(segments: [], tolerance: invalid)
            }
        }
    }

    @Test func emptyEvidenceIsUnavailable() throws {
        let mapping = try RecordingVideoClockMapping(segments: [], tolerance: 0)
        #expect(mapping.segmentID(forRecordingTime: 0) == nil)
        #expect(mapping.videoTime(forRecordingTime: 0, segmentID: "main") == nil)
    }

    @Test func largeFiniteAnchorsDoNotOverflowInterpolation() throws {
        let mapping = try RecordingVideoClockMapping(segments: [
            segment("large", [(0, 0), (1e308, 1e308)], error: 0)
        ], tolerance: 0)
        #expect(mapping.videoTime(forRecordingTime: 5e307, segmentID: "large") == 5e307)
        #expect(mapping.recordingTime(forVideoTime: 5e307, segmentID: "large") == 5e307)
    }

    @Test func decodedEvidenceMustPassMappingValidation() throws {
        let data = Data(#"{"id":"decoded","anchors":[{"recordingTime":0,"videoTime":0},{"recordingTime":0,"videoTime":1}],"maximumError":0}"#.utf8)
        let decoded = try JSONDecoder().decode(RecordingVideoClockSegment.self, from: data)
        #expect(throws: RecordingVideoClockMapping.ValidationError.self) {
            try RecordingVideoClockMapping(segments: [decoded])
        }
    }
}

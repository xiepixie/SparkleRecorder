import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Reconstruction lookup scalability")
struct ReconstructionLookupPerformanceTests {
    @Test func longRecordingLookupWorkloadPreservesExactResults() throws {
        let count = 18_000
        let mapping = try RecordingVideoClockMapping(segments: [.init(id: "movie", anchors: (0..<count).map {
            .init(recordingTime: Double($0), videoTime: Double($0) * 2)
        }, maximumError: 0)])
        let geometry = try RecordingGeometryHistory(snapshots: (0..<count).map {
            .init(surfaceID: "window", recordingTime: Double($0), validUntil: Double($0) + 0.75,
                  captureBounds: .init(x: 0, y: 0, width: 100, height: 100), frameSize: .init(width: 200, height: 200))
        })
        var checksum = 0.0
        let elapsed = ContinuousClock().measure {
            for i in stride(from: 0, to: count - 1, by: 3) {
                checksum += mapping.videoTime(forRecordingTime: Double(i) + 0.5, segmentID: "movie") ?? -1
                checksum += Double(geometry.framePoint(forGlobalPoint: .init(x: 25, y: 50), surfaceID: "window", recordingTime: Double(i) + 0.5)?.x ?? -1)
            }
        }
        #expect(checksum == 108_288_000)
        #expect(geometry.framePoint(forGlobalPoint: .init(x: 25, y: 50), surfaceID: "window", recordingTime: 5.8) == nil)
        print("Reconstruction lookup workload: 18,000 anchors/snapshots, 6,000 paired queries: \(elapsed)")
    }
}

import Testing
@testable import SparkleRecorderCore

@Suite("Reconstruction video index")
struct MacroReconstructionVideoIndexTests {
    private func row(_ id: String, _ start: Double, _ duration: Double, segment: String = "movie") -> MacroReconstructionProjectedAction {
        .init(action: .init(id: id, kind: .wait, sourceEventIndices: [], startTime: start, endTime: start + duration),
              sessionRange: nil, videoSegmentID: segment, videoRange: .init(startTime: start, duration: duration),
              startFramePoint: nil, endFramePoint: nil, issues: [])
    }
    @Test func overlappingHighlightsGapsAndSegmentsMatchLinearReference() {
        let rows = [row("a", 1, 0), row("b", 1.05, 0.3), row("c", 3, 2), row("other", 1, 8, segment: "other")]
        let index = MacroReconstructionVideoIndex(rows: rows)
        for time in stride(from: 0.0, through: 6.0, by: 0.01) {
            let expected = rows.first { $0.videoSegmentID == "movie" && time >= $0.videoRange!.startTime && time <= $0.videoRange!.startTime + max(0.1, $0.videoRange!.duration) }
            #expect(index.activeRow(at: time, segmentID: "movie") == expected)
        }
        #expect(index.activeRow(at: .nan, segmentID: "movie") == nil)
        #expect(index.activeRow(at: 1, segmentID: "missing") == nil)
        #expect(index.row(actionID: "c") == rows[2])
    }
    @Test func largeIndexSupportsBackwardSeeking() {
        let rows = (0..<20_000).map { row(String($0), Double($0), 0.5) }
        let index = MacroReconstructionVideoIndex(rows: rows)
        for i in stride(from: 19_999, through: 0, by: -17) {
            #expect(index.activeRow(at: Double(i) + 0.25, segmentID: "movie")?.action.id == String(i))
        }
    }
}

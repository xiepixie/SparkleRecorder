import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Scroll Payload Builder Tests")
struct RecordingScrollPayloadBuilderTests {
    struct ScrollCase: Sendable {
        var name: String
        var sample: RecordingScrollSample
        var expectedPlaybackX: Int32
        var expectedPlaybackY: Int32
        var expectedFixedX: Double?
        var expectedFixedY: Double?
    }

    @Test(
        "Scroll samples preserve payload fields and derive playback deltas",
        arguments: [
            ScrollCase(
                name: "point deltas win over line fallback",
                sample: RecordingScrollSample(
                    pointDeltaX: 2,
                    pointDeltaY: -5,
                    lineDeltaX: 1,
                    lineDeltaY: -1,
                    phase: 1,
                    momentumPhase: 0,
                    fixedRawX: 0,
                    fixedRawY: 0,
                    isContinuous: true
                ),
                expectedPlaybackX: 2,
                expectedPlaybackY: -5,
                expectedFixedX: nil,
                expectedFixedY: nil
            ),
            ScrollCase(
                name: "line deltas convert to point fallback",
                sample: RecordingScrollSample(
                    pointDeltaX: 0,
                    pointDeltaY: 0,
                    lineDeltaX: 2,
                    lineDeltaY: -3,
                    phase: 0,
                    momentumPhase: 0,
                    fixedRawX: 0,
                    fixedRawY: 0,
                    isContinuous: false
                ),
                expectedPlaybackX: 24,
                expectedPlaybackY: -36,
                expectedFixedX: nil,
                expectedFixedY: nil
            ),
            ScrollCase(
                name: "fixed point deltas decode from raw 16.16 values",
                sample: RecordingScrollSample(
                    pointDeltaX: 0,
                    pointDeltaY: 0,
                    lineDeltaX: 0,
                    lineDeltaY: 0,
                    phase: 2,
                    momentumPhase: 3,
                    fixedRawX: 65_536,
                    fixedRawY: -131_072,
                    isContinuous: true
                ),
                expectedPlaybackX: 0,
                expectedPlaybackY: 0,
                expectedFixedX: 1.0,
                expectedFixedY: -2.0
            ),
        ]
    )
    func scrollSamplesPreservePayloadFieldsAndDerivePlaybackDeltas(_ testCase: ScrollCase) {
        let result = RecordingScrollPayloadBuilder.build(from: testCase.sample)

        #expect(result.playbackDeltaX == testCase.expectedPlaybackX, "\(testCase.name) playback X")
        #expect(result.playbackDeltaY == testCase.expectedPlaybackY, "\(testCase.name) playback Y")
        #expect(result.payload.deltaX == CGFloat(testCase.sample.pointDeltaX), "\(testCase.name) point X")
        #expect(result.payload.deltaY == CGFloat(testCase.sample.pointDeltaY), "\(testCase.name) point Y")
        #expect(result.payload.lineDeltaX == testCase.sample.lineDeltaX, "\(testCase.name) line X")
        #expect(result.payload.lineDeltaY == testCase.sample.lineDeltaY, "\(testCase.name) line Y")
        #expect(result.payload.phase == testCase.sample.phase, "\(testCase.name) phase")
        #expect(result.payload.momentumPhase == testCase.sample.momentumPhase, "\(testCase.name) momentum")
        #expect(result.payload.fixedDeltaX == testCase.expectedFixedX, "\(testCase.name) fixed X")
        #expect(result.payload.fixedDeltaY == testCase.expectedFixedY, "\(testCase.name) fixed Y")
        #expect(result.payload.isContinuous == testCase.sample.isContinuous, "\(testCase.name) continuous")
    }

    @Test("Line fallback clamps instead of overflowing Int32")
    func lineFallbackClampsInsteadOfOverflowingInt32() {
        let positive = RecordingScrollPayloadBuilder.build(
            from: RecordingScrollSample(
                pointDeltaX: 0,
                pointDeltaY: 0,
                lineDeltaX: Int32.max,
                lineDeltaY: Int32.min,
                phase: 0,
                momentumPhase: 0,
                fixedRawX: 0,
                fixedRawY: 0,
                isContinuous: false
            )
        )

        #expect(positive.playbackDeltaX == Int32.max)
        #expect(positive.playbackDeltaY == Int32.min)
    }
}

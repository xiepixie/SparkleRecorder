import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Drag Sampler Tests")
struct RecordingDragSamplerTests {
    struct ThresholdCase: Sendable {
        var name: String
        var location: CGPoint
        var time: TimeInterval
        var expected: RecordingDragSamplingDecision
    }

    @Test("First drag sample is always kept")
    func firstDragSampleIsAlwaysKept() {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: CGPoint(x: 10, y: 10), time: 1.0)

        let decision = sampler.processDrag(location: CGPoint(x: 10.5, y: 10.5), time: 1.001)

        #expect(decision == .keep(.firstDrag))
        #expect(sampler.lastDroppedSample == nil)
    }

    @Test(
        "Default threshold requires both elapsed time and distance",
        arguments: [
            ThresholdCase(
                name: "below time threshold",
                location: CGPoint(x: 3.0, y: 0),
                time: 0.025,
                expected: .drop
            ),
            ThresholdCase(
                name: "below distance threshold",
                location: CGPoint(x: 11.0, y: 0),
                time: 0.040,
                expected: .drop
            ),
            ThresholdCase(
                name: "meets both thresholds",
                location: CGPoint(x: 12.0, y: 0),
                time: 0.040,
                expected: .keep(.threshold)
            ),
        ]
    )
    func defaultThresholdRequiresElapsedTimeAndDistance(_ testCase: ThresholdCase) {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: .zero, time: 0)
        #expect(sampler.processDrag(location: CGPoint(x: 10, y: 0), time: 0.020) == .keep(.firstDrag))

        let decision = sampler.processDrag(location: testCase.location, time: testCase.time)

        #expect(decision == testCase.expected)
    }

    @Test("High speed samples bypass elapsed time threshold")
    func highSpeedSamplesBypassElapsedTimeThreshold() {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: .zero, time: 0)
        #expect(sampler.processDrag(location: CGPoint(x: 1, y: 0), time: 0.001) == .keep(.firstDrag))

        let decision = sampler.processDrag(location: CGPoint(x: 14, y: 0), time: 0.002)

        #expect(decision == .keep(.highSpeed))
    }

    @Test("Direction changes are kept to preserve curves")
    func directionChangesAreKeptToPreserveCurves() {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: .zero, time: 0)
        #expect(sampler.processDrag(location: CGPoint(x: 10, y: 0), time: 0.020) == .keep(.firstDrag))

        let decision = sampler.processDrag(location: CGPoint(x: 10, y: 5), time: 0.021)

        #expect(decision == .keep(.directionChange))
    }

    @Test("Dropped drag sample is flushed once on mouse up")
    func droppedDragSampleIsFlushedOnceOnMouseUp() throws {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: .zero, time: 0)
        #expect(sampler.processDrag(location: CGPoint(x: 10, y: 0), time: 0.020) == .keep(.firstDrag))
        #expect(sampler.processDrag(location: CGPoint(x: 10.5, y: 0), time: 0.021) == .drop)

        let droppedSample = sampler.processMouseUp()
        let dropped = try #require(droppedSample)

        #expect(dropped.location == CGPoint(x: 10.5, y: 0))
        #expect(dropped.time == 0.021)
        let secondFlush = sampler.processMouseUp()
        #expect(secondFlush == nil)
    }

    @Test("Mouse down resets dropped sample and first drag state")
    func mouseDownResetsDroppedSampleAndFirstDragState() {
        var sampler = RecordingDragSampler()
        sampler.processMouseDown(location: .zero, time: 0)
        #expect(sampler.processDrag(location: CGPoint(x: 10, y: 0), time: 0.020) == .keep(.firstDrag))
        #expect(sampler.processDrag(location: CGPoint(x: 10.5, y: 0), time: 0.021) == .drop)

        sampler.processMouseDown(location: CGPoint(x: 50, y: 50), time: 2.0)
        let decision = sampler.processDrag(location: CGPoint(x: 50.1, y: 50.1), time: 2.001)

        #expect(sampler.lastDroppedSample == nil)
        #expect(decision == .keep(.firstDrag))
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Scroll Gesture Compactor Tests")
struct ScrollGestureCompactorTests {
    private func scroll(
        time: Double,
        dy: Int32,
        x: CGFloat = 100,
        y: CGFloat = 200,
        flags: UInt64 = 0,
        surfaceID: String? = "surface-1",
        phase: Int = 1,
        momentumPhase: Int? = 0,
        continuous: Bool = true
    ) -> RecordedEvent {
        RecordedEvent(
            kind: .scrollWheel,
            time: time,
            x: x,
            y: y,
            keyCode: 0,
            flags: flags,
            mouseButton: 0,
            clickCount: 0,
            scrollDeltaY: dy,
            scrollDeltaX: 0,
            coordinateBinding: surfaceID == nil ? .globalScreen : .targetWindow,
            surfaceId: surfaceID,
            scrollPayload: ScrollPayload(
                deltaX: 0,
                deltaY: CGFloat(dy),
                lineDeltaX: 0,
                lineDeltaY: 0,
                phase: phase,
                momentumPhase: momentumPhase,
                fixedDeltaX: nil,
                fixedDeltaY: Double(dy),
                isContinuous: continuous
            )
        )
    }

    @Test("Continuous scroll is resampled by time while preserving cumulative delta and endpoints")
    func timeBasedResamplingPreservesCumulativeDelta() {
        var compactor = ScrollGestureCompactor(
            configuration: .init(sampleInterval: 1.0 / 30.0, maximumContinuousGap: 0.12)
        )
        var output: [ScrollGestureCompactionOutput] = []
        for index in 0..<121 {
            output += compactor.process(
                scroll(time: Double(index) / 120.0, dy: -1),
                evidenceSampleIndex: index
            )
        }
        output += compactor.finish()

        #expect(output.count < 45)
        #expect(output.first?.event.time == 0)
        #expect(abs((output.last?.event.time ?? -1) - 1.0) < 0.000_001)
        #expect(output.reduce(Int64(0)) { $0 + Int64($1.event.scrollDeltaY) } == -121)
        #expect(output.compactMap(\.evidenceSampleRange).first?.lowerBound == 0)
        #expect(output.compactMap(\.evidenceSampleRange).last?.upperBound == 120)
        #expect(output.allSatisfy { $0.event.scrollPayload?.phase == 1 })
    }

    @Test("Direction reversal starts at the original event time instead of a later bucket")
    func directionReversalIsAnExactBoundary() {
        var compactor = ScrollGestureCompactor(
            configuration: .init(sampleInterval: 0.05, maximumContinuousGap: 0.2)
        )
        var output: [ScrollGestureCompactionOutput] = []
        output += compactor.process(scroll(time: 6.900, dy: 2), evidenceSampleIndex: 0)
        output += compactor.process(scroll(time: 6.908, dy: 2), evidenceSampleIndex: 1)
        output += compactor.process(scroll(time: 6.916, dy: -1), evidenceSampleIndex: 2)
        output += compactor.process(scroll(time: 6.924, dy: -2), evidenceSampleIndex: 3)
        output += compactor.finish()

        let reversal = output.first { $0.event.time == 6.916 }
        #expect(reversal?.event.scrollDeltaY == -1)
        #expect(reversal?.evidenceSampleRange == 2...2)
        #expect(output.reduce(Int64(0)) { $0 + Int64($1.event.scrollDeltaY) } == 1)
    }

    @Test("Phase momentum flags surface and coordinate changes split continuous gestures")
    func metadataChangesSplitGestures() {
        let cases: [(RecordedEvent, RecordedEvent)] = [
            (scroll(time: 0, dy: 1, phase: 1), scroll(time: 0.01, dy: 1, phase: 2)),
            (scroll(time: 0, dy: 1, momentumPhase: 1), scroll(time: 0.01, dy: 1, momentumPhase: 2)),
            (scroll(time: 0, dy: 1, flags: 0), scroll(time: 0.01, dy: 1, flags: ModFlag.shift)),
            (scroll(time: 0, dy: 1, surfaceID: "surface-1"), scroll(time: 0.01, dy: 1, surfaceID: "surface-2")),
            (scroll(time: 0, dy: 1, x: 100), scroll(time: 0.01, dy: 1, x: 101))
        ]

        for (first, second) in cases {
            var compactor = ScrollGestureCompactor(
                configuration: .init(sampleInterval: 0.1, maximumContinuousGap: 0.2)
            )
            var output = compactor.process(first, evidenceSampleIndex: 0)
            output += compactor.process(second, evidenceSampleIndex: 1)
            output += compactor.finish()
            #expect(output.map(\.event.time) == [0, 0.01])
            #expect(output.map(\.evidenceSampleRange) == [0...0, 1...1])
        }
    }

    @Test("Long pauses split gestures without changing EventGrouper semantics")
    func longPauseSplitsCompactionOnly() {
        var compactor = ScrollGestureCompactor(
            configuration: .init(sampleInterval: 0.1, maximumContinuousGap: 0.12)
        )
        var output = compactor.process(scroll(time: 0, dy: 2), evidenceSampleIndex: 0)
        output += compactor.process(scroll(time: 0.2, dy: 3), evidenceSampleIndex: 1)
        output += compactor.finish()

        #expect(output.map(\.event.time) == [0, 0.2])
        #expect(output.map(\.event.scrollDeltaY) == [2, 3])
    }

    @Test("Discrete wheel events pass through unchanged")
    func discreteWheelPassesThrough() {
        var compactor = ScrollGestureCompactor()
        let first = scroll(time: 0, dy: -12, continuous: false)
        let second = scroll(time: 0.01, dy: -12, continuous: false)
        var output = compactor.process(first, evidenceSampleIndex: 10)
        output += compactor.process(second, evidenceSampleIndex: 11)
        output += compactor.finish()

        #expect(output.map(\.event) == [first, second])
        #expect(output.map(\.evidenceSampleRange) == [10...10, 11...11])
    }
}

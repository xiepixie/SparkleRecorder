import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Recording Timeline Tests")
struct RecordingTimelineTests {
    struct LiveDurationCase: Sendable {
        var currentMachTicks: UInt64
        var baseMachTicks: UInt64
        var timebase: RecordingTimebase
        var resumeOffset: TimeInterval
        var expected: TimeInterval
    }

    struct EventTimeCase: Sendable {
        var timestamp: UInt64
        var baseTimestamp: UInt64?
        var resumeOffset: TimeInterval
        var expectedBase: UInt64
        var expectedElapsed: TimeInterval
    }

    @Test(
        "Live duration applies mach timebase, resume offset, and inverted tick clamp",
        arguments: [
            LiveDurationCase(
                currentMachTicks: 2_500_000_000,
                baseMachTicks: 1_000_000_000,
                timebase: RecordingTimebase(numer: 1, denom: 1),
                resumeOffset: 0.25,
                expected: 1.75
            ),
            LiveDurationCase(
                currentMachTicks: 1_000,
                baseMachTicks: 2_000,
                timebase: RecordingTimebase(numer: 1, denom: 1),
                resumeOffset: 4.5,
                expected: 4.5
            ),
            LiveDurationCase(
                currentMachTicks: 8_000_000,
                baseMachTicks: 2_000_000,
                timebase: RecordingTimebase(numer: 125, denom: 3),
                resumeOffset: 0.1,
                expected: 0.35
            ),
        ]
    )
    func liveDurationAppliesTimebaseAndOffset(_ testCase: LiveDurationCase) {
        let duration = RecordingTimeline.liveDuration(
            currentMachTicks: testCase.currentMachTicks,
            baseMachTicks: testCase.baseMachTicks,
            resumeOffsetDuration: testCase.resumeOffset,
            timebase: testCase.timebase
        )

        #expect(abs(duration - testCase.expected) < 0.000_000_001)
    }

    @Test(
        "Event timestamp baseline is stable and elapsed time clamps inverted timestamps",
        arguments: [
            EventTimeCase(
                timestamp: 900_000_000,
                baseTimestamp: nil,
                resumeOffset: 0,
                expectedBase: 900_000_000,
                expectedElapsed: 0
            ),
            EventTimeCase(
                timestamp: 1_500_000_000,
                baseTimestamp: 900_000_000,
                resumeOffset: 0.25,
                expectedBase: 900_000_000,
                expectedElapsed: 0.85
            ),
            EventTimeCase(
                timestamp: 500_000_000,
                baseTimestamp: 900_000_000,
                resumeOffset: 2.0,
                expectedBase: 900_000_000,
                expectedElapsed: 2.0
            ),
        ]
    )
    func eventTimestampBaselineIsStable(_ testCase: EventTimeCase) {
        let eventTime = RecordingTimeline.eventTime(
            timestamp: testCase.timestamp,
            baseTimestamp: testCase.baseTimestamp,
            resumeOffsetDuration: testCase.resumeOffset
        )

        #expect(eventTime.baseTimestamp == testCase.expectedBase)
        #expect(abs(eventTime.elapsed - testCase.expectedElapsed) < 0.000_000_001)
    }

    @Test("Recording timebase guards zero denominator")
    func recordingTimebaseGuardsZeroDenominator() {
        let timebase = RecordingTimebase(numer: 42, denom: 0)

        #expect(timebase.numer == 42)
        #expect(timebase.denom == 1)
    }
}

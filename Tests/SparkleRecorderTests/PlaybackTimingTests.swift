import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Playback Timing Tests")
struct PlaybackTimingTests {
    @Test("Precise wait strategy sleeps only when delay clears threshold")
    func preciseWaitStrategySleepsOnlyAboveThreshold() {
        let strategy = PlaybackWaitStrategy.precise

        let short = strategy.plan(now: 10.0, target: 10.001)
        #expect(abs(short.delay - 0.001) < 0.000_001)
        #expect(short.sleepDuration == 0)
        #expect(abs(short.spinDuration - 0.001) < 0.000_001)
        #expect(!short.shouldSleep)

        let long = strategy.plan(now: 10.0, target: 10.010)
        #expect(abs(long.sleepDuration - 0.0095) < 0.000_001)
        #expect(abs(long.spinDuration - 0.0005) < 0.000_001)
        #expect(long.shouldSleep)
    }

    @Test("Wait plan converts sleep duration to nanoseconds")
    func waitPlanConvertsToNanoseconds() {
        let plan = PlaybackWaitPlan(delay: 0.005, sleepDuration: 0.0045, spinDuration: 0.0005)

        #expect(plan.sleepNanoseconds == 4_500_000)
    }

    @Test("Wait strategy handles late and non-finite inputs")
    func waitStrategyHandlesLateAndNonFiniteInputs() {
        let strategy = PlaybackWaitStrategy(sleepThreshold: .nan, spinLeadTime: -.infinity)

        let late = strategy.plan(now: 10.0, target: 9.0)
        #expect(late.delay == -1.0)
        #expect(late.sleepDuration == 0)
        #expect(late.spinDuration == 0)

        let invalid = strategy.plan(now: .nan, target: 10.0)
        #expect(invalid.delay == 0)
        #expect(invalid.sleepDuration == 0)
        #expect(invalid.spinDuration == 0)

        let long = strategy.plan(now: 0, target: 0.01)
        #expect(abs(long.sleepDuration - 0.0095) < 0.000_001)
    }

    @Test("Immediate clock is injectable and returns without waiting")
    func immediateClockIsInjectable() async {
        let clock = PlaybackClockClient.immediate(now: 42)

        #expect(clock.now() == 42)
        await clock.sleep(10)
        clock.sleepSynchronously(10)
        await clock.wait(until: 52)
        clock.waitSynchronously(until: 52)
        #expect(clock.now() == 42)
    }
}

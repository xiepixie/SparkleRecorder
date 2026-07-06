import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Macro Transformer Timing Tests")
struct MacroTransformerTimingTests {
    @Test("Live duration stretch preserves trailing wait beyond last event")
    func liveDurationStretchPreservesTrailingWaitBeyondLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 0.5, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 0.5)

        #expect(abs(stretched - 1.0) < 0.000_001)
    }

    @Test("Live duration stretch never falls behind scaled last event")
    func liveDurationStretchNeverFallsBehindScaledLastEvent() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0, x: 10, y: 10),
            RecordedEvent.make(.leftMouseUp, time: 3.0, x: 10, y: 10)
        ]

        let stretched = events.liveDurationAfterStretching(2.0, by: 2.0)

        #expect(abs(stretched - 6.0) < 0.000_001)
    }
}

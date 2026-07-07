import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Recorder Buffer Tests")
struct RecorderBufferTests {
    @MainActor
    @Test("Loading events without explicit duration snaps live duration to the loaded macro")
    func loadingEventsWithoutExplicitDurationSnapsLiveDurationToLoadedMacro() {
        let recorder = Recorder()
        recorder.loadEvents([
            RecordedEvent.make(.leftMouseDown, time: 0.1, x: 10, y: 10)
        ], duration: 89.12)

        let loadedEvents = [
            RecordedEvent.make(.leftMouseDown, time: 10.945, x: 1157, y: 860),
            RecordedEvent.make(.leftMouseUp, time: 11.208, x: 1157, y: 860)
        ]

        recorder.loadEvents(loadedEvents)

        #expect(abs(recorder.liveDuration - 11.208) < 0.000_001)
        let groups = EventGrouper().group(recorder.events, liveDuration: recorder.liveDuration)
        #expect(groups.last?.kind != .wait)
    }

    @MainActor
    @Test("Clearing the recorder buffer resets live duration")
    func clearingRecorderBufferResetsLiveDuration() {
        let recorder = Recorder()
        recorder.loadEvents([
            RecordedEvent.make(.leftMouseDown, time: 2.0, x: 10, y: 10)
        ], duration: 12.0)

        recorder.clearAll()

        #expect(recorder.events.isEmpty)
        #expect(recorder.liveDuration == 0)
    }
}

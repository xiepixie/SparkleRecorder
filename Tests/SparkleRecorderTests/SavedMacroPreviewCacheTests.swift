import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Saved Macro Preview Cache Tests")
struct SavedMacroPreviewCacheTests {
    @Test("Saved macro builds preview caches from events")
    func savedMacroBuildsPreviewCachesFromEvents() {
        let events = [
            RecordedEvent.make(.leftMouseDown, time: 0.0),
            RecordedEvent.make(.leftMouseUp, time: 0.1),
            RecordedEvent.make(.keyDown, time: 2.0)
        ]

        let macro = SavedMacro(name: "Preview", events: events)

        #expect(macro.duration == 2.0)
        #expect(macro.eventCount == 3)
        #expect(macro.waveformBars.count == 3)
        #expect(macro.needsPreviewCacheRefresh == false)
    }

    @Test("Manifest keeps preview cache after events are stripped")
    func manifestKeepsPreviewCacheAfterEventsAreStripped() throws {
        var macro = SavedMacro(
            name: "Manifest",
            events: [
                RecordedEvent.make(.leftMouseDown, time: 0.0),
                RecordedEvent.make(.leftMouseUp, time: 0.1),
                RecordedEvent.make(.scrollWheel, time: 1.5)
            ]
        )
        macro.events = []

        let encoded = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(SavedMacro.self, from: encoded)

        #expect(decoded.events.isEmpty)
        #expect(decoded.duration == 1.5)
        #expect(decoded.eventCount == 3)
        #expect(decoded.waveformBars.count == 3)
        #expect(decoded.needsPreviewCacheRefresh == false)
    }
}

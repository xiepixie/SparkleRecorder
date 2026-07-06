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

    @Test("Manifest round trips semantic recording reference")
    func manifestRoundTripsSemanticRecordingReference() throws {
        let recordingID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let reference = MacroSemanticRecordingReference(
            recordingID: recordingID,
            bundleRelativePath: "SemanticRecordings/\(recordingID.uuidString)",
            manifestRelativePath: "SemanticRecordings/\(recordingID.uuidString)/manifest.json",
            capturedAt: capturedAt,
            eventCount: 3
        )
        let macro = SavedMacro(
            name: "Semantic",
            events: [RecordedEvent.make(.leftMouseDown, time: 0.0)],
            semanticRecording: reference
        )

        let encoded = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(SavedMacro.self, from: encoded)

        #expect(decoded.semanticRecording == reference)
    }

    @Test("Manifest round trips playable sanitization summary")
    func manifestRoundTripsPlayableSanitizationSummary() throws {
        let recordingID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let summary = MacroPlayableSanitizationSummary(
            recordingID: recordingID,
            appliedAt: Date(timeIntervalSince1970: 1_800_000_700),
            sanitizedEventCount: 2,
            withheldReadableFieldCount: 3,
            reviewRequiredEventCount: 1,
            reviewRequiredFieldCount: 2
        )
        let macro = SavedMacro(
            name: "Sanitized",
            events: [RecordedEvent.make(.keyDown, time: 0.0)],
            playableSanitization: summary
        )

        let encoded = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(SavedMacro.self, from: encoded)

        #expect(decoded.playableSanitization == summary)
    }

    @Test("Legacy manifest without semantic recording reference decodes")
    func legacyManifestWithoutSemanticRecordingReferenceDecodes() throws {
        let macroID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let legacyJSON = """
        {
          "id": "\(macroID.uuidString)",
          "name": "Legacy",
          "events": [],
          "createdAt": 0,
          "modifiedAt": 0,
          "version": 3,
          "loops": 1,
          "speed": 1.0,
          "surfaces": {},
          "followWindowOffset": true,
          "tags": [],
          "favorite": false,
          "notes": "",
          "playCount": 0,
          "totalRunTime": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let decoded = try decoder.decode(SavedMacro.self, from: legacyJSON)

        #expect(decoded.id == macroID)
        #expect(decoded.semanticRecording == nil)
        #expect(decoded.playableSanitization == nil)
    }

    @Test("Playback context inherits saved surface binding")
    func playbackContextInheritsSavedSurfaceBinding() {
        let surface = TestFixtures.surface(
            appName: "Cookie Run Kingdom",
            bundleIdentifier: "com.devsisters.ck",
            windowTitle: "Cookie Run: Kingdom"
        )
        let macro = SavedMacro(
            name: "Bound",
            events: [RecordedEvent.make(.leftMouseDown, time: 0.0)],
            surfaces: [TestFixtures.surfaceId: surface],
            followWindowOffset: true
        )

        let context = macro.playbackContext

        #expect(context.surfaces == [TestFixtures.surfaceId: surface])
        #expect(context.currentSurfaceFrames.isEmpty)
        #expect(context.currentContentFrames.isEmpty)
        #expect(context.coordinateMode == .boundWindowOffset)
    }

    @Test("Playback context respects screen-absolute saved macro toggle")
    func playbackContextRespectsScreenAbsoluteSavedMacroToggle() {
        let surface = TestFixtures.surface()
        let macro = SavedMacro(
            name: "Absolute",
            events: [RecordedEvent.make(.leftMouseDown, time: 0.0)],
            surfaces: [TestFixtures.surfaceId: surface],
            followWindowOffset: false
        )

        #expect(macro.playbackContext.surfaces == [TestFixtures.surfaceId: surface])
        #expect(macro.playbackContext.coordinateMode == .screenAbsolute)
    }
}

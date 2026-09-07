import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro Export Privacy Sanitizer Tests")
struct MacroExportPrivacySanitizerTests {
    @Test("Macros without visual evidence export without consulting the bundle store")
    func plainMacroDoesNotLoadBundle() async throws {
        let probe = ExportBundleLoadProbe()
        let sanitizer = MacroExportPrivacySanitizer(loadBundle: { id in
            await probe.record(id)
            return SemanticRecordingBundle(id: id)
        })
        let events = [event(unicodeString: "safe")]
        let macro = SavedMacro(name: "Plain", events: events)

        let prepared = try await sanitizer.prepare(events, macro: macro)

        #expect(prepared == events)
        #expect(await probe.ids().isEmpty)
    }

    @Test("Visual evidence load failures stop export instead of returning raw events")
    func visualEvidenceFailureIsFailClosed() async {
        let recordingID = UUID()
        let sanitizer = MacroExportPrivacySanitizer(loadBundle: { _ in
            throw CocoaError(.fileReadNoSuchFile)
        })
        let macro = macro(recordingID: recordingID)

        await #expect(throws: MacroExportPrivacyFailure.self) {
            _ = try await sanitizer.prepare([event(unicodeString: "secret")], macro: macro)
        }
    }

    @Test("Visual evidence is loaded by the macro recording id before export")
    func visualEvidenceUsesLinkedRecording() async throws {
        let recordingID = UUID()
        let probe = ExportBundleLoadProbe()
        let sanitizer = MacroExportPrivacySanitizer(loadBundle: { id in
            await probe.record(id)
            return SemanticRecordingBundle(id: id)
        })
        let events = [event(unicodeString: "visible")]

        let prepared = try await sanitizer.prepare(events, macro: macro(recordingID: recordingID))

        #expect(prepared == events)
        #expect(await probe.ids() == [recordingID])
    }

    private func macro(recordingID: UUID) -> SavedMacro {
        SavedMacro(
            name: "Evidence",
            events: [],
            semanticRecording: MacroSemanticRecordingReference(
                recordingID: recordingID,
                bundleRelativePath: "SemanticRecordings/\(recordingID.uuidString)",
                manifestRelativePath: "SemanticRecordings/\(recordingID.uuidString)/manifest.json",
                eventCount: 1
            )
        )
    }

    private func event(unicodeString: String) -> RecordedEvent {
        RecordedEvent(
            kind: .keyDown,
            time: 0.1,
            x: 0,
            y: 0,
            keyCode: 0,
            flags: 0,
            mouseButton: 0,
            clickCount: 0,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            unicodeString: unicodeString
        )
    }
}

private actor ExportBundleLoadProbe {
    private var recordingIDs: [UUID] = []

    func record(_ id: UUID) { recordingIDs.append(id) }
    func ids() -> [UUID] { recordingIDs }
}

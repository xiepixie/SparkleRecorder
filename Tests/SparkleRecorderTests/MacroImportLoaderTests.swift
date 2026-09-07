import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro Import Loader Tests")
struct MacroImportLoaderTests {
    @Test("Native SavedMacro import preserves portable metadata for the commit layer")
    func loadsNativeSavedMacro() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("portable.tinyrec")
        let source = SavedMacro(
            name: "Portable",
            events: TestFixtures.clickPair(),
            hotkey: HotkeyBinding(keyCode: 15, name: "⌥R", modifiers: 2048)
        )
        try JSONEncoder().encode(source).write(to: url)

        let prepared = try MacroImportLoader.load(url: url)
        guard case .savedMacro(let loaded) = prepared else {
            Issue.record("Expected a native SavedMacro payload")
            return
        }
        #expect(loaded.id == source.id)
        #expect(loaded.name == source.name)
        #expect(loaded.events == source.events)
        #expect(loaded.hotkey == source.hotkey)
    }

    @Test("Unknown extensions still use content sniffing without changing the macro name")
    func sniffsTextMacroWithUnknownExtension() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("renamed.data")
        try TextMacroFormat.export(TestFixtures.clickPair())
            .write(to: url, atomically: true, encoding: .utf8)

        let prepared = try MacroImportLoader.load(url: url)
        guard case .events(
            let name,
            let events,
            let skippedEntryCount,
            let legacyVersionWarning
        ) = prepared else {
            Issue.record("Expected a text macro payload")
            return
        }
        #expect(name == "renamed")
        #expect(events == TestFixtures.clickPair())
        #expect(skippedEntryCount == 0)
        #expect(!legacyVersionWarning)
    }

    @Test("Text parser diagnostics stay structured for localized presentation")
    func keepsSkippedEntriesStructured() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("partial.txt")
        let text = """
        SPARKLERECORDER 1
        @0.000 MOVE 10 20
        BROKEN ENTRY
        """
        try text.write(to: url, atomically: true, encoding: .utf8)

        let prepared = try MacroImportLoader.load(url: url)
        guard case .events(_, let events, let skippedEntryCount, let legacyVersionWarning) = prepared else {
            Issue.record("Expected a text macro payload")
            return
        }
        #expect(events.count == 1)
        #expect(skippedEntryCount == 1)
        #expect(!legacyVersionWarning)
        #expect(MacroImportPresentation.warning(
            skippedEntryCount: skippedEntryCount,
            legacyVersionWarning: legacyVersionWarning
        ) != nil)
    }

    @Test("GUI import errors do not expose parser implementation details")
    func presentsStableImportErrors() {
        let recMessage = MacroImportPresentation.errorMessage(
            MacroImportError.notRecFormat("length 37 is not a multiple of 20 bytes")
        )
        let textMessage = MacroImportPresentation.errorMessage(
            MacroImportError.notTextFormat("missing internal header token")
        )
        let unreadableMessage = MacroImportPresentation.errorMessage(
            MacroImportError.unreadable("opaque parser detail")
        )

        #expect(!recMessage.contains("37"))
        #expect(!textMessage.contains("internal"))
        #expect(!unreadableMessage.contains("opaque"))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderImportTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

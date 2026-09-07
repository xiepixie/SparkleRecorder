import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro Export Writer Tests")
struct MacroExportWriterTests {
    @Test("Text export writes the canonical editable format")
    func writesTextFormat() async throws {
        let url = temporaryURL(extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let events = [event()]

        try await MacroExportWriter.writeText(events, to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("SPARKLERECORDER 1\n"))
        #expect(text.contains("KEYDOWN"))
    }

    @Test("Native export round-trips SavedMacro metadata")
    func writesNativeMacro() async throws {
        let url = temporaryURL(extension: "tinyrec")
        defer { try? FileManager.default.removeItem(at: url) }
        let macro = SavedMacro(name: "Round Trip", events: [event()], loops: 3, speed: 1.5)

        try await MacroExportWriter.writeNative(macro, to: url)

        let decoded = try JSONDecoder().decode(SavedMacro.self, from: Data(contentsOf: url))
        #expect(decoded == macro)
    }

    @Test("Shell export is executable and safely quotes the app path")
    func writesExecutableShellMacro() async throws {
        let url = temporaryURL(extension: "command")
        defer { try? FileManager.default.removeItem(at: url) }
        let macro = SavedMacro(name: "Script", events: [event()])
        let executable = "/Applications/Sparkle $ Recorder/Recorder\"App"

        try await MacroExportWriter.writeShellScript(
            macro,
            executablePath: executable,
            to: url
        )

        let script = try String(contentsOf: url, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(script.contains("EXEC=\"/Applications/Sparkle \\$ Recorder/Recorder\\\"App\""))
        #expect(permissions?.intValue == 0o755)
        #expect(script.contains("--play"))
    }

    private func temporaryURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-export-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    private func event() -> RecordedEvent {
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
            unicodeString: "a"
        )
    }
}

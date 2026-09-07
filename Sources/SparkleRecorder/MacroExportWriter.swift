import Foundation
import SparkleRecorderCore

struct MacroExportPrivacyFailure: LocalizedError, Sendable {
    var errorDescription: String? {
        String(
            localized: "Visual evidence could not be verified, so export was stopped to avoid exposing sensitive text.",
            table: "Common"
        )
    }
}

/// Performs potentially large serialization and file IO away from MainActor.
/// Callers own user interaction, privacy preparation, and destination selection;
/// this Module owns only deterministic serialization + durable file writing.
enum MacroExportWriter {
    static func writeText(_ events: [RecordedEvent], to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let text = TextMacroFormat.export(events)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    static func writeNative(_ macro: SavedMacro, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(macro)
            try data.write(to: url, options: .atomic)
        }.value
    }

    static func writeShellScript(
        _ macro: SavedMacro,
        executablePath: String,
        to url: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let json = try JSONEncoder().encode(macro)
            let macroLine = json.base64EncodedString()
            let executable = shellDoubleQuoted(executablePath)
            let script = """
            #!/bin/bash
            # SparkleRecorder self-running macro
            EXEC=\(executable)
            if [ ! -x "$EXEC" ]; then
                echo "SparkleRecorder binary not found at $EXEC. Please install SparkleRecorder."
                exit 1
            fi
            TMP=$(mktemp -t tinyrec).json
            echo "\(macroLine)" | base64 -D > "$TMP"
            "$EXEC" --play "$TMP"
            rm -f "$TMP"
            """
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }.value
    }

    private static func shellDoubleQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }
}

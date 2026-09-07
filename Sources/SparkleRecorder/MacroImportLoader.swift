import Foundation
import SparkleRecorderCore

enum PreparedMacroImport: Sendable {
    case savedMacro(SavedMacro)
    case events(
        name: String,
        events: [RecordedEvent],
        skippedEntryCount: Int,
        legacyVersionWarning: Bool
    )
}

enum MacroImportLoader {
    static func load(url: URL) throws -> PreparedMacroImport {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent

        if ext == "tinyrec" || ext == "json" {
            let decoder = JSONDecoder()
            if let saved = try? decoder.decode(SavedMacro.self, from: data) {
                return .savedMacro(saved)
            }
            if let macro = try? decoder.decode(Macro.self, from: data) {
                return .events(
                    name: name,
                    events: macro.events,
                    skippedEntryCount: 0,
                    legacyVersionWarning: false
                )
            }
        }

        let result: MacroImportResult
        switch ext {
        case "rec":
            result = try LegacyRecImporter.parse(data)
        case "txt", "trm":
            guard let text = String(data: data, encoding: .utf8) else {
                throw MacroImportError.notTextFormat("file is not UTF-8 text.")
            }
            result = try TextMacroFormat.parse(text)
        default:
            if data.count % 20 == 0, let parsed = try? LegacyRecImporter.parse(data) {
                result = parsed
            } else if let text = String(data: data, encoding: .utf8),
                      let parsed = try? TextMacroFormat.parse(text) {
                result = parsed
            } else if let macro = try? JSONDecoder().decode(Macro.self, from: data) {
                result = MacroImportResult(
                    events: macro.events,
                    parsed: macro.events.count,
                    skipped: 0,
                    warning: nil
                )
            } else {
                throw MacroImportError.unreadable("Unrecognized macro file format.")
            }
        }

        return .events(
            name: name,
            events: result.events,
            skippedEntryCount: result.skipped,
            legacyVersionWarning: result.warning != nil
        )
    }
}

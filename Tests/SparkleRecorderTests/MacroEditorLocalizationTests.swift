import Foundation
import Testing

@Suite("Macro Editor Localization Tests")
struct MacroEditorLocalizationTests {
    @Test("Macro editor localized strings have English and Simplified Chinese entries")
    func macroEditorLocalizedStringsHaveEnglishAndSimplifiedChineseEntries() throws {
        let root = repositoryRoot()
        let sourceFiles = try macroEditorSourceFiles(root: root)
        let localizedKeys = try sourceFiles.reduce(into: Set<String>()) { keys, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            keys.formUnion(Self.localizedStringKeys(in: source))
        }
        let catalog = try localizationCatalog(root: root)

        var missingEntries: [String] = []
        var missingEnglish: [String] = []
        var missingSimplifiedChinese: [String] = []

        for key in localizedKeys.sorted() {
            guard let entry = catalog[key] as? [String: Any] else {
                missingEntries.append(key)
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            if localizations["en"] == nil {
                missingEnglish.append(key)
            }
            if localizations["zh-Hans"] == nil {
                missingSimplifiedChinese.append(key)
            }
        }

        #expect(missingEntries.isEmpty, "Missing Localizable.xcstrings entries: \(missingEntries)")
        #expect(missingEnglish.isEmpty, "Missing English localizations: \(missingEnglish)")
        #expect(missingSimplifiedChinese.isEmpty, "Missing Simplified Chinese localizations: \(missingSimplifiedChinese)")
    }

    @Test("Macro editor avoids hard-coded static visible strings")
    func macroEditorAvoidsHardCodedStaticVisibleStrings() throws {
        let root = repositoryRoot()
        let sourceFiles = try macroEditorSourceFiles(root: root)
        var hardCoded: [String] = []

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for literal in Self.staticVisibleStringLiterals(in: source) where !Self.allowedLiteral(literal.value) {
                hardCoded.append("\(file.lastPathComponent):\(literal.line): \(literal.kind)(\"\(literal.value)\")")
            }
        }

        #expect(hardCoded.isEmpty, "Hard-coded Macro Editor visible strings should use NSLocalizedString: \(hardCoded)")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func macroEditorSourceFiles(root: URL) throws -> [URL] {
        let editorDirectory = root.appendingPathComponent("Sources/SparkleRecorder/Components/Editor")
        let editorFiles = try FileManager.default.contentsOfDirectory(
            at: editorDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        return editorFiles + [root.appendingPathComponent("Sources/SparkleRecorder/MacroEditor.swift")]
    }

    private func localizationCatalog(root: URL) throws -> [String: Any] {
        let url = root.appendingPathComponent("Sources/SparkleRecorder/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(rootObject["strings"] as? [String: Any])
    }

    private static func localizedStringKeys(in source: String) -> Set<String> {
        let pattern = #"NSLocalizedString\("((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[keyRange])
        })
    }

    private static func staticVisibleStringLiterals(in source: String) -> [(kind: String, value: String, line: Int)] {
        let pattern = #"(Text|Button|Label|TextField)\("((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let kindRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else {
                return nil
            }
            let value = String(source[valueRange])
            guard !value.contains(#"\("#) else {
                return nil
            }
            return (
                kind: String(source[kindRange]),
                value: value,
                line: source[..<kindRange.lowerBound].reduce(into: 1) { line, character in
                    if character == "\n" {
                        line += 1
                    }
                }
            )
        }
    }

    private static func allowedLiteral(_ value: String) -> Bool {
        let technicalOrSymbolicLiterals: Set<String> = [
            "",
            "#",
            "X",
            "Y",
            "s",
            "·",
            "—"
        ]
        return technicalOrSymbolicLiterals.contains(value)
    }
}

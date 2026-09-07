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

    @Test("Macro editor localized calls use the declared catalog")
    func macroEditorLocalizedCallsUseDeclaredCatalog() throws {
        let root = repositoryRoot()
        let sourceFiles = try macroEditorSourceFiles(root: root)
        let catalogs = try localizationCatalogs(root: root)
        var mismatches: [String] = []

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for reference in Self.localizedStringReferences(in: source) {
                guard catalogs[reference.table]?[reference.key] != nil else {
                    mismatches.append("\(file.lastPathComponent): [\(reference.table)] \(reference.key)")
                    continue
                }
            }
        }

        #expect(mismatches.isEmpty, "Macro Editor localized calls must use the catalog that owns the key: \(mismatches)")
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
        try localizationCatalogs(root: root).values.reduce(into: [:]) { mergedStrings, strings in
            for (key, value) in strings {
                mergedStrings[key] = value
            }
        }
    }

    private func localizationCatalogs(root: URL) throws -> [String: [String: Any]] {
        let folder = root.appendingPathComponent("Sources/SparkleRecorder")
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let xcstringsFiles = contents.filter { $0.pathExtension == "xcstrings" }

        var catalogs: [String: [String: Any]] = [:]
        for file in xcstringsFiles {
            let data = try Data(contentsOf: file)
            let rootObject = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            if let strings = rootObject["strings"] as? [String: Any] {
                catalogs[file.deletingPathExtension().lastPathComponent] = strings
            }
        }
        return catalogs
    }

    private struct LocalizedStringReference {
        let key: String
        let table: String
    }

    private static func localizedStringReferences(in source: String) -> [LocalizedStringReference] {
        var references: [LocalizedStringReference] = []
        let literalPatterns = [
            #"String\(localized:\s*"((?:[^"\\]|\\.)*)"\s*,\s*table:\s*"([^"]+)""#,
            #"(?:Text|Button|Label|TextField)\("((?:[^"\\]|\\.)*)"\s*,\s*tableName:\s*"([^"]+)""#,
        ]

        for pattern in literalPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard match.numberOfRanges > 2,
                      let keyRange = Range(match.range(at: 1), in: source),
                      let tableRange = Range(match.range(at: 2), in: source) else {
                    continue
                }
                references.append(LocalizedStringReference(
                    key: String(source[keyRange]),
                    table: String(source[tableRange])
                ))
            }
        }

        return references
    }

    private static func localizedStringKeys(in source: String) -> Set<String> {
        var keys = Set<String>()

        // 1. NSLocalizedString("key", ...)
        let nsPattern = #"NSLocalizedString\("((?:[^"\\]|\\.)*)""#
        if let regex = try? NSRegularExpression(pattern: nsPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: source) {
                    keys.insert(String(source[r]))
                }
            }
        }

        // 2. String(localized: "key", ...)
        let strPattern = #"String\(localized:\s*"((?:[^"\\]|\\.)*)""#
        if let regex = try? NSRegularExpression(pattern: strPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: source) {
                    keys.insert(String(source[r]))
                }
            }
        }

        // 3. Text("key", tableName: "...") / Button("key", tableName: "...")
        let uiPattern = #"(?:Text|Button|Label|TextField)\("((?:[^"\\]|\\.)*)",\s*tableName:"#
        if let regex = try? NSRegularExpression(pattern: uiPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: source) {
                    keys.insert(String(source[r]))
                }
            }
        }

        return keys
    }

    private static func staticVisibleStringLiterals(in source: String) -> [(kind: String, value: String, line: Int)] {
        let pattern = #"(Text|Button|Label|TextField)\("((?:[^"\\]|\\.)*)"(\s*,\s*tableName:\s*"[^"]*")?"#
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
            // If tableName is provided, it is properly localized via String Catalog per AGENTS.md.
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
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

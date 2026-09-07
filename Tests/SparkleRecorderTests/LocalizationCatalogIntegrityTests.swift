import Foundation
import Testing

@Suite("Localization Catalog Integrity Tests")
struct LocalizationCatalogIntegrityTests {
    @Test("Every catalog entry has a Simplified Chinese translation")
    func everyCatalogEntryHasSimplifiedChineseTranslation() throws {
        var missing: [String] = []

        for catalogURL in try catalogURLs() {
            let strings = try catalogStrings(at: catalogURL)
            for key in strings.keys.sorted() {
                guard let entry = strings[key] as? [String: Any],
                      let localizations = entry["localizations"] as? [String: Any],
                      let simplifiedChinese = localizations["zh-Hans"] as? [String: Any],
                      let stringUnit = simplifiedChinese["stringUnit"] as? [String: Any],
                      stringUnit["state"] as? String == "translated",
                      let value = stringUnit["value"] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    missing.append("\(catalogURL.lastPathComponent): \(key)")
                    continue
                }
            }
        }

        #expect(missing.isEmpty, "Missing Simplified Chinese translations: \(missing)")
    }

    @Test("Manual catalog entries keep explicit English translations")
    func manualCatalogEntriesKeepExplicitEnglishTranslations() throws {
        var missing: [String] = []

        for catalogURL in try catalogURLs() {
            let strings = try catalogStrings(at: catalogURL)
            for key in strings.keys.sorted() {
                guard let entry = strings[key] as? [String: Any],
                      entry["extractionState"] as? String == "manual" else {
                    continue
                }

                guard let localizations = entry["localizations"] as? [String: Any],
                      let english = localizations["en"] as? [String: Any],
                      let stringUnit = english["stringUnit"] as? [String: Any],
                      stringUnit["state"] as? String == "translated",
                      let value = stringUnit["value"] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    missing.append("\(catalogURL.lastPathComponent): \(key)")
                    continue
                }
            }
        }

        #expect(missing.isEmpty, "Manual entries missing explicit English translations: \(missing)")
    }

    @Test("Cross-catalog duplication does not grow")
    func crossCatalogDuplicationDoesNotGrow() throws {
        let catalogs = try catalogsByName()
        var owners: [String: [String]] = [:]

        for (table, strings) in catalogs {
            for key in strings.keys {
                owners[key, default: []].append(table)
            }
        }

        let duplicateKeys = owners.filter { $0.value.count > 1 }
        #expect(
            duplicateKeys.count <= 274,
            "Cross-catalog duplicate keys increased from the migration baseline of 274: \(duplicateKeys.count)"
        )
    }

    @Test("Cross-catalog translation conflicts stay on the reviewed allowlist")
    func crossCatalogTranslationConflictsStayOnReviewedAllowlist() throws {
        let catalogs = try catalogsByName()
        var entriesByKey: [String: [(table: String, entry: [String: Any])]] = [:]

        for (table, strings) in catalogs {
            for (key, rawEntry) in strings {
                guard let entry = rawEntry as? [String: Any] else { continue }
                entriesByKey[key, default: []].append((table, entry))
            }
        }

        let reviewedConflicts: Set<String> = [
            "Match",
            "Moves",
            "Needs review",
            "Run",
            "Text to find",
            "Timing",
        ]
        var unexpected: [String] = []

        for (key, entries) in entriesByKey where entries.count > 1 {
            let simplifiedChineseValues = Set(entries.compactMap { pair in
                let localizations = pair.entry["localizations"] as? [String: Any]
                let simplifiedChinese = localizations?["zh-Hans"] as? [String: Any]
                let stringUnit = simplifiedChinese?["stringUnit"] as? [String: Any]
                return stringUnit?["value"] as? String
            })
            if simplifiedChineseValues.count > 1, !reviewedConflicts.contains(key) {
                unexpected.append(key)
            }
        }

        #expect(unexpected.isEmpty, "New cross-catalog translation conflicts require review: \(unexpected.sorted())")
    }

    @Test("App status feedback keys exist in their declared catalogs")
    func appStatusFeedbackKeysExistInDeclaredCatalogs() throws {
        let catalogs = try catalogsByName()
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources/SparkleRecorder")
        let sourceFiles = try swiftFiles(in: sourceRoot)
        let localizedPattern = #"String\s*\(\s*localized:\s*\"((?:[^\"\\]|\\.)*)\"\s*,\s*table:\s*\"([^\"]+)\""#
        let localizedRegex = try NSRegularExpression(pattern: localizedPattern)
        var missing: [String] = []

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in presentStatusCalls(in: source) {
                let bodyRange = NSRange(call.body.startIndex..<call.body.endIndex, in: call.body)
                for match in localizedRegex.matches(in: call.body, range: bodyRange) {
                    guard match.numberOfRanges > 2,
                          let keyRange = Range(match.range(at: 1), in: call.body),
                          let tableRange = Range(match.range(at: 2), in: call.body) else {
                        continue
                    }
                    let key = String(call.body[keyRange])
                    let table = String(call.body[tableRange])
                    guard catalogs[table]?[key] != nil else {
                        missing.append("\(file.lastPathComponent):\(call.line) [\(table)] \(key)")
                        continue
                    }
                }
            }
        }

        #expect(
            missing.isEmpty,
            "App status feedback uses localized keys missing from their declared catalogs: \(missing)"
        )
    }

    @Test("Localized helper calls point at the catalog that owns the key")
    func localizedHelperCallsPointAtOwningCatalog() throws {
        let catalogs = try catalogsByName()
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources/SparkleRecorder")
        let sourceFiles = try swiftFiles(in: sourceRoot)
        let tableNames = [
            "common": "Common",
            "automation": "Automation",
            "recording": "Recording",
            "settings": "Settings",
            "editorUX": "EditorUX",
        ]
        let pattern = #"LocalizedSystem(?:Button|Label)\("((?:[^"\\]|\\.)*)",\s*tableName:\s*L10nTable\.(common|automation|recording|settings|editorUX)"#
        let regex = try NSRegularExpression(pattern: pattern)
        var mismatches: [String] = []

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard match.numberOfRanges > 2,
                      let keyRange = Range(match.range(at: 1), in: source),
                      let tableRange = Range(match.range(at: 2), in: source) else {
                    continue
                }
                let key = String(source[keyRange])
                let tableToken = String(source[tableRange])
                guard let table = tableNames[tableToken] else { continue }
                guard catalogs[table]?[key] != nil else {
                    let line = source[..<keyRange.lowerBound].reduce(into: 1) { line, character in
                        if character == "\n" { line += 1 }
                    }
                    mismatches.append("\(file.lastPathComponent):\(line) [\(table)] \(key)")
                    continue
                }
            }
        }

        #expect(mismatches.isEmpty, "Localized helper uses a key from the wrong catalog: \(mismatches)")
    }

    private func presentStatusCalls(in source: String) -> [(body: String, line: Int)] {
        var calls: [(body: String, line: Int)] = []
        var searchStart = source.startIndex
        let marker = "presentStatus("

        while searchStart < source.endIndex,
              let markerRange = source.range(
                of: marker,
                range: searchStart..<source.endIndex
              ) {
            let openingParen = source.index(before: markerRange.upperBound)
            var cursor = source.index(after: openingParen)
            var depth = 1
            var insideString = false
            var escaped = false

            while cursor < source.endIndex, depth > 0 {
                let character = source[cursor]
                if insideString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        insideString = false
                    }
                } else {
                    if character == "\"" {
                        insideString = true
                    } else if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                    }
                }
                cursor = source.index(after: cursor)
            }

            guard depth == 0 else { break }
            let closingParen = source.index(before: cursor)
            let bodyStart = source.index(after: openingParen)
            let line = source[..<markerRange.lowerBound].reduce(into: 1) { line, character in
                if character == "\n" { line += 1 }
            }
            calls.append((String(source[bodyStart..<closingParen]), line))
            searchStart = cursor
        }

        return calls
    }

    private func catalogURLs() throws -> [URL] {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources/SparkleRecorder")
        return try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "xcstrings" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func catalogsByName() throws -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for url in try catalogURLs() {
            result[url.deletingPathExtension().lastPathComponent] = try catalogStrings(at: url)
        }
        return result
    }

    private func catalogStrings(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let rootObject = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(rootObject["strings"] as? [String: Any])
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

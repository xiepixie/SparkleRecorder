import Foundation
import SparkleRecorderCore

package enum WorkflowMacroCatalog {
    private struct LegacyLibraryData: Decodable {
        var macros: [SavedMacro]
    }

    package static var defaultDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
            .appendingPathComponent("Macros", isDirectory: true)
    }

    package static func load(macrosDirectory: URL?) throws -> [SavedMacro] {
        let fileManager = FileManager.default
        let directory = macrosDirectory ?? defaultDirectory
        guard fileManager.fileExists(atPath: directory.path) else {
            if macrosDirectory == nil, let legacy = try loadLegacyLibrary() {
                return legacy
            }
            return []
        }

        let packageURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let manifests = packageURLs
            .filter { $0.pathExtension == "sparkrec" }
            .compactMap { packageURL -> SavedMacro? in
                let manifestURL = packageURL.appendingPathComponent("macro.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      var macro = try? decode(SavedMacro.self, from: data) else {
                    return nil
                }
                let eventsURL = packageURL.appendingPathComponent("events.json")
                if let eventData = try? Data(contentsOf: eventsURL),
                   let events = try? decode([RecordedEvent].self, from: eventData) {
                    macro.events = events
                    macro.refreshCachesFromEvents()
                }
                return macro
            }

        if manifests.isEmpty, macrosDirectory == nil, let legacy = try loadLegacyLibrary() {
            return legacy
        }

        return manifests.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt > right.createdAt
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private static func loadLegacyLibrary() throws -> [SavedMacro]? {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let legacyURL = appSupport
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
            .appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: legacyURL)
            return try decode(LegacyLibraryData.self, from: data).macros
        } catch let error as WorkflowCLIError {
            throw error
        } catch {
            throw WorkflowCLIError(
                "fileReadFailed",
                "Could not read file '\(legacyURL.path)': \(error.localizedDescription)",
                path: legacyURL.path
            )
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let value = try? isoDecoder.decode(type, from: data) {
            return value
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkflowCLIError(
                "jsonDecodeFailed",
                "Could not decode workflow JSON: \(error.localizedDescription)"
            )
        }
    }
}

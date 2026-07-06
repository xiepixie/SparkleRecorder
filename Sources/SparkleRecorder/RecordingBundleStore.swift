import Foundation
import SparkleRecorderCore

actor RecordingBundleStore {
    let rootDirectory: URL

    init(
        rootDirectory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
            .appendingPathComponent("SemanticRecordings", isDirectory: true)
    ) {
        self.rootDirectory = rootDirectory
    }

    func createBundleDirectory(recordingID: UUID) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(recordingID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try createBundleSubdirectories(in: directory)
        return directory
    }

    func write(_ bundle: SemanticRecordingBundle, to directory: URL) throws {
        try createBundleSubdirectories(in: directory)
        try writeJSON(bundle, to: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName))
        try writeJSON(
            bundle.videoSegments,
            to: directory
                .appendingPathComponent("video", isDirectory: true)
                .appendingPathComponent("segments.json")
        )
        try writeJSONLines(
            bundle.frames,
            to: directory
                .appendingPathComponent("frames", isDirectory: true)
                .appendingPathComponent("index.jsonl")
        )
        try writeJSONLines(
            bundle.timelineEvents,
            to: directory.appendingPathComponent(SemanticRecordingSchema.privateTimelineFileName)
        )
        try writeJSONLines(
            bundle.aiSafeEvents,
            to: directory.appendingPathComponent(SemanticRecordingSchema.aiSafeEventsFileName)
        )
        try writeJSONLines(
            bundle.visualObservations,
            to: directory
                .appendingPathComponent("ocr", isDirectory: true)
                .appendingPathComponent("observations.jsonl")
        )
        try writeJSONLines(
            bundle.suppressions,
            to: directory.appendingPathComponent(SemanticRecordingSchema.suppressionsFileName)
        )
    }

    func loadManifest(from directory: URL) throws -> SemanticRecordingBundle {
        let data = try Data(contentsOf: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName))
        return try Self.decoder.decode(SemanticRecordingBundle.self, from: data)
    }

    private func createBundleSubdirectories(in directory: URL) throws {
        for component in ["video", "frames", "ocr", "accessibility", "windows", "visual-index", "ai", "runs"] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output = Data()
        for value in values {
            output.append(try Self.jsonLineEncoder.encode(value))
            output.append(Data("\n".utf8))
        }
        try output.write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var jsonLineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

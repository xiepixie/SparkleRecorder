import Foundation
import SparkleRecorderCore

package func encodeWorkflowCLIJSON<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
        return try encoder.encode(value)
    } catch {
        throw WorkflowCLIError(
            "jsonEncodeFailed",
            "Could not encode workflow JSON: \(error.localizedDescription)"
        )
    }
}

package func readWorkflowCLIFile(at path: String) throws -> Data {
    do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw WorkflowCLIError(
            "fileReadFailed",
            "Could not read file '\(path)': \(error.localizedDescription)",
            path: path
        )
    }
}

package func decodeWorkflowCLIJSON<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    let isoDecoder = JSONDecoder()
    isoDecoder.dateDecodingStrategy = .iso8601
    do {
        return try isoDecoder.decode(type, from: data)
    } catch {
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

package func decodeWorkflowMacroCatalog(from data: Data) throws -> [AutomationWorkflowDraftMacroCatalogEntry] {
    if let entries = try? decodeWorkflowCLIJSON([AutomationWorkflowDraftMacroCatalogEntry].self, from: data) {
        return entries
    }
    let envelope = try decodeWorkflowCLIJSON(
        AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>.self,
        from: data
    )
    return envelope.data?.macros ?? []
}

package func writeWorkflowCLIFile(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    do {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    } catch {
        throw WorkflowCLIError(
            "fileWriteFailed",
            "Could not write file '\(path)': \(error.localizedDescription)",
            path: path
        )
    }
}

package func writeWorkflowJSON<Value: Encodable>(_ value: Value) {
    guard let data = try? encodeWorkflowCLIJSON(value) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

package func writeWorkflowError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

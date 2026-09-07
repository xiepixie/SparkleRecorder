import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Workflow CLI Output Tests")
struct WorkflowCLIOutputTests {
    private struct Payload: Codable, Equatable {
        var zeta: Int
        var alpha: Int
        var createdAt: Date
    }

    @Test("Workflow CLI JSON keeps sorted pretty ISO-8601 output")
    func workflowCLIJSONKeepsStableEncodingPolicy() throws {
        let data = try encodeWorkflowCLIJSON(Payload(
            zeta: 2,
            alpha: 1,
            createdAt: Date(timeIntervalSince1970: 0)
        ))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\n"))
        #expect(text.contains("1970-01-01T00:00:00Z"))
        let alphaRange = try #require(text.range(of: "\"alpha\""))
        let zetaRange = try #require(text.range(of: "\"zeta\""))
        #expect(alphaRange.lowerBound < zetaRange.lowerBound)
    }

    @Test("Workflow CLI reader and decoder share ISO-8601 policy")
    func workflowCLIReaderAndDecoderShareISO8601Policy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-CLIOutput-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("payload.json").path
        let expected = Payload(
            zeta: 2,
            alpha: 1,
            createdAt: Date(timeIntervalSince1970: 1_725_552_000)
        )

        try writeWorkflowCLIFile(try encodeWorkflowCLIJSON(expected), to: path)
        let decoded = try decodeWorkflowCLIJSON(Payload.self, from: readWorkflowCLIFile(at: path))

        #expect(decoded == expected)
    }

    @Test("Macro catalog decoder accepts direct arrays and CLI envelopes")
    func macroCatalogDecoderAcceptsDirectArraysAndEnvelopes() throws {
        let entry = AutomationWorkflowDraftMacroCatalogEntry(
            id: UUID(uuidString: "74000000-0000-0000-0000-000000000099")!,
            name: "Catalog Macro",
            durationSeconds: 1.25,
            eventCount: 3
        )

        let direct = try encodeWorkflowCLIJSON([entry])
        #expect(try decodeWorkflowMacroCatalog(from: direct) == [entry])

        let envelope = AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>
            .workflowMacroCatalog(command: "workflow macros", macros: [entry])
        let wrapped = try encodeWorkflowCLIJSON(envelope)
        #expect(try decodeWorkflowMacroCatalog(from: wrapped) == [entry])
    }

    @Test("Workflow CLI file writer creates parent directories")
    func workflowCLIFileWriterCreatesParentDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-CLIOutput-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("nested/result.json").path
        let data = Data("{}".utf8)

        try writeWorkflowCLIFile(data, to: path)

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == data)
    }
}

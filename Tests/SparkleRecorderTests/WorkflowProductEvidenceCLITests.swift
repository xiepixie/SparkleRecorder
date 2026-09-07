import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderTooling

@Suite("Workflow Product Evidence CLI Tests")
struct WorkflowProductEvidenceCLITests {
    @Test("Product evidence capability routes audit through one interface")
    func routesAuditThroughOneInterface() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-ProductEvidenceCLI-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let exitCode = try WorkflowProductEvidenceCLI.run(
            ["audit", "--directory", directory.path],
            wantsJSON: false
        )

        #expect(exitCode == 0)
    }

    @Test("Strict audit keeps its nonzero gate semantics")
    func strictAuditKeepsNonzeroGateSemantics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-ProductEvidenceCLI-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let exitCode = try WorkflowProductEvidenceCLI.run(
            ["audit", "--require-live", "--directory", directory.path],
            wantsJSON: false
        )

        #expect(exitCode == 1)
    }

    @Test("Unknown product evidence commands fail at the capability interface")
    func unknownCommandFailsAtCapabilityInterface() {
        do {
            _ = try WorkflowProductEvidenceCLI.run(["unknown-command"], wantsJSON: false)
            Issue.record("Expected unsupported command failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "unsupportedCommand")
            #expect(error.path == "unknown-command")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

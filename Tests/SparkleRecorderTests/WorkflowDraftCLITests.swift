import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Workflow Draft CLI Tests")
struct WorkflowDraftCLITests {
    @Test("Draft capability owns init and task editing through one interface")
    func draftCapabilityOwnsInitAndTaskEditing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-WorkflowDraftCLI-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let draftPath = directory.appendingPathComponent("draft.json").path

        #expect(try WorkflowDraftCLI.run(
            ["init", "--name", "CLI Draft", "--out", draftPath],
            wantsJSON: false
        ) == 0)

        #expect(try WorkflowDraftCLI.run(
            [
                "task", "add", draftPath,
                "--key", "pause",
                "--type", "delay",
                "--delay", "1.5",
                "--out", draftPath
            ],
            wantsJSON: false
        ) == 0)

        let data = try readWorkflowCLIFile(at: draftPath)
        let document = try decodeWorkflowCLIJSON(AutomationWorkflowDraftDocument.self, from: data)
        #expect(document.workflow.name == "CLI Draft")
        #expect(document.workflow.tasks.count == 1)
        #expect(document.workflow.tasks.first?.key == "pause")
        #expect(document.workflow.tasks.first?.type == "delay")
        #expect(document.workflow.tasks.first?.delaySeconds == 1.5)
    }

    @Test("Draft routing preserves nested command gate semantics")
    func nestedCommandGateSemanticsStayStable() {
        for arguments in [
            ["task", "add"],
            ["loop", "set"],
            ["schedule", "set"],
            ["condition", "set"],
            ["dependency", "add"]
        ] {
            do {
                _ = try WorkflowDraftCLI.run(arguments, wantsJSON: false)
                Issue.record("Expected unsupported command for \(arguments.joined(separator: " "))")
            } catch let error as WorkflowCLIError {
                #expect(error.code == "unsupportedCommand")
                #expect(error.message == "Unsupported workflow command 'draft \(arguments.joined(separator: " "))'.")
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Draft validation and simulation remain behind the capability interface")
    func validationAndSimulationStayBehindCapabilityInterface() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-WorkflowDraftCLI-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let draftPath = directory.appendingPathComponent("draft.json").path
        _ = try WorkflowDraftCLI.run(
            ["init", "--name", "Validation Draft", "--out", draftPath],
            wantsJSON: false
        )
        _ = try WorkflowDraftCLI.run(
            [
                "task", "add", draftPath,
                "--key", "pause",
                "--type", "delay",
                "--delay", "0.25",
                "--out", draftPath
            ],
            wantsJSON: false
        )

        #expect(try WorkflowDraftCLI.run(["validate", draftPath], wantsJSON: false) == 0)
        #expect(try WorkflowDraftCLI.run(
            ["simulate", draftPath, "--at", "2026-09-05T12:00:00Z"],
            wantsJSON: false
        ) == 0)
    }
}

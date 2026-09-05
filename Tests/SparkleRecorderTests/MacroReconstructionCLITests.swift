import Foundation
import Testing
@testable import SparkleRecorder
import SparkleRecorderCore

@Suite("Macro Reconstruction CLI Tests")
struct MacroReconstructionCLITests {
    @Test func parserRejectsUnattendedExecutionAndAmbiguousOptions() throws {
        for arguments in [["accept"], ["test"], ["success"], ["import", "--macro-id", "bad", "--candidate", "file"],
                          ["inspect", "--macro", "file", "--include-video"],
                          ["export", "--macro-id", UUID().uuidString, "--macro-id", UUID().uuidString]] {
            #expect(throws: MacroReconstructionCLIError.self) { try MacroReconstructionCLI.parse(arguments) }
        }
        let request = try MacroReconstructionCLI.parse(["inspect", "--macro", "/tmp/input.json", "--json"])
        #expect(request.command == "inspect" && request.macroPath == "/tmp/input.json")
    }

    @Test func inspectListsLiteralCandidateActionIDsWithoutLibraryAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = macro()
        let path = root.appendingPathComponent("source.json")
        try JSONEncoder().encode(source).write(to: path)
        let result = try await MacroReconstructionCLI.execute(["inspect", "--macro", path.path], appSupportURL: root)
        let expected = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: "candidate")
        #expect(result.actions?.map(\.actionID) == expected.map(\.id))
        #expect(result.actionRevision == "candidate")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("SparkleRecorder").path))
    }

    @Test func exportAndImportRetainAcceptedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MacroRepository(appSupportURL: root)
        let source = macro()
        try await repo.saveMetadata(source)
        try await repo.saveEvents(source.events, for: source.id)
        let output = root.appendingPathComponent("package")
        let exported = try await MacroReconstructionCLI.execute(
            ["export", "--macro-id", source.id.uuidString, "--output", output.path], appSupportURL: root)
        #expect(exported.outputPath == output.path)
        #expect(exported.packageReport?.visualEvidenceIncluded == false)
        let imported = try await MacroReconstructionCLI.execute(
            ["import", "--macro-id", source.id.uuidString, "--candidate", output.appendingPathComponent("candidate-template.json").path], appSupportURL: root)
        #expect(imported.candidateID != nil)
        #expect(imported.requiresAttention == false)
        #expect(try await repo.loadMacro(for: source.id) == source)
        let candidateID = try #require(imported.candidateID)
        await #expect(throws: MacroCandidateStoreError.testRequired) {
            try await repo.acceptCandidate(candidateID: candidateID, for: source.id)
        }
    }

    @Test func helpIsDiscoverableWithoutAccessingTheLibrary() async throws {
        for arguments in [[], ["--help"], ["help", "--json"], ["export", "--help"]] {
            let result = try await MacroReconstructionCLI.execute(arguments)
            #expect(result.command == "help")
            #expect(result.usage?.contains("reconstruction import") == true)
            #expect(result.summary.contains("workflow macros --json"))
            #expect(result.summary.contains("Refine"))
        }
        #expect(throws: MacroReconstructionCLIError.self) {
            try MacroReconstructionCLI.parse(["accept", "--help"])
        }
    }

    @Test func summariesGuideTheNextUserDecision() {
        let exported = MacroReconstructionCLIResult(command: "export", outputPath: "/tmp/package")
        #expect(exported.summary.contains("instructions.md"))
        let imported = MacroReconstructionCLIResult(command: "import", candidateID: UUID(), requiresAttention: true)
        #expect(imported.summary.contains("Refine"))
        #expect(imported.summary.contains("uncertainties"))
        #expect(imported.summary.contains("unchanged"))
    }

    private func macro() -> SavedMacro {
        SavedMacro(name: "CLI source", events: [RecordedEvent(kind: .mouseMoved, time: 0, x: 10, y: 20,
            keyCode: 0, flags: 0, mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)])
    }
}

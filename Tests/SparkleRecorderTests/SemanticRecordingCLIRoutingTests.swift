import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Semantic Recording CLI Routing Tests")
struct SemanticRecordingCLIRoutingTests {
    @Test("Recording capability keeps stable machine command names")
    func commandNamesStayStable() {
        #expect(SemanticRecordingCLI.commandName([]) == "recording")
        #expect(SemanticRecordingCLI.commandName(["show"]) == "recording.show")
        #expect(SemanticRecordingCLI.commandName(["frame", "show"]) == "recording.frame.show")
        #expect(SemanticRecordingCLI.commandName(["ocr", "search"]) == "recording.ocr.search")
        #expect(SemanticRecordingCLI.commandName(["visual", "search"]) == "recording.visual.search")
        #expect(SemanticRecordingCLI.commandName(["asset", "baseline"]) == "recording.asset.baseline")
        #expect(SemanticRecordingCLI.commandName(["suggest", "conditions"]) == "recording.suggest.conditions")
    }

    @Test("Fixture-backed recording commands route through one capability interface")
    func fixtureCommandsRouteThroughOneInterface() throws {
        #expect(try SemanticRecordingCLI.run(["list", "--fixture", "checkout"], wantsJSON: false) == 0)
        #expect(try SemanticRecordingCLI.run(["show", "checkout-demo", "--fixture", "checkout"], wantsJSON: false) == 0)
        #expect(try SemanticRecordingCLI.run(["readiness", "checkout-demo", "--fixture", "checkout"], wantsJSON: false) == 0)
        #expect(try SemanticRecordingCLI.run([
            "ocr", "search", "checkout-demo", "--fixture", "checkout", "--text", "checkout"
        ], wantsJSON: false) == 0)
        #expect(try SemanticRecordingCLI.run([
            "suggest", "conditions", "checkout-demo", "--fixture", "checkout"
        ], wantsJSON: false) == 0)
    }

    @Test("Recording routing preserves typed parser and unsupported-command errors")
    func routingPreservesStableErrors() {
        do {
            _ = try SemanticRecordingCLI.run(["unknown-command"], wantsJSON: false)
            Issue.record("Expected unsupported command failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "unsupportedCommand")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try SemanticRecordingCLI.run([
                "ocr", "search", "checkout-demo", "--fixture", "checkout",
                "--text", "checkout", "--match", "fuzzy"
            ], wantsJSON: false)
            Issue.record("Expected unsupported match mode failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "unsupportedMatchMode")
            #expect(error.path == "--match")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

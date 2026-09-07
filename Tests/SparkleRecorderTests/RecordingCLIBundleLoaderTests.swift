import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Recording CLI Bundle Loader Tests")
struct RecordingCLIBundleLoaderTests {
    @Test("Fixture loading has one source contract for strict and tolerant reads")
    func fixtureLoadingUsesSharedSourceContract() throws {
        let arguments = ["checkout-demo", "--fixture", "checkout"]

        let strict = try RecordingCLIBundleLoader.load(arguments)
        let tolerant = try RecordingCLIBundleLoader.loadTolerant(arguments)

        #expect(strict.requestedRecordingID == "checkout-demo")
        #expect(strict.fixture == "checkout")
        #expect(strict.sourceOption == nil)
        #expect(strict.bundleDirectory == nil)
        #expect(strict.bundle.id == SemanticRecordingFixture.recordingID)
        #expect(tolerant.requestedRecordingID == strict.requestedRecordingID)
        #expect(tolerant.fixture == strict.fixture)
        #expect(tolerant.bundle.id == strict.bundle.id)
    }

    @Test("Source parser rejects conflicting sources before touching storage")
    func sourceParserRejectsConflictingSources() {
        do {
            _ = try RecordingCLIBundleLoader.load([
                "checkout-demo",
                "--fixture", "checkout",
                "--recordings-root", "/tmp/recordings"
            ])
            Issue.record("Expected conflicting source failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "conflictingRecordingSource")
            #expect(error.path == "--recordings-root")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Command-specific options can be consumed without duplicating source parsing")
    func commandSpecificOptionsCanBeConsumed() throws {
        var capturedValue: String?
        let loaded = try RecordingCLIBundleLoader.load([
            "checkout-demo",
            "--fixture", "checkout",
            "--window", "4.5"
        ]) { token, index, arguments in
            guard token == "--window" else { return nil }
            capturedValue = arguments[index + 1]
            return 1
        }

        #expect(capturedValue == "4.5")
        #expect(loaded.bundle.id == SemanticRecordingFixture.recordingID)
    }

    @Test("Fixture validation remains explicit and stable")
    func fixtureValidationRemainsExplicitAndStable() {
        do {
            try RecordingCLIBundleLoader.validateFixture("unknown")
            Issue.record("Expected unsupported fixture failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "unsupportedFixture")
            #expect(error.path == "unknown")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Source option quoting is centralized")
    func sourceOptionQuotingIsCentralized() {
        let option = RecordingCLIBundleLoader.sourceOption(
            "--recordings-root",
            url: URL(fileURLWithPath: "/tmp/My Recordings", isDirectory: true)
        )

        #expect(option == " --recordings-root '/tmp/My Recordings'")
    }
}

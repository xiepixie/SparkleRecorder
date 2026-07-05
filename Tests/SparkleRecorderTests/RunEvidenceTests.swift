import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Run Evidence Tests")
struct RunEvidenceTests {
    @Test("Failure evidence creates a failed run report with step context")
    func failureEvidenceBuildsRunReport() {
        let macroID = UUID()
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let evidence = PlaybackFailureEvidence(
            macroID: macroID,
            runID: runID,
            startTime: startedAt,
            duration: 2.75,
            failedEventIndex: 4,
            errorMessage: "verifyText failed",
            bundleIdentifier: "com.example.Target",
            windowTitle: "Checkout"
        )

        let report = evidence.report

        #expect(evidence.macroID == macroID)
        #expect(report.runID == runID)
        #expect(report.startTime == startedAt)
        #expect(report.duration == 2.75)
        #expect(!report.isSuccess)
        #expect(report.failedEventIndex == 4)
        #expect(report.errorMessage == "verifyText failed")
    }

    @Test("Run evidence clamps negative durations")
    func evidenceClampsNegativeDurations() {
        let evidence = PlaybackFailureEvidence(
            macroID: UUID(),
            duration: -1,
            failedEventIndex: nil,
            errorMessage: "failed"
        )

        #expect(evidence.duration == 0)
        #expect(evidence.report.duration == 0)
    }
}

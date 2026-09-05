import Foundation
import Testing
@testable import SparkleRecorder
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

    @Test("Run evidence manifest binds evidence id, macro id, and run id")
    func manifestBindsRunEvidencePayload() {
        let macroID = UUID()
        let runID = UUID()
        let createdAt = Date(timeIntervalSince1970: 3_000)
        let manifest = RunEvidenceManifest(
            evidenceID: runID,
            macroID: macroID,
            runID: runID,
            screenshotFilename: "failure.png",
            createdAt: createdAt
        )

        #expect(manifest.schemaVersion == RunEvidenceManifest.currentSchemaVersion)
        #expect(manifest.evidenceID == runID)
        #expect(manifest.macroID == macroID)
        #expect(manifest.runID == runID)
        #expect(manifest.reportFilename == "report.json")
        #expect(manifest.screenshotFilename == "failure.png")
        #expect(manifest.createdAt == createdAt)
    }

    @Test("Evidence persistence distinguishes complete report-only and failed saves")
    func evidencePersistenceHealthReflectsStoredArtifacts() async throws {
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderEvidenceHealth-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let repository = MacroRepository(appSupportURL: appSupport)
        let macroID = UUID()

        let completeReport = RunReport(
            runID: UUID(),
            startTime: Date(timeIntervalSince1970: 10),
            duration: 1,
            isSuccess: true
        )
        let complete = await repository.saveRunEvidenceWithStatus(
            id: macroID,
            report: completeReport,
            screenshot: Data([0x01, 0x02])
        )

        let reportOnly = await repository.saveRunEvidenceWithStatus(
            id: macroID,
            report: RunReport(
                runID: UUID(),
                startTime: Date(timeIntervalSince1970: 20),
                duration: 1,
                isSuccess: false
            ),
            screenshot: nil
        )

        #expect(complete.health == .persisted)
        #expect(complete.hasReadableReport)
        #expect(reportOnly.health == .partial)
        #expect(reportOnly.report == .persisted)
        #expect(reportOnly.screenshot == .unavailable)

        let blockedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderEvidenceBlocked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blockedRoot) }
        try Data("not a directory".utf8).write(to: blockedRoot)
        let blockedRepository = MacroRepository(appSupportURL: blockedRoot)
        let failed = await blockedRepository.saveRunEvidenceWithStatus(
            id: macroID,
            report: completeReport,
            screenshot: Data([0x01])
        )

        #expect(failed.health == .failed)
        #expect(!failed.hasReadableReport)
        #expect(failed.failureMessage?.isEmpty == false)
    }
}

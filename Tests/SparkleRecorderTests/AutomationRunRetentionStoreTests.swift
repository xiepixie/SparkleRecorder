import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Run Retention Store Tests")
struct AutomationRunRetentionStoreTests {
    @Test("Preview and apply delete only expired run evidence and preserve result metadata")
    func previewAndApplyExpiredEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderRetention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 50_000_000)
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let oldEvidenceID = UUID()
        let latestEvidenceID = UUID()
        let oldRun = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            evidenceID: oldEvidenceID,
            completedAt: now.addingTimeInterval(-100 * day)
        )
        let latestRun = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            evidenceID: latestEvidenceID,
            completedAt: now
        )

        let oldURL = evidenceURL(root: root, macroID: macroID, evidenceID: oldEvidenceID)
        let latestURL = evidenceURL(root: root, macroID: macroID, evidenceID: latestEvidenceID)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestURL, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 8_192).write(to: oldURL.appendingPathComponent("failure.png"))
        try Data(repeating: 9, count: 4_096).write(to: latestURL.appendingPathComponent("failure.png"))

        let repositoryStore = AutomationInMemoryRepositoryStore(runHistory: [oldRun, latestRun])
        let repository = AutomationRepositoryClient.inMemory(store: repositoryStore)
        let store = AutomationRunRetentionStore(
            repository: repository,
            supportDirectory: root
        )

        let preview = try await store.preview(
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: 30,
                attentionEvidenceAgeDays: 90,
                metadataAgeDays: 365
            ),
            evaluatedAt: now
        )

        #expect(preview.artifactRunCount == 1)
        #expect(preview.estimatedByteCount >= 8_192)
        #expect(preview.plan.items.first?.runID == oldRun.id)

        let result = try await store.apply(preview)
        let storedRuns = try await repository.loadRunHistory()
        let storedOldRun = try #require(storedRuns.first { $0.id == oldRun.id })

        #expect(result.prunedArtifactRunCount == 1)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: latestURL.path))
        #expect(storedOldRun.outcome == oldRun.outcome)
        #expect(storedOldRun.evidenceID == nil)
        #expect(storedOldRun.artifactRetention?.status == .pruned)
        #expect(storedOldRun.artifactRetention?.originalEvidenceID == oldEvidenceID)
    }

    @Test("Storage inventory separates reports screenshots and other evidence")
    func storageInventorySeparatesArtifactClasses() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderUsage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let macroID = UUID()
        let evidenceID = UUID()
        let run = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: macroID,
            evidenceID: evidenceID,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        let directory = evidenceURL(root: root, macroID: macroID, evidenceID: evidenceID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: directory.appendingPathComponent("report.json"))
        try Data(repeating: 2, count: 200).write(to: directory.appendingPathComponent("failure.png"))
        try Data(repeating: 3, count: 300).write(to: directory.appendingPathComponent("manifest.json"))
        let orphanDirectory = evidenceURL(root: root, macroID: UUID(), evidenceID: UUID())
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 400).write(to: orphanDirectory.appendingPathComponent("report.json"))

        let repository = AutomationRepositoryClient.inMemory(
            store: AutomationInMemoryRepositoryStore(runHistory: [run])
        )
        let store = AutomationRunRetentionStore(repository: repository, supportDirectory: root)
        let usage = try await store.storageUsage()
        let execution = usage.breakdown(for: run.executionID)

        #expect(usage.breakdown.reportByteCount > 0)
        #expect(usage.breakdown.screenshotByteCount > 0)
        #expect(usage.breakdown.otherEvidenceByteCount > 0)
        #expect(usage.breakdown.reportByteCount > execution.reportByteCount)
        #expect(execution.screenshotByteCount == usage.breakdown.screenshotByteCount)
        #expect(usage.totalByteCount == usage.breakdown.evidenceByteCount)
    }

    @Test("Manual screenshot deletion frees screenshots and preserves report")
    func manualScreenshotDeletionPreservesReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderScreenshotDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let macroID = UUID()
        let evidenceID = UUID()
        var run = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: macroID,
            evidenceID: evidenceID,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        run.evidencePersistence = AutomationRunEvidencePersistence(
            evidenceID: evidenceID,
            report: .persisted,
            screenshot: .persisted,
            manifest: .persisted
        )
        let directory = evidenceURL(root: root, macroID: macroID, evidenceID: evidenceID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reportURL = directory.appendingPathComponent("report.json")
        let screenshotURL = directory.appendingPathComponent("failure.png")
        try Data(repeating: 1, count: 100).write(to: reportURL)
        try Data(repeating: 2, count: 200).write(to: screenshotURL)

        let repositoryStore = AutomationInMemoryRepositoryStore(runHistory: [run])
        let repository = AutomationRepositoryClient.inMemory(store: repositoryStore)
        let store = AutomationRunRetentionStore(repository: repository, supportDirectory: root)
        let preview = try await store.manualDeletionPreview(
            runIDs: [run.id],
            scope: .screenshots
        )
        let result = try await store.applyManualDeletion(preview)
        let stored = try #require(try await repository.loadRunHistory().first)

        #expect(preview.breakdown.reportByteCount > 0)
        #expect(preview.breakdown.screenshotByteCount > 0)
        #expect(result.freedByteCount == preview.breakdown.screenshotByteCount)
        #expect(FileManager.default.fileExists(atPath: reportURL.path))
        #expect(!FileManager.default.fileExists(atPath: screenshotURL.path))
        #expect(stored.evidenceID == evidenceID)
        #expect(stored.evidencePersistence?.health == .partial)
    }

    @Test("Manual history deletion removes terminal record and evidence")
    func manualHistoryDeletionRemovesRecordAndEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderHistoryDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let macroID = UUID()
        let evidenceID = UUID()
        let run = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: macroID,
            evidenceID: evidenceID,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        let directory = evidenceURL(root: root, macroID: macroID, evidenceID: evidenceID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: directory.appendingPathComponent("report.json"))

        let repository = AutomationRepositoryClient.inMemory(
            store: AutomationInMemoryRepositoryStore(runHistory: [run])
        )
        let store = AutomationRunRetentionStore(repository: repository, supportDirectory: root)
        let preview = try await store.manualDeletionPreview(runIDs: [run.id], scope: .history)
        _ = try await store.applyManualDeletion(preview)

        #expect(try await repository.loadRunHistory().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Manual deletion apply revalidates active runs")
    func manualDeletionApplyRevalidatesActiveRuns() async throws {
        let runID = UUID()
        let active = AutomationTaskRun(
            id: runID,
            workflowID: UUID(),
            taskID: UUID(),
            status: .running,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let store = AutomationRunRetentionStore(
            repository: .inMemory(store: AutomationInMemoryRepositoryStore(runHistory: [active])),
            supportDirectory: FileManager.default.temporaryDirectory
        )
        let forgedPlan = AutomationRunRetentionPlan(
            evaluatedAt: Date(timeIntervalSince1970: 20),
            scannedRunCount: 1,
            items: [AutomationRunRetentionPlanItem(
                runID: runID,
                workflowID: active.workflowID,
                macroID: nil,
                evidenceID: nil,
                activityAt: active.createdAt,
                artifactKinds: [],
                deleteMetadata: true
            )],
            protectedRunReasons: [:]
        )
        let preview = AutomationRunManualDeletionPreview(
            scope: .history,
            runIDs: [runID],
            plan: forgedPlan,
            breakdown: AutomationRunStorageBreakdown()
        )

        await #expect(throws: AutomationRunRetentionStoreError.activeRunsCannotBeDeleted) {
            try await store.applyManualDeletion(preview)
        }
    }

    private let day: TimeInterval = 24 * 60 * 60

    private func completedRun(
        workflowID: UUID,
        taskID: UUID,
        macroID: UUID,
        evidenceID: UUID,
        completedAt: Date
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            actualStartTime: completedAt.addingTimeInterval(-1),
            completedAt: completedAt,
            status: .completed,
            outcome: .succeeded(report: nil),
            evidenceID: evidenceID,
            createdAt: completedAt.addingTimeInterval(-2)
        )
    }

    private func evidenceURL(root: URL, macroID: UUID, evidenceID: UUID) -> URL {
        root
            .appendingPathComponent("Macros", isDirectory: true)
            .appendingPathComponent("\(macroID.uuidString).sparkrec", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(evidenceID.uuidString, isDirectory: true)
    }
}

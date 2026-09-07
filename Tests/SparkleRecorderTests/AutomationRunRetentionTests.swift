import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Run Retention Tests")
struct AutomationRunRetentionTests {
    @Test("Settings normalize zero as retention disabled")
    func settingsNormalizeDays() {
        let settings = AutomationRunRetentionSettings(
            successEvidenceAgeDays: 0,
            attentionEvidenceAgeDays: -1,
            metadataAgeDays: 90,
            maximumMetadataRunCount: 0
        )

        #expect(settings.successEvidenceAgeDays == nil)
        #expect(settings.attentionEvidenceAgeDays == nil)
        #expect(settings.metadataAgeDays == 90)
        #expect(settings.maximumMetadataRunCount == nil)
    }

    @Test("Scheduled cleanup runs initially and becomes eligible after one day")
    func scheduledCleanupDecisionUsesMinimumInterval() {
        let now = date(days: 20)
        let initial = AutomationRunScheduledRetentionCleanupPlanner.decision(
            lastRunAt: nil,
            evaluatedAt: now
        )
        let recent = AutomationRunScheduledRetentionCleanupPlanner.decision(
            lastRunAt: now.addingTimeInterval(-day + 1),
            evaluatedAt: now
        )
        let eligible = AutomationRunScheduledRetentionCleanupPlanner.decision(
            lastRunAt: now.addingTimeInterval(-day),
            evaluatedAt: now
        )

        #expect(initial.shouldRun)
        #expect(!recent.shouldRun)
        #expect(eligible.shouldRun)
    }

    @Test("Planner uses separate success and attention ages while protecting latest runs")
    func plannerSeparatesAgesAndProtectsLatest() throws {
        let now = date(days: 400)
        let workflowID = UUID()
        let taskID = UUID()
        let successMacroID = UUID()
        let failureMacroID = UUID()
        let oldSuccess = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: successMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-100 * day),
            outcome: .succeeded(report: nil)
        )
        let oldFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: failureMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-200 * day),
            outcome: .failed(report: nil)
        )
        let recentSuccess = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: successMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-2 * day),
            outcome: .succeeded(report: nil)
        )
        let recentFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: failureMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-day),
            outcome: .failed(report: nil)
        )

        let plan = AutomationRunRetentionPlanner.plan(
            runs: [oldSuccess, oldFailure, recentSuccess, recentFailure],
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: 30,
                attentionEvidenceAgeDays: 90,
                metadataAgeDays: 365
            ),
            evaluatedAt: now
        )

        #expect(Set(plan.items.map(\.runID)) == [oldSuccess.id, oldFailure.id])
        #expect(plan.items.allSatisfy { $0.artifactKinds == [.macroRunEvidence] })
        #expect(plan.items.allSatisfy { !$0.deleteMetadata })
        #expect(plan.protectedRunReasons[recentFailure.id]?.contains(.latestWorkflowExecution) == true)
        #expect(plan.protectedRunReasons[recentFailure.id]?.contains(.latestWorkflowFailure) == true)
        #expect(plan.protectedRunReasons[recentSuccess.id]?.contains(.latestMacroEvidence) == true)
    }

    @Test("Attention outcomes use the longer evidence window, not the success window")
    func plannerUsesAttentionWindowForPermissionFailures() {
        let now = date(days: 400)
        let workflowID = UUID()
        let taskID = UUID()
        let successMacroID = UUID()
        let attentionMacroID = UUID()
        let oldSuccess = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: successMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-60 * day),
            outcome: .succeeded(report: nil)
        )
        let oldPermissionFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: attentionMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-60 * day),
            outcome: .permissionDenied(permission: .accessibility, message: "Permission required")
        )
        let recentFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: attentionMacroID,
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-day),
            outcome: .failed(report: nil)
        )
        let latestSuccess = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: successMacroID,
            evidenceID: UUID(),
            completedAt: now,
            outcome: .succeeded(report: nil)
        )

        let plan = AutomationRunRetentionPlanner.plan(
            runs: [oldSuccess, oldPermissionFailure, recentFailure, latestSuccess],
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: 30,
                attentionEvidenceAgeDays: 90,
                metadataAgeDays: 365
            ),
            evaluatedAt: now
        )

        #expect(plan.items.contains { $0.runID == oldSuccess.id })
        #expect(!plan.items.contains { $0.runID == oldPermissionFailure.id })
    }

    @Test("Active checkpoints are always protected")
    func plannerProtectsActiveRun() {
        let now = date(days: 500)
        var active = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: UUID(),
            createdAt: now.addingTimeInterval(-400 * day)
        )
        active.evidenceID = UUID()

        let plan = AutomationRunRetentionPlanner.plan(
            runs: [active],
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: 1,
                attentionEvidenceAgeDays: 1,
                metadataAgeDays: 1
            ),
            evaluatedAt: now
        )

        #expect(plan.items.isEmpty)
        #expect(plan.protectedRunReasons[active.id] == [.active, .latestWorkflowExecution, .latestMacroEvidence])
    }

    @Test("Two phase application preserves explanation and removes artifact bindings")
    func twoPhaseApplicationPrunesArtifacts() throws {
        let now = date(days: 500)
        let workflowID = UUID()
        let taskID = UUID()
        let macroID = UUID()
        let evidenceID = UUID()
        var oldRun = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            evidenceID: evidenceID,
            completedAt: now.addingTimeInterval(-100 * day),
            outcome: .failed(report: nil)
        )
        oldRun.conditionEvidence = conditionEvidence(for: oldRun, evaluatedAt: oldRun.completedAt!)
        let latestRun = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            evidenceID: UUID(),
            completedAt: now,
            outcome: .succeeded(report: nil)
        )
        let latestFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: UUID(),
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-day),
            outcome: .failed(report: nil)
        )
        let plan = AutomationRunRetentionPlanner.plan(
            runs: [oldRun, latestRun, latestFailure],
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: 30,
                attentionEvidenceAgeDays: 90,
                metadataAgeDays: 365
            ),
            evaluatedAt: now
        )
        let item = try #require(plan.items.first { $0.runID == oldRun.id })
        #expect(item.artifactKinds == [.macroRunEvidence, .conditionEvidence])

        let pendingRuns = AutomationRunRetentionPlanner.markPending(
            runs: [oldRun, latestRun, latestFailure],
            plan: plan
        )
        let pending = try #require(pendingRuns.first { $0.id == oldRun.id })
        #expect(pending.artifactRetention?.status == .pendingDeletion)
        #expect(pending.artifactRetention?.originalEvidenceID == evidenceID)
        #expect(pending.evidenceID == evidenceID)

        let appliedRuns = AutomationRunRetentionPlanner.markApplied(
            runs: pendingRuns,
            plan: plan,
            deletedRelativePathsByRunID: [oldRun.id: ["Macros/run", "AutomationEvidence/run"]]
        )
        let pruned = try #require(appliedRuns.first { $0.id == oldRun.id })
        #expect(pruned.outcome == .failed(report: nil))
        #expect(pruned.evidenceID == nil)
        #expect(pruned.conditionEvidence?.artifacts.isEmpty == true)
        #expect(pruned.artifactRetention?.status == .pruned)
        #expect(pruned.artifactRetention?.deletedRelativePaths == ["Macros/run", "AutomationEvidence/run"])
    }

    @Test("Ancient metadata is removed only when a newer execution is protected")
    func plannerRemovesAncientMetadata() {
        let now = date(days: 800)
        let workflowID = UUID()
        let taskID = UUID()
        let ancient = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            completedAt: now.addingTimeInterval(-500 * day),
            outcome: .succeeded(report: nil)
        )
        let latest = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            completedAt: now,
            outcome: .succeeded(report: nil)
        )
        let plan = AutomationRunRetentionPlanner.plan(
            runs: [ancient, latest],
            settings: AutomationRunRetentionSettings(metadataAgeDays: 365),
            evaluatedAt: now
        )
        let applied = AutomationRunRetentionPlanner.markApplied(
            runs: [ancient, latest],
            plan: plan,
            deletedRelativePathsByRunID: [:]
        )

        #expect(plan.items.first { $0.runID == ancient.id }?.deleteMetadata == true)
        #expect(applied.map(\.id) == [latest.id])
    }

    @Test("Metadata count cap removes oldest eligible runs and preserves protected runs")
    func plannerCapsMetadataCount() {
        let now = date(days: 100)
        let workflowID = UUID()
        let taskID = UUID()
        let oldRuns = (1...3).map { offset in
            completedRun(
                workflowID: workflowID,
                taskID: taskID,
                completedAt: now.addingTimeInterval(TimeInterval(-10 + offset)),
                outcome: .succeeded(report: nil)
            )
        }
        let latestFailure = completedRun(
            workflowID: workflowID,
            taskID: taskID,
            completedAt: now.addingTimeInterval(-2),
            outcome: .failed(report: nil)
        )
        var active = AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: now
        )
        active.status = .running
        let runs = oldRuns + [latestFailure, active]

        let plan = AutomationRunRetentionPlanner.plan(
            runs: runs,
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: nil,
                attentionEvidenceAgeDays: nil,
                metadataAgeDays: nil,
                maximumMetadataRunCount: 3
            ),
            evaluatedAt: now
        )
        let applied = AutomationRunRetentionPlanner.markApplied(
            runs: runs,
            plan: plan,
            deletedRelativePathsByRunID: [:]
        )

        #expect(Set(plan.items.filter(\.deleteMetadata).map(\.runID)) == Set(oldRuns.prefix(2).map(\.id)))
        #expect(applied.count == 3)
        #expect(applied.contains { $0.id == latestFailure.id })
        #expect(applied.contains { $0.id == active.id })
    }

    @Test("Pending deletion resumes even if the run later becomes the latest evidence")
    func pendingDeletionResumes() {
        let now = date(days: 500)
        var pending = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: UUID(),
            evidenceID: UUID(),
            completedAt: now.addingTimeInterval(-100 * day),
            outcome: .succeeded(report: nil)
        )
        pending.artifactRetention = AutomationRunArtifactRetention(
            status: .pendingDeletion,
            requestedAt: now.addingTimeInterval(-day),
            originalEvidenceID: pending.evidenceID
        )

        let plan = AutomationRunRetentionPlanner.plan(
            runs: [pending],
            settings: AutomationRunRetentionSettings(
                successEvidenceAgeDays: nil,
                attentionEvidenceAgeDays: nil,
                metadataAgeDays: nil
            ),
            evaluatedAt: now
        )

        #expect(plan.items.map(\.runID) == [pending.id])
        #expect(plan.items.first?.artifactKinds == [.macroRunEvidence])
    }

    @Test("Manual deletion rejects active runs at the core boundary")
    func manualDeletionRejectsActiveRuns() {
        let active = AutomationTaskRun(
            workflowID: UUID(),
            taskID: UUID(),
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        #expect(throws: AutomationRunManualDeletionValidationError.activeRuns([active.id])) {
            try AutomationRunManualDeletionPlanner.plan(
                runs: [active],
                runIDs: [active.id],
                scope: .history
            )
        }
    }

    @Test("Screenshot deletion keeps report and evidence binding durable")
    func screenshotDeletionKeepsReportBinding() throws {
        let evidenceID = UUID()
        var run = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: UUID(),
            evidenceID: evidenceID,
            completedAt: Date(timeIntervalSince1970: 10),
            outcome: .succeeded(report: nil)
        )
        run.evidencePersistence = AutomationRunEvidencePersistence(
            evidenceID: evidenceID,
            report: .persisted,
            screenshot: .persisted,
            manifest: .persisted
        )

        let updated = try AutomationRunManualDeletionPlanner.markScreenshotsDeleted(
            runs: [run],
            runIDs: [run.id]
        )
        let stored = try #require(updated.first)

        #expect(stored.evidenceID == evidenceID)
        #expect(stored.evidencePersistence?.report == .persisted)
        #expect(stored.evidencePersistence?.screenshot == .unavailable)
        #expect(stored.evidencePersistence?.health == .partial)
    }

    @Test("Manual history deletion includes protected latest evidence")
    func manualHistoryDeletionCanRemoveLatestTerminalRun() throws {
        let run = completedRun(
            workflowID: UUID(),
            taskID: UUID(),
            macroID: UUID(),
            evidenceID: UUID(),
            completedAt: Date(timeIntervalSince1970: 10),
            outcome: .succeeded(report: nil)
        )

        let plan = try AutomationRunManualDeletionPlanner.plan(
            runs: [run],
            runIDs: [run.id],
            scope: .history
        )

        #expect(plan.items.first?.deleteMetadata == true)
        #expect(plan.items.first?.artifactKinds == [.macroRunEvidence])
        #expect(plan.protectedRunReasons.isEmpty)
    }

    private let day: TimeInterval = 24 * 60 * 60

    private func date(days: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(days) * day)
    }

    private func completedRun(
        workflowID: UUID,
        taskID: UUID,
        macroID: UUID? = nil,
        evidenceID: UUID? = nil,
        completedAt: Date,
        outcome: AutomationOutcome
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            actualStartTime: completedAt.addingTimeInterval(-1),
            completedAt: completedAt,
            status: .completed,
            outcome: outcome,
            evidenceID: evidenceID,
            createdAt: completedAt.addingTimeInterval(-2)
        )
    }

    private func conditionEvidence(
        for run: AutomationTaskRun,
        evaluatedAt: Date
    ) -> AutomationConditionEvaluationEvidence {
        AutomationConditionEvaluationEvidence(
            runID: run.id,
            workflowID: run.workflowID,
            taskID: run.taskID,
            conditionID: UUID(),
            kind: .imageAppeared,
            outcome: run.outcome ?? .conditionNotMatched,
            evaluatedAt: evaluatedAt,
            targetDescription: "Button",
            observedSummary: "Not visible",
            artifacts: [AutomationConditionDiagnosticArtifact(
                id: "sample",
                title: "Sample",
                kind: .displaySampleImage,
                relativePath: "AutomationEvidence/\(run.id.uuidString)/condition-last-sample.png",
                createdAt: evaluatedAt
            )]
        )
    }
}

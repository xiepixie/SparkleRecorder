import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Run Center Projection Tests")
struct AutomationRunCenterProjectionTests {
    @Test("Projection groups attempts by execution and sorts latest activity first")
    func groupsAndSortsExecutions() throws {
        let workflowID = UUID()
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let olderExecutionID = UUID()
        let newerExecutionID = UUID()
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Nightly export",
            tasks: [
                AutomationTask(id: firstTaskID, name: "Open report", kind: .delay(1)),
                AutomationTask(id: secondTaskID, name: "Export report", kind: .delay(1))
            ]
        )
        let state = AutomationRunState(
            workflows: [workflow],
            runs: [
                completedRun(
                    executionID: olderExecutionID,
                    workflowID: workflowID,
                    taskID: firstTaskID,
                    createdAt: date(100),
                    completedAt: date(110),
                    outcome: .succeeded(report: nil)
                ),
                completedRun(
                    executionID: newerExecutionID,
                    workflowID: workflowID,
                    taskID: firstTaskID,
                    createdAt: date(200),
                    completedAt: date(210),
                    outcome: .succeeded(report: nil)
                ),
                completedRun(
                    executionID: newerExecutionID,
                    workflowID: workflowID,
                    taskID: secondTaskID,
                    createdAt: date(211),
                    completedAt: date(220),
                    outcome: .succeeded(report: nil)
                )
            ],
            now: date(300)
        )

        let projection = AutomationRunCenterProjection.make(state: state)

        #expect(projection.executions.map { $0.executionID } == [newerExecutionID, olderExecutionID])
        #expect(projection.executions[0].workflowName == "Nightly export")
        #expect(projection.executions[0].taskRunCount == 2)
        #expect(projection.executions[0].completedRunCount == 2)
        #expect(projection.executions[0].attemptCount == 2)
        #expect(projection.summary.totalCount == 2)
        #expect(projection.summary.succeededCount == 2)
    }

    @Test("Active run takes precedence over a failed attempt in the same execution")
    func activeRunHasStatusPrecedence() throws {
        let fixture = workflowFixture()
        let executionID = UUID()
        let state = AutomationRunState(
            workflows: [fixture.workflow],
            runs: [
                completedRun(
                    executionID: executionID,
                    workflowID: fixture.workflow.id,
                    taskID: fixture.task.id,
                    createdAt: date(100),
                    completedAt: date(110),
                    outcome: .failed(report: nil)
                ),
                AutomationTaskRun(
                    executionID: executionID,
                    workflowID: fixture.workflow.id,
                    taskID: fixture.task.id,
                    actualStartTime: date(120),
                    status: .running,
                    createdAt: date(115),
                    attempt: 2
                )
            ],
            now: date(130)
        )

        let execution = try #require(AutomationRunCenterProjection.make(state: state).executions.first)

        #expect(execution.status == .running)
        #expect(execution.hasActiveRun)
        #expect(execution.recommendedAction == .waitOrCancel)
    }

    @Test("Failure focus exposes task attempt event and evidence action")
    func failureFocusAndAction() throws {
        let macroID = UUID()
        let evidenceID = UUID()
        let fixture = workflowFixture(macroID: macroID)
        let report = RunReport(
            runID: evidenceID,
            startTime: date(100),
            duration: 4,
            isSuccess: false,
            failedEventIndex: 6,
            errorMessage: "Target text was not found"
        )
        let state = AutomationRunState(
            workflows: [fixture.workflow],
            runs: [completedRun(
                executionID: UUID(),
                workflowID: fixture.workflow.id,
                taskID: fixture.task.id,
                macroID: macroID,
                createdAt: date(100),
                completedAt: date(104),
                outcome: .failed(report: report),
                evidenceID: evidenceID,
                attempt: 2
            )],
            now: date(110)
        )

        let projection = AutomationRunCenterProjection.make(state: state)
        let execution = try #require(projection.executions.first)
        let focus = try #require(execution.failureFocus)

        #expect(execution.status == .needsAttention)
        #expect(focus.taskName == "Export report")
        #expect(focus.attempt == 2)
        #expect(focus.failedEventIndex == 6)
        #expect(focus.evidenceID == evidenceID)
        #expect(execution.recommendedAction == .inspectFailedEvent(
            macroID: macroID,
            eventIndex: 6,
            evidenceID: evidenceID
        ))
    }

    @Test("Filters use execution status rather than individual task status")
    func filtersExecutionStatus() {
        let fixture = workflowFixture()
        let outcomes: [AutomationOutcome] = [
            .succeeded(report: nil),
            .failed(report: nil),
            .cancelled(reason: "Stopped")
        ]
        let runs = outcomes.enumerated().map { index, outcome in
            completedRun(
                executionID: UUID(),
                workflowID: fixture.workflow.id,
                taskID: fixture.task.id,
                createdAt: date(TimeInterval(index * 10)),
                completedAt: date(TimeInterval(index * 10 + 1)),
                outcome: outcome
            )
        } + [AutomationTaskRun(
            executionID: UUID(),
            workflowID: fixture.workflow.id,
            taskID: fixture.task.id,
            status: .queued,
            createdAt: date(100)
        )]
        let projection = AutomationRunCenterProjection.make(state: AutomationRunState(
            workflows: [fixture.workflow],
            runs: runs,
            now: date(110)
        ))

        #expect(projection.executions(matching: .all).count == 4)
        #expect(projection.executions(matching: .needsAttention).count == 1)
        #expect(projection.executions(matching: .running).count == 1)
        #expect(projection.executions(matching: .succeeded).count == 1)
        #expect(projection.summary.totalCount == 4)
    }

    @Test("Permission and missing macro outcomes produce concrete recovery actions")
    func specializedRecoveryActions() throws {
        let fixture = workflowFixture()
        let missingMacroID = UUID()
        let state = AutomationRunState(
            workflows: [fixture.workflow],
            runs: [
                completedRun(
                    executionID: UUID(),
                    workflowID: fixture.workflow.id,
                    taskID: fixture.task.id,
                    createdAt: date(100),
                    completedAt: date(101),
                    outcome: .permissionDenied(permission: .accessibility, message: "Required")
                ),
                completedRun(
                    executionID: UUID(),
                    workflowID: fixture.workflow.id,
                    taskID: fixture.task.id,
                    createdAt: date(200),
                    completedAt: date(201),
                    outcome: .missingMacro(macroID: missingMacroID)
                )
            ],
            now: date(210)
        )

        let actions = AutomationRunCenterProjection.make(state: state).executions.map(\.recommendedAction)

        #expect(actions.contains(.grantPermission(.accessibility)))
        #expect(actions.contains(.restoreMacro(missingMacroID)))
    }

    @Test("Persistence issue overrides a successful outcome and recommends storage repair")
    func persistenceIssueNeedsAttention() throws {
        let fixture = workflowFixture()
        let run = completedRun(
            executionID: UUID(),
            workflowID: fixture.workflow.id,
            taskID: fixture.task.id,
            createdAt: date(100),
            completedAt: date(101),
            outcome: .succeeded(report: nil)
        )
        let issue = AutomationPersistenceIssue(
            operation: .runCheckpoint,
            runID: run.id,
            message: "disk full",
            failedAt: date(101)
        )
        let state = AutomationRunState(
            workflows: [fixture.workflow],
            runs: [run],
            now: date(102),
            persistenceIssue: issue
        )

        let projection = AutomationRunCenterProjection.make(state: state)
        let execution = try #require(projection.executions.first)

        #expect(projection.persistenceIssue == issue)
        #expect(execution.status == .needsAttention)
        #expect(execution.recommendedAction == .repairStorage)
        #expect(projection.summary.needsAttentionCount == 1)
        #expect(projection.summary.succeededCount == 0)
    }

    @Test("Evidence availability requires a persisted readable report")
    func evidenceAvailabilityUsesPersistenceHealth() throws {
        let fixture = workflowFixture(macroID: UUID())
        let evidenceID = UUID()
        var unverified = completedRun(
            executionID: UUID(),
            workflowID: fixture.workflow.id,
            taskID: fixture.task.id,
            macroID: fixture.task.kind.macroID,
            createdAt: date(100),
            completedAt: date(101),
            outcome: .failed(report: nil),
            evidenceID: evidenceID
        )
        let unverifiedProjection = try #require(AutomationRunCenterProjection.make(
            state: AutomationRunState(workflows: [fixture.workflow], runs: [unverified])
        ).executions.first)

        #expect(!unverifiedProjection.hasEvidence)

        unverified.evidencePersistence = AutomationRunEvidencePersistence(
            evidenceID: evidenceID,
            report: .persisted,
            screenshot: .unavailable,
            manifest: .persisted
        )
        let partialProjection = try #require(AutomationRunCenterProjection.make(
            state: AutomationRunState(workflows: [fixture.workflow], runs: [unverified])
        ).executions.first)

        #expect(partialProjection.hasEvidence)
    }

    @Test("Projection handles ten thousand independent executions")
    func projectsLargeRunHistory() {
        let fixture = workflowFixture()
        let runs = (0..<10_000).map { index in
            completedRun(
                executionID: UUID(),
                workflowID: fixture.workflow.id,
                taskID: fixture.task.id,
                createdAt: date(TimeInterval(index * 2)),
                completedAt: date(TimeInterval(index * 2 + 1)),
                outcome: .succeeded(report: nil)
            )
        }

        let projection = AutomationRunCenterProjection.make(state: AutomationRunState(
            workflows: [fixture.workflow],
            runs: runs,
            now: date(20_001)
        ))

        #expect(projection.executions.count == 10_000)
        #expect(projection.summary.succeededCount == 10_000)
        #expect(projection.executions.first?.latestActivityAt == date(19_999))
        #expect(projection.executions.last?.latestActivityAt == date(1))
    }

    @Test("Startup interruption is attention rather than an ordinary cancellation")
    func interruptionNeedsAttention() throws {
        let fixture = workflowFixture()
        let detectedAt = date(120)
        var run = completedRun(
            executionID: UUID(),
            workflowID: fixture.workflow.id,
            taskID: fixture.task.id,
            createdAt: date(100),
            completedAt: detectedAt,
            outcome: .cancelled(reason: "Application closed")
        )
        run.interruption = AutomationRunInterruption(
            previousStatus: .running,
            detectedAt: detectedAt,
            reason: "Application closed"
        )

        let execution = try #require(AutomationRunCenterProjection.make(state: AutomationRunState(
            workflows: [fixture.workflow],
            runs: [run],
            now: detectedAt
        )).executions.first)

        #expect(execution.status == .needsAttention)
        #expect(execution.failureFocus?.runID == run.id)
        #expect(execution.recommendedAction == .reviewCancellation)
    }

    private func workflowFixture(macroID: UUID? = nil) -> (workflow: AutomationWorkflow, task: AutomationTask) {
        let task: AutomationTask
        if let macroID {
            task = AutomationTask(name: "Export report", kind: .macro(macroID: macroID))
        } else {
            task = AutomationTask(name: "Export report", kind: .delay(1))
        }
        return (
            AutomationWorkflow(name: "Nightly export", tasks: [task]),
            task
        )
    }

    private func completedRun(
        executionID: UUID,
        workflowID: UUID,
        taskID: UUID,
        macroID: UUID? = nil,
        createdAt: Date,
        completedAt: Date,
        outcome: AutomationOutcome,
        evidenceID: UUID? = nil,
        attempt: Int = 1
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: taskID,
            macroID: macroID,
            actualStartTime: createdAt,
            completedAt: completedAt,
            status: .completed,
            outcome: outcome,
            evidenceID: evidenceID,
            createdAt: createdAt,
            attempt: attempt
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

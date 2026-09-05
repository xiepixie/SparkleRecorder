import Foundation

public enum AutomationRunCenterFilter: String, CaseIterable, Codable, Equatable, Sendable {
    case all
    case needsAttention
    case running
    case succeeded
}

public enum AutomationExecutionDisplayStatus: String, Codable, Equatable, Sendable {
    case running
    case needsAttention
    case cancelled
    case succeeded
}

public enum AutomationRunRecommendedAction: Codable, Equatable, Sendable {
    case waitOrCancel
    case grantPermission(AutomationPermission)
    case restoreMacro(UUID)
    case inspectFailedEvent(macroID: UUID?, eventIndex: Int, evidenceID: UUID?)
    case inspectEvidence(UUID)
    case inspectTargetApplication
    case adjustTimeout
    case adjustResourcePolicy
    case retryExecution
    case reviewCancellation
    case repairStorage
    case none
}

public struct AutomationRunFailureFocus: Codable, Equatable, Sendable {
    public var runID: UUID
    public var taskID: UUID
    public var taskName: String
    public var macroID: UUID?
    public var attempt: Int
    public var failedEventIndex: Int?
    public var evidenceID: UUID?
    public var outcome: AutomationOutcome

    public init(
        runID: UUID,
        taskID: UUID,
        taskName: String,
        macroID: UUID?,
        attempt: Int,
        failedEventIndex: Int?,
        evidenceID: UUID?,
        outcome: AutomationOutcome
    ) {
        self.runID = runID
        self.taskID = taskID
        self.taskName = taskName
        self.macroID = macroID
        self.attempt = attempt
        self.failedEventIndex = failedEventIndex
        self.evidenceID = evidenceID
        self.outcome = outcome
    }
}

public struct AutomationExecutionProjection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { executionID }

    public var executionID: UUID
    public var workflowID: UUID
    public var workflowName: String
    public var status: AutomationExecutionDisplayStatus
    public var createdAt: Date
    public var latestActivityAt: Date
    public var taskRunCount: Int
    public var completedRunCount: Int
    public var attemptCount: Int
    public var hasEvidence: Bool
    public var hasActiveRun: Bool
    public var failureFocus: AutomationRunFailureFocus?
    public var recommendedAction: AutomationRunRecommendedAction
    public var runs: [AutomationTaskRun]

    public init(
        executionID: UUID,
        workflowID: UUID,
        workflowName: String,
        status: AutomationExecutionDisplayStatus,
        createdAt: Date,
        latestActivityAt: Date,
        taskRunCount: Int,
        completedRunCount: Int,
        attemptCount: Int,
        hasEvidence: Bool,
        hasActiveRun: Bool,
        failureFocus: AutomationRunFailureFocus?,
        recommendedAction: AutomationRunRecommendedAction,
        runs: [AutomationTaskRun]
    ) {
        self.executionID = executionID
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.status = status
        self.createdAt = createdAt
        self.latestActivityAt = latestActivityAt
        self.taskRunCount = taskRunCount
        self.completedRunCount = completedRunCount
        self.attemptCount = attemptCount
        self.hasEvidence = hasEvidence
        self.hasActiveRun = hasActiveRun
        self.failureFocus = failureFocus
        self.recommendedAction = recommendedAction
        self.runs = runs
    }
}

public struct AutomationRunCenterSummary: Codable, Equatable, Sendable {
    public var runningCount: Int
    public var needsAttentionCount: Int
    public var succeededCount: Int
    public var totalCount: Int

    public init(
        runningCount: Int = 0,
        needsAttentionCount: Int = 0,
        succeededCount: Int = 0,
        totalCount: Int = 0
    ) {
        self.runningCount = max(0, runningCount)
        self.needsAttentionCount = max(0, needsAttentionCount)
        self.succeededCount = max(0, succeededCount)
        self.totalCount = max(0, totalCount)
    }
}

public struct AutomationRunCenterProjection: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var summary: AutomationRunCenterSummary
    public var executions: [AutomationExecutionProjection]
    public var persistenceIssue: AutomationPersistenceIssue?

    public init(
        generatedAt: Date,
        summary: AutomationRunCenterSummary,
        executions: [AutomationExecutionProjection],
        persistenceIssue: AutomationPersistenceIssue? = nil
    ) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.executions = executions
        self.persistenceIssue = persistenceIssue
    }

    public func executions(matching filter: AutomationRunCenterFilter) -> [AutomationExecutionProjection] {
        switch filter {
        case .all:
            return executions
        case .needsAttention:
            return executions.filter { $0.status == .needsAttention }
        case .running:
            return executions.filter { $0.status == .running }
        case .succeeded:
            return executions.filter { $0.status == .succeeded }
        }
    }

    public static func make(
        state: AutomationRunState,
        generatedAt: Date? = nil
    ) -> AutomationRunCenterProjection {
        let workflowByID = Dictionary(uniqueKeysWithValues: state.workflows.map { ($0.id, $0) })
        let groupedRuns = Dictionary(grouping: state.runs, by: \AutomationTaskRun.executionID)
        let executions = groupedRuns.map { executionID, runs in
            makeExecution(
                executionID: executionID,
                runs: runs,
                workflow: workflowByID[runs[0].workflowID],
                persistenceIssue: state.persistenceIssue?.runID.map { runID in
                    runs.contains { $0.id == runID } ? state.persistenceIssue : nil
                } ?? nil
            )
        }
        .sorted { left, right in
            if left.latestActivityAt != right.latestActivityAt {
                return left.latestActivityAt > right.latestActivityAt
            }
            return left.executionID.uuidString < right.executionID.uuidString
        }

        return AutomationRunCenterProjection(
            generatedAt: generatedAt ?? state.now ?? executions.first?.latestActivityAt ?? stateFallbackDate,
            summary: AutomationRunCenterSummary(
                runningCount: executions.count { $0.status == .running },
                needsAttentionCount: executions.count { $0.status == .needsAttention },
                succeededCount: executions.count { $0.status == .succeeded },
                totalCount: executions.count
            ),
            executions: executions,
            persistenceIssue: state.persistenceIssue
        )
    }

    private static func makeExecution(
        executionID: UUID,
        runs: [AutomationTaskRun],
        workflow: AutomationWorkflow?,
        persistenceIssue: AutomationPersistenceIssue?
    ) -> AutomationExecutionProjection {
        let sortedRuns = runs.sorted(by: runSort)
        let status = persistenceIssue == nil ? executionStatus(for: sortedRuns) : .needsAttention
        let failureRun = sortedRuns.first { run in
            isActionableFailure(run)
        }
        let failureFocus = failureRun.flatMap { run -> AutomationRunFailureFocus? in
            guard let outcome = run.outcome else { return nil }
            let taskName = workflow?.task(id: run.taskID)?.name ?? "Unavailable task"
            return AutomationRunFailureFocus(
                runID: run.id,
                taskID: run.taskID,
                taskName: taskName,
                macroID: run.macroID ?? workflow?.task(id: run.taskID)?.kind.macroID,
                attempt: run.attempt,
                failedEventIndex: failedEventIndex(for: outcome),
                evidenceID: run.evidenceID,
                outcome: outcome
            )
        }

        return AutomationExecutionProjection(
            executionID: executionID,
            workflowID: sortedRuns[0].workflowID,
            workflowName: workflow?.name ?? "Unavailable workflow",
            status: status,
            createdAt: sortedRuns.map(\.createdAt).min() ?? stateFallbackDate,
            latestActivityAt: sortedRuns.map(activityDate).max() ?? stateFallbackDate,
            taskRunCount: Set(sortedRuns.map(\.taskID)).count,
            completedRunCount: sortedRuns.count(where: \.isTerminal),
            attemptCount: sortedRuns.count,
            hasEvidence: sortedRuns.contains {
                $0.artifactRetention?.status != .pruned
                    && ($0.evidencePersistence?.hasReadableReport == true
                        || $0.conditionEvidence?.artifacts.isEmpty == false)
            },
            hasActiveRun: sortedRuns.contains { !$0.isTerminal },
            failureFocus: failureFocus,
            recommendedAction: recommendedAction(
                status: status,
                failureFocus: failureFocus,
                runs: sortedRuns,
                persistenceIssue: persistenceIssue
            ),
            runs: sortedRuns
        )
    }

    private static let stateFallbackDate = Date(timeIntervalSince1970: 0)

    private static func runSort(_ left: AutomationTaskRun, _ right: AutomationTaskRun) -> Bool {
        let leftDate = left.actualStartTime ?? left.earliestStartTime ?? left.scheduledStartTime ?? left.createdAt
        let rightDate = right.actualStartTime ?? right.earliestStartTime ?? right.scheduledStartTime ?? right.createdAt
        if leftDate != rightDate { return leftDate < rightDate }
        if left.attempt != right.attempt { return left.attempt < right.attempt }
        return left.id.uuidString < right.id.uuidString
    }

    private static func activityDate(_ run: AutomationTaskRun) -> Date {
        run.completedAt ?? run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }

    private static func executionStatus(for runs: [AutomationTaskRun]) -> AutomationExecutionDisplayStatus {
        if runs.contains(where: { !$0.isTerminal }) {
            return .running
        }
        if runs.contains(where: isActionableFailure) {
            return .needsAttention
        }
        if runs.contains(where: { run in
            guard case .cancelled = run.outcome else { return false }
            return true
        }) {
            return .cancelled
        }
        return .succeeded
    }

    private static func isActionableFailure(_ outcome: AutomationOutcome) -> Bool {
        switch outcome {
        case .failed, .timedOut, .resourceConflict, .permissionDenied, .missingMacro, .rejected:
            return true
        case .succeeded, .cancelled, .conditionMatched, .conditionNotMatched:
            return false
        }
    }

    private static func isActionableFailure(_ run: AutomationTaskRun) -> Bool {
        if run.interruption != nil { return true }
        return run.outcome.map(isActionableFailure) == true
    }

    private static func failedEventIndex(for outcome: AutomationOutcome) -> Int? {
        guard case .failed(let report) = outcome else { return nil }
        return report?.failedEventIndex
    }

    private static func recommendedAction(
        status: AutomationExecutionDisplayStatus,
        failureFocus: AutomationRunFailureFocus?,
        runs: [AutomationTaskRun],
        persistenceIssue: AutomationPersistenceIssue?
    ) -> AutomationRunRecommendedAction {
        if persistenceIssue != nil {
            return .repairStorage
        }
        if status == .running {
            return .waitOrCancel
        }
        guard let failureFocus else {
            return status == .cancelled ? .reviewCancellation : .none
        }

        switch failureFocus.outcome {
        case .permissionDenied(let permission, _):
            return .grantPermission(permission)
        case .missingMacro(let macroID):
            return .restoreMacro(macroID)
        case .failed(let report):
            if let eventIndex = report?.failedEventIndex {
                return .inspectFailedEvent(
                    macroID: failureFocus.macroID,
                    eventIndex: eventIndex,
                    evidenceID: failureFocus.evidenceID
                )
            }
            if let evidenceID = failureFocus.evidenceID {
                return .inspectEvidence(evidenceID)
            }
            return .retryExecution
        case .timedOut:
            return .adjustTimeout
        case .resourceConflict:
            return .adjustResourcePolicy
        case .rejected:
            return .inspectTargetApplication
        case .cancelled:
            return .reviewCancellation
        case .succeeded, .conditionMatched, .conditionNotMatched:
            return runs.contains(where: { !$0.isTerminal }) ? .waitOrCancel : .none
        }
    }
}

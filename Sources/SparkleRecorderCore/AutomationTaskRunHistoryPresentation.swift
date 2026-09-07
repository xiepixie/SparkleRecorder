import Foundation

public struct AutomationTaskRunHistoryPresentation: Equatable, Sendable {
    public var recentRuns: [AutomationTaskRun]
    public var initialSelectedRun: AutomationTaskRun?
    public var activeRunID: UUID?
    public var totalCount: Int

    private var maxAttemptByExecutionID: [UUID: Int]

    public init(
        recentRuns: [AutomationTaskRun],
        initialSelectedRun: AutomationTaskRun?,
        activeRunID: UUID?,
        totalCount: Int,
        maxAttemptByExecutionID: [UUID: Int]
    ) {
        self.recentRuns = recentRuns
        self.initialSelectedRun = initialSelectedRun
        self.activeRunID = activeRunID
        self.totalCount = totalCount
        self.maxAttemptByExecutionID = maxAttemptByExecutionID
    }

    public static func make(
        runs: [AutomationTaskRun],
        workflowID: UUID,
        taskID: UUID,
        initialSelectedRunID: UUID? = nil,
        recentLimit: Int = 5
    ) -> AutomationTaskRunHistoryPresentation {
        struct Candidate {
            var run: AutomationTaskRun
            var sourceIndex: Int
        }

        let limit = max(0, recentLimit)
        var recent: [Candidate] = []
        recent.reserveCapacity(limit)
        var initialSelectedRun: AutomationTaskRun?
        var activeRun: AutomationTaskRun?
        var totalCount = 0
        var maxAttemptByExecutionID: [UUID: Int] = [:]

        for (sourceIndex, run) in runs.enumerated()
        where run.workflowID == workflowID && run.taskID == taskID {
            totalCount += 1
            maxAttemptByExecutionID[run.executionID] = max(
                maxAttemptByExecutionID[run.executionID, default: 0],
                run.attempt
            )

            if run.id == initialSelectedRunID {
                initialSelectedRun = run
            }

            if !run.isTerminal {
                if let current = activeRun {
                    if latestActivityDate(for: current) < latestActivityDate(for: run) {
                        activeRun = run
                    }
                } else {
                    activeRun = run
                }
            }

            guard limit > 0 else {
                continue
            }

            let candidate = Candidate(run: run, sourceIndex: sourceIndex)
            let insertionIndex = recent.firstIndex { existing in
                let candidateDate = latestActivityDate(for: candidate.run)
                let existingDate = latestActivityDate(for: existing.run)
                if candidateDate != existingDate {
                    return candidateDate > existingDate
                }
                return candidate.sourceIndex < existing.sourceIndex
            } ?? recent.endIndex
            recent.insert(candidate, at: insertionIndex)
            if recent.count > limit {
                recent.removeLast()
            }
        }

        return AutomationTaskRunHistoryPresentation(
            recentRuns: recent.map(\.run),
            initialSelectedRun: initialSelectedRun,
            activeRunID: activeRun?.id,
            totalCount: totalCount,
            maxAttemptByExecutionID: maxAttemptByExecutionID
        )
    }

    public func run(id: UUID) -> AutomationTaskRun? {
        if initialSelectedRun?.id == id {
            return initialSelectedRun
        }
        return recentRuns.first { $0.id == id }
    }

    public func hasLaterAttempt(after run: AutomationTaskRun) -> Bool {
        maxAttemptByExecutionID[run.executionID, default: run.attempt] > run.attempt
    }

    private static func latestActivityDate(for run: AutomationTaskRun) -> Date {
        run.actualStartTime ?? run.earliestStartTime ?? run.scheduledStartTime ?? run.createdAt
    }
}

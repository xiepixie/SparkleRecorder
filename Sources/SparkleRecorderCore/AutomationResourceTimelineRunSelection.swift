import Foundation

struct AutomationResourceTimelineRunSelection: Sendable {
    private struct ExecutionKey: Hashable, Sendable {
        var workflowID: UUID
        var executionID: UUID
    }

    private struct ExecutionSummary: Sendable {
        var hasActiveRun: Bool
        var latestActivityAt: Date
    }

    static func currentContextRuns(
        from runs: [AutomationTaskRun]
    ) -> [AutomationTaskRun] {
        guard !runs.isEmpty else {
            return []
        }

        var summaries: [ExecutionKey: ExecutionSummary] = [:]
        var executionKeysByWorkflow: [UUID: Set<ExecutionKey>] = [:]

        for run in runs {
            let key = ExecutionKey(
                workflowID: run.workflowID,
                executionID: run.executionID
            )
            let activityAt = activityDate(for: run)
            if var summary = summaries[key] {
                summary.hasActiveRun = summary.hasActiveRun || !run.isTerminal
                summary.latestActivityAt = max(summary.latestActivityAt, activityAt)
                summaries[key] = summary
            } else {
                summaries[key] = ExecutionSummary(
                    hasActiveRun: !run.isTerminal,
                    latestActivityAt: activityAt
                )
            }
            executionKeysByWorkflow[run.workflowID, default: []].insert(key)
        }

        var selectedExecutionKeys = Set<ExecutionKey>()
        selectedExecutionKeys.reserveCapacity(executionKeysByWorkflow.count)

        for keys in executionKeysByWorkflow.values {
            let activeKeys = keys.filter { summaries[$0]?.hasActiveRun == true }
            if !activeKeys.isEmpty {
                selectedExecutionKeys.formUnion(activeKeys)
                continue
            }

            guard let latestKey = latestExecutionKey(in: keys, summaries: summaries) else {
                continue
            }
            selectedExecutionKeys.insert(latestKey)
        }

        return runs.filter { run in
            selectedExecutionKeys.contains(
                ExecutionKey(
                    workflowID: run.workflowID,
                    executionID: run.executionID
                )
            )
        }
    }

    private static func latestExecutionKey(
        in keys: Set<ExecutionKey>,
        summaries: [ExecutionKey: ExecutionSummary]
    ) -> ExecutionKey? {
        var selected: ExecutionKey?

        for candidate in keys {
            guard let candidateSummary = summaries[candidate] else {
                continue
            }
            guard let current = selected,
                  let currentSummary = summaries[current] else {
                selected = candidate
                continue
            }

            if candidateSummary.latestActivityAt > currentSummary.latestActivityAt {
                selected = candidate
            } else if candidateSummary.latestActivityAt == currentSummary.latestActivityAt,
                      candidate.executionID.uuidString < current.executionID.uuidString {
                selected = candidate
            }
        }

        return selected
    }

    private static func activityDate(for run: AutomationTaskRun) -> Date {
        run.completedAt
            ?? run.actualStartTime
            ?? run.earliestStartTime
            ?? run.scheduledStartTime
            ?? run.createdAt
    }
}

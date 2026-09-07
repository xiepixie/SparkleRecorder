import Foundation

struct AutomationRunHistoryIndex: Sendable {
    private struct TaskKey: Hashable, Sendable {
        var workflowID: UUID
        var taskID: UUID
    }

    private struct DownstreamKey: Hashable, Sendable {
        var workflowID: UUID
        var executionID: UUID
        var targetTaskID: UUID
        var upstreamRunID: UUID
    }

    private var runsByTask: [TaskKey: [AutomationTaskRun]]
    private var latestRunByTask: [TaskKey: AutomationTaskRun]
    private var latestDownstreamRunByKey: [DownstreamKey: AutomationTaskRun]

    init(runs: [AutomationTaskRun]) {
        var runsByTask: [TaskKey: [AutomationTaskRun]] = [:]
        var latestRunByTask: [TaskKey: AutomationTaskRun] = [:]
        var latestDownstreamRunByKey: [DownstreamKey: AutomationTaskRun] = [:]

        for run in runs {
            let taskKey = TaskKey(workflowID: run.workflowID, taskID: run.taskID)
            runsByTask[taskKey, default: []].append(run)
            if let current = latestRunByTask[taskKey] {
                if Self.isEarlier(current, than: run) {
                    latestRunByTask[taskKey] = run
                }
            } else {
                latestRunByTask[taskKey] = run
            }

            for upstreamRunID in Set(run.upstreamRunIDs) {
                let downstreamKey = DownstreamKey(
                    workflowID: run.workflowID,
                    executionID: run.executionID,
                    targetTaskID: run.taskID,
                    upstreamRunID: upstreamRunID
                )
                if let current = latestDownstreamRunByKey[downstreamKey] {
                    if Self.isEarlier(current, than: run) {
                        latestDownstreamRunByKey[downstreamKey] = run
                    }
                } else {
                    latestDownstreamRunByKey[downstreamKey] = run
                }
            }
        }

        self.runsByTask = runsByTask
        self.latestRunByTask = latestRunByTask
        self.latestDownstreamRunByKey = latestDownstreamRunByKey
    }

    func runs(workflowID: UUID, taskID: UUID) -> [AutomationTaskRun] {
        runsByTask[TaskKey(workflowID: workflowID, taskID: taskID)] ?? []
    }

    func latestRun(workflowID: UUID, taskID: UUID) -> AutomationTaskRun? {
        latestRunByTask[TaskKey(workflowID: workflowID, taskID: taskID)]
    }

    func downstreamRun(
        workflowID: UUID,
        targetTaskID: UUID,
        sourceRun: AutomationTaskRun
    ) -> AutomationTaskRun? {
        latestDownstreamRunByKey[
            DownstreamKey(
                workflowID: workflowID,
                executionID: sourceRun.executionID,
                targetTaskID: targetTaskID,
                upstreamRunID: sourceRun.id
            )
        ]
    }

    static func timelineSortDate(_ run: AutomationTaskRun) -> Date {
        run.completedAt
            ?? run.actualStartTime
            ?? run.earliestStartTime
            ?? run.scheduledStartTime
            ?? run.createdAt
    }

    private static func isEarlier(
        _ left: AutomationTaskRun,
        than right: AutomationTaskRun
    ) -> Bool {
        timelineSortDate(left) < timelineSortDate(right)
    }
}

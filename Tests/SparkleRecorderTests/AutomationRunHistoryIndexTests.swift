import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation Run History Index Tests")
struct AutomationRunHistoryIndexTests {
    @Test("Task lookup preserves run order and isolates workflow scope")
    func taskLookupPreservesRunOrderAndWorkflowScope() {
        let workflowID = UUID()
        let otherWorkflowID = UUID()
        let taskID = UUID()
        let first = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(10)
        )
        let second = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(20)
        )
        let other = makeRun(
            workflowID: otherWorkflowID,
            taskID: taskID,
            createdAt: date(30)
        )

        let index = AutomationRunHistoryIndex(runs: [first, other, second])

        #expect(index.runs(workflowID: workflowID, taskID: taskID).map(\.id) == [first.id, second.id])
        #expect(index.runs(workflowID: otherWorkflowID, taskID: taskID).map(\.id) == [other.id])
    }

    @Test("Latest run uses the existing timeline ordering and preserves first tie")
    func latestRunUsesExistingTimelineOrderingAndPreservesFirstTie() {
        let workflowID = UUID()
        let taskID = UUID()
        var completed = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(10)
        )
        completed.completedAt = date(40)

        var started = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(50)
        )
        started.actualStartTime = date(30)

        let tiedFirst = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(60)
        )
        let tiedSecond = makeRun(
            workflowID: workflowID,
            taskID: taskID,
            createdAt: date(60)
        )

        let index = AutomationRunHistoryIndex(
            runs: [started, completed, tiedFirst, tiedSecond]
        )

        #expect(index.latestRun(workflowID: workflowID, taskID: taskID)?.id == tiedFirst.id)
        #expect(AutomationRunHistoryIndex.timelineSortDate(completed) == date(40))
        #expect(AutomationRunHistoryIndex.timelineSortDate(started) == date(30))
    }

    @Test("Downstream lookup keeps execution task and upstream run boundaries")
    func downstreamLookupKeepsExecutionTaskAndUpstreamRunBoundaries() {
        let workflowID = UUID()
        let sourceTaskID = UUID()
        let targetTaskID = UUID()
        let otherTargetTaskID = UUID()
        let executionID = UUID()
        let source = makeRun(
            workflowID: workflowID,
            taskID: sourceTaskID,
            executionID: executionID,
            createdAt: date(10)
        )

        let matching = makeRun(
            workflowID: workflowID,
            taskID: targetTaskID,
            executionID: executionID,
            createdAt: date(20),
            upstreamRunIDs: [source.id]
        )
        let newerMatching = makeRun(
            workflowID: workflowID,
            taskID: targetTaskID,
            executionID: executionID,
            createdAt: date(30),
            upstreamRunIDs: [source.id, source.id]
        )
        let wrongExecution = makeRun(
            workflowID: workflowID,
            taskID: targetTaskID,
            executionID: UUID(),
            createdAt: date(40),
            upstreamRunIDs: [source.id]
        )
        let wrongTask = makeRun(
            workflowID: workflowID,
            taskID: otherTargetTaskID,
            executionID: executionID,
            createdAt: date(50),
            upstreamRunIDs: [source.id]
        )

        let index = AutomationRunHistoryIndex(
            runs: [source, matching, wrongExecution, wrongTask, newerMatching]
        )

        #expect(
            index.downstreamRun(
                workflowID: workflowID,
                targetTaskID: targetTaskID,
                sourceRun: source
            )?.id == newerMatching.id
        )
        #expect(
            index.downstreamRun(
                workflowID: workflowID,
                targetTaskID: otherTargetTaskID,
                sourceRun: source
            )?.id == wrongTask.id
        )
    }

    @Test("Indexed latest lookup matches the previous linear scan across large history")
    func indexedLatestLookupMatchesPreviousLinearScanAcrossLargeHistory() {
        let workflowIDs = (0..<4).map { _ in UUID() }
        let taskIDs = (0..<24).map { _ in UUID() }
        var runs: [AutomationTaskRun] = []
        runs.reserveCapacity(12_000)

        for index in 0..<12_000 {
            let workflowID = workflowIDs[index % workflowIDs.count]
            let taskID = taskIDs[(index * 7) % taskIDs.count]
            var run = makeRun(
                workflowID: workflowID,
                taskID: taskID,
                executionID: UUID(),
                createdAt: date(TimeInterval(index))
            )
            if index % 5 == 0 {
                run.actualStartTime = date(TimeInterval(index + 2))
            }
            if index % 11 == 0 {
                run.completedAt = date(TimeInterval(index + 4))
            }
            runs.append(run)
        }

        let index = AutomationRunHistoryIndex(runs: runs)

        for workflowID in workflowIDs {
            for taskID in taskIDs {
                let expected = runs
                    .filter { $0.workflowID == workflowID && $0.taskID == taskID }
                    .max {
                        AutomationRunHistoryIndex.timelineSortDate($0)
                            < AutomationRunHistoryIndex.timelineSortDate($1)
                    }
                #expect(index.latestRun(workflowID: workflowID, taskID: taskID)?.id == expected?.id)
            }
        }
    }

    @Test("Indexed downstream lookup matches the previous linear scan")
    func indexedDownstreamLookupMatchesPreviousLinearScan() {
        let workflowID = UUID()
        let sourceTaskID = UUID()
        let targetTaskID = UUID()
        let executionIDs = (0..<30).map { _ in UUID() }
        var sources: [AutomationTaskRun] = []
        var runs: [AutomationTaskRun] = []

        for (executionIndex, executionID) in executionIDs.enumerated() {
            let source = makeRun(
                workflowID: workflowID,
                taskID: sourceTaskID,
                executionID: executionID,
                createdAt: date(TimeInterval(executionIndex * 100))
            )
            sources.append(source)
            runs.append(source)

            for attempt in 0..<8 {
                runs.append(
                    makeRun(
                        workflowID: workflowID,
                        taskID: targetTaskID,
                        executionID: executionID,
                        createdAt: date(TimeInterval(executionIndex * 100 + attempt + 1)),
                        upstreamRunIDs: [source.id]
                    )
                )
            }
        }

        let index = AutomationRunHistoryIndex(runs: runs)

        for source in sources {
            let expected = runs
                .filter { run in
                    run.workflowID == workflowID
                        && run.taskID == targetTaskID
                        && run.executionID == source.executionID
                        && run.upstreamRunIDs.contains(source.id)
                }
                .max {
                    AutomationRunHistoryIndex.timelineSortDate($0)
                        < AutomationRunHistoryIndex.timelineSortDate($1)
                }

            #expect(
                index.downstreamRun(
                    workflowID: workflowID,
                    targetTaskID: targetTaskID,
                    sourceRun: source
                )?.id == expected?.id
            )
        }
    }

    private func makeRun(
        workflowID: UUID,
        taskID: UUID,
        executionID: UUID? = nil,
        createdAt: Date,
        upstreamRunIDs: [UUID] = []
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: taskID,
            createdAt: createdAt,
            upstreamRunIDs: upstreamRunIDs
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }
}

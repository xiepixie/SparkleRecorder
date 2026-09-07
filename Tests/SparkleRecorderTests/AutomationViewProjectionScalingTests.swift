import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Automation View Projection Scaling Tests")
struct AutomationViewProjectionScalingTests {
    @Test("Large run history preserves latest schedule and downstream semantics")
    func largeRunHistoryPreservesLatestScheduleAndDownstreamSemantics() throws {
        let workflowID = UUID()
        let sourceTaskID = UUID()
        let targetTaskID = UUID()
        let dependencyID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let generatedAt = base.addingTimeInterval(50_000)
        let scheduledAt = base.addingTimeInterval(60_000)

        let sourceTask = AutomationTask(
            id: sourceTaskID,
            name: "Prepare",
            kind: .delay(0),
            schedule: .once(scheduledAt)
        )
        let targetTask = AutomationTask(
            id: targetTaskID,
            name: "Publish",
            kind: .delay(0)
        )
        let dependency = AutomationDependency(
            id: dependencyID,
            fromTaskID: sourceTaskID,
            toTaskID: targetTaskID,
            trigger: .onSuccess
        )
        let workflow = AutomationWorkflow(
            id: workflowID,
            name: "Indexed history",
            tasks: [sourceTask, targetTask],
            dependencies: [dependency]
        )

        var runs: [AutomationTaskRun] = []
        runs.reserveCapacity(10_002)
        for index in 0..<10_000 {
            let completedAt = base.addingTimeInterval(TimeInterval(index))
            runs.append(
                AutomationTaskRun(
                    executionID: UUID(),
                    workflowID: workflowID,
                    taskID: index.isMultiple(of: 2) ? sourceTaskID : targetTaskID,
                    completedAt: completedAt,
                    status: .completed,
                    outcome: .succeeded(report: nil),
                    createdAt: completedAt
                )
            )
        }

        let executionID = UUID()
        var latestSource = AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: sourceTaskID,
            scheduledStartTime: scheduledAt,
            actualStartTime: base.addingTimeInterval(100_000),
            completedAt: base.addingTimeInterval(100_001),
            status: .completed,
            outcome: .succeeded(report: nil),
            createdAt: base.addingTimeInterval(99_999)
        )
        latestSource.attempt = 2
        let downstreamTarget = AutomationTaskRun(
            executionID: executionID,
            workflowID: workflowID,
            taskID: targetTaskID,
            actualStartTime: base.addingTimeInterval(100_002),
            status: .running,
            createdAt: base.addingTimeInterval(100_002),
            upstreamRunIDs: [latestSource.id]
        )
        runs.append(latestSource)
        runs.append(downstreamTarget)

        let projection = AutomationViewProjection.overview(
            from: AutomationRunState(
                workflows: [workflow],
                runs: runs,
                now: generatedAt
            )
        )

        let projectedWorkflow = try #require(projection.workflows.first)
        let sourceNode = try #require(projectedWorkflow.nodes.first { $0.taskID == sourceTaskID })
        let targetNode = try #require(projectedWorkflow.nodes.first { $0.taskID == targetTaskID })
        let edge = try #require(projectedWorkflow.edges.first { $0.id == dependencyID })

        #expect(sourceNode.runID == latestSource.id)
        #expect(sourceNode.nextScheduledOccurrence == nil)
        #expect(targetNode.runID == downstreamTarget.id)
        #expect(edge.status == .satisfied)
        #expect(edge.branchDecision?.sourceRunID == latestSource.id)
        #expect(edge.branchDecision?.targetRunID == downstreamTarget.id)
        #expect(edge.branchDecision?.executionID == executionID)
        #expect(projection.timelineItems.map(\.runID) == [latestSource.id, downstreamTarget.id])
    }
}

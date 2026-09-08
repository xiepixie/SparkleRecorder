import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Catalog Run Index Tests")
struct AutomationCatalogRunIndexTests {
    @Test("Catalog run index keeps count, latest five, and newest attention run")
    func catalogRunIndexSummarizesWithoutViewFiltering() throws {
        let workflowID = UUID()
        let otherWorkflowID = UUID()
        let base = Date(timeIntervalSince1970: 2_000_000_000)

        var executions: [AutomationExecutionProjection] = []
        for index in 0..<12 {
            executions.append(
                execution(
                    workflowID: workflowID,
                    status: index == 3 ? .needsAttention : .succeeded,
                    activityAt: base.addingTimeInterval(TimeInterval(-index))
                )
            )
        }
        executions.append(
            execution(
                workflowID: otherWorkflowID,
                status: .running,
                activityAt: base.addingTimeInterval(1)
            )
        )

        let index = AutomationCatalogRunIndex(executions: executions)
        let summary = index.summary(for: workflowID)

        #expect(summary.totalCount == 12)
        #expect(summary.recentExecutions.count == 5)
        #expect(summary.recentExecutions.map(\.workflowID).allSatisfy { $0 == workflowID })
        #expect(summary.latestNeedsAttention == executions[3])
        #expect(index.summary(for: UUID()).isEmpty)
    }

    @Test("Ten thousand executions stay indexed by workflow")
    func largeHistoryIndexesEveryWorkflow() {
        let workflowIDs = (0..<100).map { _ in UUID() }
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let executions = (0..<10_000).map { index in
            execution(
                workflowID: workflowIDs[index % workflowIDs.count],
                status: .succeeded,
                activityAt: base.addingTimeInterval(TimeInterval(-index))
            )
        }

        let index = AutomationCatalogRunIndex(executions: executions)

        for workflowID in workflowIDs {
            let summary = index.summary(for: workflowID)
            #expect(summary.totalCount == 100)
            #expect(summary.recentExecutions.count == 5)
        }
    }

    private func execution(
        workflowID: UUID,
        status: AutomationExecutionDisplayStatus,
        activityAt: Date
    ) -> AutomationExecutionProjection {
        AutomationExecutionProjection(
            executionID: UUID(),
            workflowID: workflowID,
            workflowName: "Workflow",
            status: status,
            createdAt: activityAt,
            latestActivityAt: activityAt,
            taskRunCount: 1,
            completedRunCount: status == .running ? 0 : 1,
            attemptCount: 1,
            hasEvidence: false,
            hasActiveRun: status == .running,
            failureFocus: nil,
            recommendedAction: .none,
            runs: []
        )
    }
}

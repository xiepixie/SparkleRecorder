import Foundation
import SparkleRecorderCore

struct AutomationCatalogExecutionSummary: Equatable, Sendable {
    var totalCount: Int
    var recentExecutions: [AutomationExecutionProjection]
    var latestNeedsAttention: AutomationExecutionProjection?

    static let empty = AutomationCatalogExecutionSummary(
        totalCount: 0,
        recentExecutions: [],
        latestNeedsAttention: nil
    )

    var isEmpty: Bool { totalCount == 0 }
}

struct AutomationCatalogRunIndex: Equatable, Sendable {
    private var summariesByWorkflowID: [UUID: AutomationCatalogExecutionSummary]

    init(executions: [AutomationExecutionProjection]) {
        var summaries: [UUID: AutomationCatalogExecutionSummary] = [:]
        summaries.reserveCapacity(min(executions.count, 64))

        for execution in executions {
            var summary = summaries[execution.workflowID] ?? .empty
            summary.totalCount += 1
            if summary.recentExecutions.count < 5 {
                summary.recentExecutions.append(execution)
            }
            if summary.latestNeedsAttention == nil, execution.status == .needsAttention {
                summary.latestNeedsAttention = execution
            }
            summaries[execution.workflowID] = summary
        }

        summariesByWorkflowID = summaries
    }

    func summary(for workflowID: UUID) -> AutomationCatalogExecutionSummary {
        summariesByWorkflowID[workflowID] ?? .empty
    }
}

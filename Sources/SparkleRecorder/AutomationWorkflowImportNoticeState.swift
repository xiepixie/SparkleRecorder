import Foundation
import SparkleRecorderCore

struct AutomationWorkflowImportNoticeState: Identifiable, Equatable {
    let id = UUID()
    let workflowID: UUID
    let workflowName: String
    let taskCount: Int
    let dependencyCount: Int
    let isReplacement: Bool
    let previousWorkflow: AutomationWorkflow?
}

import Foundation
import SparkleRecorderCore

struct AutomationWorkflowDraftConditionEdit {
    let taskKey: String
    let condition: AutomationWorkflowDraftCondition
    let timeoutSeconds: TimeInterval?
    let pollingSeconds: TimeInterval?
}

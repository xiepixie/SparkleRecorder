import Foundation
import SparkleRecorderCore

struct AutomationWorkflowDraftDependencyEdit {
    let selector: AutomationWorkflowDraftDependencySelector
    let from: String
    let to: String
    let trigger: String
    let delaySeconds: TimeInterval
    let enabled: Bool
    let removesDependency: Bool
}

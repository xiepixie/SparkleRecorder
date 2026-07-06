import Foundation
import SparkleRecorderCore

struct AutomationWorkflowDraftPreviewState: Identifiable {
    let id = UUID()
    let sourceName: String
    let sourceDirectory: URL?
    let loadedAt: Date
    let document: AutomationWorkflowDraftDocument
    let macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    let projection: AutomationWorkflowDraftPreviewProjection
    let compiledWorkflow: AutomationWorkflow?

    var canImportCompiledWorkflow: Bool {
        projection.importPreview?.isImportable == true && compiledWorkflow != nil
    }
}

import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation Workflow Draft Preview Presenter Tests")
struct AutomationWorkflowDraftPreviewPresenterTests {
    @MainActor
    @Test("Draft preview resolves macros from the catalog available when file selection completes")
    func previewUsesCatalogAtSelectionCompletion() throws {
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(
                name: "Live catalog preview",
                tasks: [
                    AutomationWorkflowDraftTask(
                        key: "tap",
                        type: "macro",
                        macroRef: AutomationWorkflowDraftMacroRef(name: "Tap")
                    )
                ]
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-draft-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let addedWhilePanelWasOpen = SavedMacro(name: "Tap", events: [])
        var currentMacros: [SavedMacro] = []
        var preview: AutomationWorkflowDraftPreviewState?

        AutomationWorkflowDraftPreviewPresenter.openDraft(
            currentMacros: { currentMacros },
            selectURL: { completion in
                currentMacros = [addedWhilePanelWasOpen]
                completion(url)
            },
            onPreview: { preview = $0 }
        )

        let state = try #require(preview)
        let macroRow = try #require(state.projection.taskRows.first)
        #expect(
            macroRow.macroResolution
                == .resolved(name: addedWhilePanelWasOpen.name, id: addedWhilePanelWasOpen.id)
        )
        #expect(state.macroCatalog.map(\.id) == [addedWhilePanelWasOpen.id])
        #expect(state.compiledWorkflow != nil)
    }
}

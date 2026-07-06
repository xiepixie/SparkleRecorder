import AppKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

@MainActor
enum AutomationWorkflowDraftPreviewPresenter {
    static func openDraft(
        macros: [SavedMacro],
        onPreview: @escaping (AutomationWorkflowDraftPreviewState) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Open Workflow Draft", comment: "")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let state = try previewState(from: url, macros: macros)
                onPreview(state)
            } catch {
                showError(
                    title: NSLocalizedString("Draft preview failed", comment: ""),
                    message: String(describing: error)
                )
            }
        }
    }

    static func openPatch(
        document: AutomationWorkflowDraftDocument,
        macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry],
        onApply: @escaping (Result<AutomationWorkflowDraftEditResult, Error>) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Apply Workflow Draft Patch", comment: "")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let data = try Data(contentsOf: url)
                let patch = try decodePatchDocument(from: data)
                let result = try AutomationWorkflowDraftPatchApplier.apply(
                    patch,
                    to: document,
                    context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog)
                )
                onApply(.success(result))
            } catch {
                onApply(.failure(error))
            }
        }
    }

    private static func previewState(
        from url: URL,
        macros: [SavedMacro]
    ) throws -> AutomationWorkflowDraftPreviewState {
        let data = try Data(contentsOf: url)
        let document = try decodeDraftDocument(from: data)
        let catalog = macros.map(AutomationWorkflowDraftMacroCatalogEntry.init(macro:))
        return previewState(
            document: document,
            sourceName: url.lastPathComponent,
            sourceDirectory: url.deletingLastPathComponent(),
            loadedAt: Date(),
            macroCatalog: catalog
        )
    }

    static func previewState(
        document: AutomationWorkflowDraftDocument,
        sourceName: String,
        sourceDirectory: URL? = nil,
        loadedAt: Date = Date(),
        macroCatalog: [AutomationWorkflowDraftMacroCatalogEntry]
    ) -> AutomationWorkflowDraftPreviewState {
        let context = AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog)
        let validationResult = AutomationWorkflowDraftValidator.validate(
            document,
            context: context
        )
        let validationEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftValidationPayload>
            .workflowDraftValidation(command: "workflow draft validate", result: validationResult)
        let simulationResult = AutomationWorkflowDraftSimulator.simulate(
            document,
            context: context
        )
        let simulationEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftSimulationPayload>
            .workflowDraftSimulation(command: "workflow draft simulate", result: simulationResult)
        let importResult = AutomationWorkflowDraftImporter.dryRun(
            document,
            context: context
        )
        let importEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowDraftImportPayload>
            .workflowDraftImport(command: "workflow import --dry-run", result: importResult)
        let macroCatalogEnvelope = AutomationCLIResultEnvelope<AutomationWorkflowMacroCatalogPayload>
            .workflowMacroCatalog(command: "workflow macros", macros: macroCatalog)
        let projection = AutomationWorkflowDraftPreviewProjection(
            document: document,
            validationEnvelope: validationEnvelope,
            macroCatalogEnvelope: macroCatalogEnvelope,
            simulationEnvelope: simulationEnvelope,
            importEnvelope: importEnvelope
        )

        return AutomationWorkflowDraftPreviewState(
            sourceName: sourceName,
            sourceDirectory: sourceDirectory,
            loadedAt: loadedAt,
            document: document,
            macroCatalog: macroCatalog,
            projection: projection,
            compiledWorkflow: importResult.workflow
        )
    }

    private static func decodeDraftDocument(from data: Data) throws -> AutomationWorkflowDraftDocument {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        do {
            return try isoDecoder.decode(AutomationWorkflowDraftDocument.self, from: data)
        } catch {
            return try JSONDecoder().decode(AutomationWorkflowDraftDocument.self, from: data)
        }
    }

    private static func decodePatchDocument(from data: Data) throws -> AutomationWorkflowDraftPatchDocument {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        do {
            return try isoDecoder.decode(AutomationWorkflowDraftPatchDocument.self, from: data)
        } catch {
            return try JSONDecoder().decode(AutomationWorkflowDraftPatchDocument.self, from: data)
        }
    }

    private static func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

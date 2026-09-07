import AppKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

@MainActor
enum AutomationWorkflowPackagePresenter {
    private static var sharedPackageURLs: [URL] = []

    static func export(workflow: AutomationWorkflow) {
        export(
            workflows: [workflow],
            title: String(localized: "Export Workflow", table: "Automation"),
            defaultName: workflow.name
        )
    }

    static func export(workflows: [AutomationWorkflow], defaultName: String) {
        export(
            workflows: workflows,
            title: String(localized: "Export Workflow Package", table: "Automation"),
            defaultName: defaultName
        )
    }

    static func share(workflow: AutomationWorkflow) {
        share(workflows: [workflow], defaultName: workflow.name)
    }

    static func share(workflows: [AutomationWorkflow], defaultName: String) {
        guard !workflows.isEmpty else {
            return
        }

        do {
            let url = try temporaryPackageURL(workflows: workflows, defaultName: defaultName)
            guard let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
                showError(
                    title: String(localized: "Share failed", table: "Common"),
                    message: String(localized: "Open a SparkleRecorder window before sharing a workflow package.", table: "Automation")
                )
                return
            }

            sharedPackageURLs.append(url)
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } catch {
            showError(
                title: String(localized: "Share failed", table: "Common"),
                message: String(describing: error)
            )
        }
    }

    private static func export(
        workflows: [AutomationWorkflow],
        title: String,
        defaultName: String
    ) {
        guard !workflows.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = "\(safeFileName(defaultName)).\(AutomationWorkflowPackage.fileExtension)"
        if let type = UTType(filenameExtension: AutomationWorkflowPackage.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let data = try AutomationWorkflowPackage.encode(workflows: workflows)
                try data.write(to: url, options: .atomic)
            } catch {
                showError(
                    title: String(localized: "Export failed", table: "Common"),
                    message: String(describing: error)
                )
            }
        }
    }

    private static func temporaryPackageURL(
        workflows: [AutomationWorkflow],
        defaultName: String
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorderWorkflowPackages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "\(safeFileName(defaultName))-\(UUID().uuidString).\(AutomationWorkflowPackage.fileExtension)"
        let url = directory.appendingPathComponent(fileName)
        let data = try AutomationWorkflowPackage.encode(workflows: workflows)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func importWorkflows(
        currentWorkflows: @escaping @MainActor () -> [AutomationWorkflow],
        availableMacroIDs: Set<UUID>,
        onImport: @escaping @MainActor ([AutomationWorkflow]) async throws -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Workflow Package", table: "Automation")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: AutomationWorkflowPackage.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else {
                return
            }

            do {
                let importItems = try panel.urls.flatMap { url in
                    let data = try Data(contentsOf: url)
                    let packageDirectoryURL = url.deletingLastPathComponent()
                    return try AutomationWorkflowPackage.decode(data).workflows.map {
                        AutomationWorkflowPackageImportItem(
                            workflow: $0,
                            packageDirectoryURL: packageDirectoryURL
                        )
                    }
                }
                guard let prepared = prepareForImport(
                    importItems,
                    currentWorkflows: currentWorkflows()
                ) else {
                    return
                }
                let workflows = prepared.map(\.workflow)
                guard confirmMissingMacroReferences(in: workflows, availableMacroIDs: availableMacroIDs) else {
                    return
                }
                Task { @MainActor in
                    do {
                        try await onImport(workflows)
                    } catch {
                        showError(
                            title: String(localized: "Import failed", table: "Common"),
                            message: error.localizedDescription
                        )
                        return
                    }

                    do {
                        try await persistVisualAssetPackageRoots(for: prepared)
                    } catch {
                        showError(
                            title: String(localized: "Visual assets could not be linked", table: "Automation"),
                            message: String(
                                localized: "The workflows were imported, but some visual assets could not be linked. Import the package again to retry the asset links.",
                                table: "Automation"
                            )
                        )
                    }
                }
            } catch {
                showError(
                    title: String(localized: "Import failed", table: "Common"),
                    message: String(describing: error)
                )
            }
        }
    }

    private static func prepareForImport(
        _ importItems: [AutomationWorkflowPackageImportItem],
        currentWorkflows: [AutomationWorkflow]
    ) -> [AutomationWorkflowPackageImportItem]? {
        guard !importItems.isEmpty else {
            return []
        }

        let conflictPlan = AutomationWorkflowPackageImportConflictPlan.make(
            importItems: importItems,
            currentWorkflows: currentWorkflows
        )
        guard conflictPlan.requiresResolution else {
            return importItems
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Workflow package has conflicts", table: "Automation")
        alert.informativeText = String(localized: "Some imported workflows already exist. Add copies to keep existing workflows, or replace matching workflows.", table: "Automation")
        alert.addButton(withTitle: String(localized: "Add Copies", table: "Common"))
        alert.addButton(withTitle: String(localized: "Replace Existing", table: "Common"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Common"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return conflictPlan.addingCopies(importItems, now: Date())
        case .alertSecondButtonReturn:
            return importItems
        default:
            return nil
        }
    }

    private static func confirmMissingMacroReferences(
        in workflows: [AutomationWorkflow],
        availableMacroIDs: Set<UUID>
    ) -> Bool {
        let missingMacroIDs = missingMacroIDs(in: workflows, availableMacroIDs: availableMacroIDs)
        guard !missingMacroIDs.isEmpty else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Workflow package references missing macros", table: "Automation")
        alert.informativeText = String(
            format: String(localized: "This package references %d macros that are not in your local library. The workflows can still be imported, but those tasks will show as Missing macro until you import or recreate the macros.", table: "Automation"),
            missingMacroIDs.count
        )
        alert.addButton(withTitle: String(localized: "Import Anyway", table: "Common"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Common"))

        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func missingMacroIDs(
        in workflows: [AutomationWorkflow],
        availableMacroIDs: Set<UUID>
    ) -> [UUID] {
        let referencedIDs = workflows.flatMap { workflow in
            workflow.tasks.compactMap { task -> UUID? in
                guard case .macro(let macroID) = task.kind else {
                    return nil
                }
                return macroID
            }
        }

        return Set(referencedIDs)
            .subtracting(availableMacroIDs)
            .sorted { $0.uuidString < $1.uuidString }
    }

    private static func persistVisualAssetPackageRoots(
        for importItems: [AutomationWorkflowPackageImportItem]
    ) async throws {
        let association = AutomationVisualAssetPackageRootAssociation.fileBacked()
        let requests = importItems.map { item in
            AutomationVisualAssetPackageRootAssociation.Request(
                workflow: item.workflow,
                packageDirectoryURL: item.packageDirectoryURL,
                source: .workflowPackageImport
            )
        }
        try await association.persist(requests, associatedAt: Date())
    }

    private static func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? String(localized: "Workflow", table: "Automation") : trimmed
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return base
            .components(separatedBy: invalid)
            .joined(separator: "-")
    }

    private static func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

import AppKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

@MainActor
enum AutomationWorkflowPackagePresenter {
    private static var sharedPackageURLs: [URL] = []

    private struct WorkflowPackageImportItem {
        var workflow: AutomationWorkflow
        var packageDirectoryURL: URL
    }

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
        currentWorkflows: [AutomationWorkflow],
        availableMacroIDs: Set<UUID>,
        onImport: @escaping ([AutomationWorkflow]) -> Void
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
                        WorkflowPackageImportItem(
                            workflow: $0,
                            packageDirectoryURL: packageDirectoryURL
                        )
                    }
                }
                guard let prepared = prepareForImport(importItems, currentWorkflows: currentWorkflows) else {
                    return
                }
                let workflows = prepared.map(\.workflow)
                guard confirmMissingMacroReferences(in: workflows, availableMacroIDs: availableMacroIDs) else {
                    return
                }
                onImport(workflows)
                persistVisualAssetPackageRoots(for: prepared)
            } catch {
                showError(
                    title: String(localized: "Import failed", table: "Common"),
                    message: String(describing: error)
                )
            }
        }
    }

    private static func prepareForImport(
        _ importItems: [WorkflowPackageImportItem],
        currentWorkflows: [AutomationWorkflow]
    ) -> [WorkflowPackageImportItem]? {
        guard !importItems.isEmpty else {
            return []
        }

        let workflows = importItems.map(\.workflow)
        let currentIDs = Set(currentWorkflows.map(\.id))
        let importedIDs = workflows.map(\.id)
        let duplicateIDs = duplicateValues(importedIDs)
        let conflictsExisting = workflows.contains { currentIDs.contains($0.id) }
        let conflictsWithinImport = !duplicateIDs.isEmpty

        guard conflictsExisting || conflictsWithinImport else {
            return importItems
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Workflow package has conflicts", table: "Automation")
        alert.informativeText = NSLocalizedString(
            "Some imported workflows already exist. Add copies to keep existing workflows, or replace matching workflows.",
            comment: ""
        )
        alert.addButton(withTitle: String(localized: "Add Copies", table: "Common"))
        alert.addButton(withTitle: String(localized: "Replace Existing", table: "Common"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Common"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return importItemsWithCopiedConflicts(importItems, currentIDs: currentIDs)
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
            format: NSLocalizedString(
                "This package references %d macros that are not in your local library. The workflows can still be imported, but those tasks will show as Missing macro until you import or recreate the macros.",
                comment: ""
            ),
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

    private static func importItemsWithCopiedConflicts(
        _ importItems: [WorkflowPackageImportItem],
        currentIDs: Set<UUID>
    ) -> [WorkflowPackageImportItem] {
        var seenIDs = currentIDs
        let now = Date()
        return importItems.map { item in
            var workflow = item.workflow
            guard seenIDs.contains(workflow.id) else {
                seenIDs.insert(workflow.id)
                return item
            }

            workflow.id = UUID()
            workflow.name = String(format: String(localized: "%@ Copy", table: "Common"), workflow.name)
            workflow.createdAt = now
            workflow.modifiedAt = now
            seenIDs.insert(workflow.id)
            return WorkflowPackageImportItem(
                workflow: workflow,
                packageDirectoryURL: item.packageDirectoryURL
            )
        }
    }

    private static func persistVisualAssetPackageRoots(
        for importItems: [WorkflowPackageImportItem]
    ) {
        let associatedAt = Date()
        let roots = importItems.flatMap { item in
            AutomationVisualAssetPackageRoot.roots(
                for: [item.workflow],
                packageDirectoryURL: item.packageDirectoryURL,
                source: .workflowPackageImport,
                associatedAt: associatedAt
            )
        }
        let rootedWorkflowIDs = Set(roots.map(\.workflowID))
        let unrootedWorkflowIDs = Set(importItems.map(\.workflow.id)).subtracting(rootedWorkflowIDs)
        guard !roots.isEmpty || !unrootedWorkflowIDs.isEmpty else {
            return
        }

        let client = AutomationVisualAssetPackageRootClient.fileBacked()
        Task {
            do {
                if !roots.isEmpty {
                    try await client.upsertRoots(roots)
                }
                if !unrootedWorkflowIDs.isEmpty {
                    try await client.removeRoots(unrootedWorkflowIDs)
                }
            } catch {
                NSLog("SparkleRecorder: Failed to persist imported workflow visual asset roots: \(error)")
            }
        }
    }

    private static func duplicateValues<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var duplicates: Set<T> = []
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return Array(duplicates)
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

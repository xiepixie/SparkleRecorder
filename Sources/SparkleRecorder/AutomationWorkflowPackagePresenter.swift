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
            title: NSLocalizedString("Export Workflow", comment: ""),
            defaultName: workflow.name
        )
    }

    static func export(workflows: [AutomationWorkflow], defaultName: String) {
        export(
            workflows: workflows,
            title: NSLocalizedString("Export Workflow Package", comment: ""),
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
                    title: NSLocalizedString("Share failed", comment: ""),
                    message: NSLocalizedString("Open a SparkleRecorder window before sharing a workflow package.", comment: "")
                )
                return
            }

            sharedPackageURLs.append(url)
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } catch {
            showError(
                title: NSLocalizedString("Share failed", comment: ""),
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
                    title: NSLocalizedString("Export failed", comment: ""),
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
        panel.title = NSLocalizedString("Import Workflow Package", comment: "")
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
                let workflows = try panel.urls.flatMap { url in
                    let data = try Data(contentsOf: url)
                    return try AutomationWorkflowPackage.decode(data).workflows
                }
                guard let prepared = prepareForImport(workflows, currentWorkflows: currentWorkflows) else {
                    return
                }
                guard confirmMissingMacroReferences(in: prepared, availableMacroIDs: availableMacroIDs) else {
                    return
                }
                onImport(prepared)
            } catch {
                showError(
                    title: NSLocalizedString("Import failed", comment: ""),
                    message: String(describing: error)
                )
            }
        }
    }

    private static func prepareForImport(
        _ workflows: [AutomationWorkflow],
        currentWorkflows: [AutomationWorkflow]
    ) -> [AutomationWorkflow]? {
        guard !workflows.isEmpty else {
            return []
        }

        let currentIDs = Set(currentWorkflows.map(\.id))
        let importedIDs = workflows.map(\.id)
        let duplicateIDs = duplicateValues(importedIDs)
        let conflictsExisting = workflows.contains { currentIDs.contains($0.id) }
        let conflictsWithinImport = !duplicateIDs.isEmpty

        guard conflictsExisting || conflictsWithinImport else {
            return workflows
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Workflow package has conflicts", comment: "")
        alert.informativeText = NSLocalizedString(
            "Some imported workflows already exist. Add copies to keep existing workflows, or replace matching workflows.",
            comment: ""
        )
        alert.addButton(withTitle: NSLocalizedString("Add Copies", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Replace Existing", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return workflowsWithCopiedConflicts(workflows, currentIDs: currentIDs)
        case .alertSecondButtonReturn:
            return workflows
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
        alert.messageText = NSLocalizedString("Workflow package references missing macros", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString(
                "This package references %d macros that are not in your local library. The workflows can still be imported, but those tasks will show as Missing macro until you import or recreate the macros.",
                comment: ""
            ),
            missingMacroIDs.count
        )
        alert.addButton(withTitle: NSLocalizedString("Import Anyway", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

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

    private static func workflowsWithCopiedConflicts(
        _ workflows: [AutomationWorkflow],
        currentIDs: Set<UUID>
    ) -> [AutomationWorkflow] {
        var seenIDs = currentIDs
        let now = Date()
        return workflows.map { workflow in
            guard seenIDs.contains(workflow.id) else {
                seenIDs.insert(workflow.id)
                return workflow
            }

            var copy = workflow
            copy.id = UUID()
            copy.name = String(format: NSLocalizedString("%@ Copy", comment: ""), workflow.name)
            copy.createdAt = now
            copy.modifiedAt = now
            seenIDs.insert(copy.id)
            return copy
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
        let base = trimmed.isEmpty ? NSLocalizedString("Workflow", comment: "") : trimmed
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

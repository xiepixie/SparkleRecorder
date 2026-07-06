import AppKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

@MainActor
enum AutomationWorkflowDraftExportPresenter {
    static func export(workflow: AutomationWorkflow, macros: [SavedMacro]) {
        let result = AutomationWorkflowDraftExporter.export(
            workflow,
            options: AutomationWorkflowDraftExportOptions(
                macroCatalog: macros.map(AutomationWorkflowDraftMacroCatalogEntry.init(macro:))
            )
        )

        guard result.isExportable else {
            showIssues(
                title: NSLocalizedString("Workflow draft export blocked", comment: ""),
                message: NSLocalizedString("Resolve workflow validation errors before exporting an AI-editable draft.", comment: ""),
                issues: result.issues
            )
            return
        }

        let panel = NSSavePanel()
        panel.title = NSLocalizedString("Export AI Draft", comment: "")
        panel.nameFieldStringValue = "\(safeFileName(workflow.name)).workflow-draft.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let data = try encodeDraftDocument(result.document)
                try data.write(to: url, options: .atomic)
                showSuccess(result: result, url: url)
            } catch {
                showError(
                    title: NSLocalizedString("Export failed", comment: ""),
                    message: String(describing: error)
                )
            }
        }
    }

    private static func encodeDraftDocument(_ document: AutomationWorkflowDraftDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private static func showSuccess(result: AutomationWorkflowDraftExportResult, url: URL) {
        let warningIssues = result.issues.filter { $0.severity != .error }
        let message = String(
            format: NSLocalizedString("Exported %@ with %d tasks and %d dependencies to %@.", comment: ""),
            result.workflowName,
            result.document.workflow.tasks.count,
            result.document.workflow.dependencies.count,
            url.lastPathComponent
        )

        let warningSummary: String
        if warningIssues.isEmpty {
            warningSummary = NSLocalizedString("Open the exported draft with AI Draft preview to validate or edit it before importing.", comment: "")
        } else {
            warningSummary = String(
                format: NSLocalizedString("%d export warnings need review before re-import.", comment: ""),
                warningIssues.count
            )
        }

        showIssues(
            title: NSLocalizedString("Workflow draft exported", comment: ""),
            message: "\(message)\n\n\(warningSummary)",
            issues: warningIssues
        )
    }

    private static func showIssues(
        title: String,
        message: String,
        issues: [AutomationWorkflowDraftIssue]
    ) {
        let alert = NSAlert()
        alert.alertStyle = issues.contains { $0.severity == .error } ? .warning : .informational
        alert.messageText = title
        alert.informativeText = issueMessage(message, issues: issues)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    private static func issueMessage(_ message: String, issues: [AutomationWorkflowDraftIssue]) -> String {
        let preview = issues
            .prefix(3)
            .map { issue in "- \(issue.message)" }
            .joined(separator: "\n")
        guard !preview.isEmpty else {
            return message
        }
        if issues.count > 3 {
            return "\(message)\n\n\(preview)\n..."
        }
        return "\(message)\n\n\(preview)"
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

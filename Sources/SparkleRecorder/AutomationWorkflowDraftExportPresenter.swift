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
                title: String(localized: "Workflow draft export blocked", table: "Automation"),
                message: String(localized: "Resolve workflow validation errors before exporting an AI-editable draft.", table: "Automation"),
                issues: result.issues
            )
            return
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export AI Draft", table: "Common")
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
                    title: String(localized: "Export failed", table: "Common"),
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
            format: String(localized: "Exported %@ with %d tasks and %d dependencies to %@.", table: "Automation"),
            result.workflowName,
            result.document.workflow.tasks.count,
            result.document.workflow.dependencies.count,
            url.lastPathComponent
        )

        let warningSummary: String
        if warningIssues.isEmpty {
            warningSummary = String(localized: "Open the exported draft with AI Draft preview to validate or edit it before importing.", table: "EditorUX")
        } else {
            warningSummary = String(
                format: String(localized: "%d export warnings need review before re-import.", table: "EditorUX"),
                warningIssues.count
            )
        }

        showIssues(
            title: String(localized: "Workflow draft exported", table: "Automation"),
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
        alert.addButton(withTitle: String(localized: "OK", table: "Common"))
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

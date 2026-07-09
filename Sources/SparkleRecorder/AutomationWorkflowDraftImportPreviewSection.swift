import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowDraftImportPreviewSection: View {
    let preview: AutomationWorkflowDraftPreviewProjection.ImportPreview?

    var body: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: String(localized: "IMPORT DRY-RUN", table: "Automation"),
                    count: preview.taskCount
                )

                statusRow(preview)
                summaryRow(preview)

                if !preview.macroResolutionRows.isEmpty {
                    subsectionTitle(String(localized: "MACRO RESOLUTION", table: "EditorUX"))
                    ForEach(preview.macroResolutionRows) { row in
                        macroResolutionRow(row)
                    }
                }

                if !preview.taskIDRows.isEmpty {
                    subsectionTitle(String(localized: "TASK ID MAP", table: "Automation"))
                    ForEach(preview.taskIDRows) { row in
                        idMapRow(row)
                    }
                }

                if !preview.dependencyIDRows.isEmpty {
                    subsectionTitle(String(localized: "DEPENDENCY ID MAP", table: "Automation"))
                    ForEach(preview.dependencyIDRows) { row in
                        idMapRow(row)
                    }
                }

                if !preview.issueRows.isEmpty || !preview.workflowIssueRows.isEmpty {
                    subsectionTitle(String(localized: "IMPORT ISSUES", table: "Common"))
                    ForEach(preview.issueRows) { row in
                        importIssueRow(row)
                    }
                    ForEach(preview.workflowIssueRows) { row in
                        workflowIssueRow(row)
                    }
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
        }
    }

    private func statusRow(_ preview: AutomationWorkflowDraftPreviewProjection.ImportPreview) -> some View {
        HStack(spacing: 8) {
            Image(systemName: preview.isImportable ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(preview.isImportable ? Brand.libraryGreen : Brand.red500)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(preview.statusLabel)
                    .font(.caption)
                    .bold()
                Text(preview.workflowName ?? String(localized: "No compiled workflow", table: "Automation"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let workflowID = preview.workflowID {
                Text(String(workflowID.uuidString.prefix(8)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(rowBackground(tint: preview.isImportable ? Brand.libraryGreen : Brand.red500))
        .accessibilityElement(children: .combine)
    }

    private func summaryRow(_ preview: AutomationWorkflowDraftPreviewProjection.ImportPreview) -> some View {
        HStack(spacing: 8) {
            summaryPill(
                title: String(localized: "Compiled tasks", table: "Automation"),
                value: "\(preview.taskCount)",
                systemImage: "square.stack.3d.up"
            )
            summaryPill(
                title: String(localized: "Compiled edges", table: "Common"),
                value: "\(preview.dependencyCount)",
                systemImage: "arrow.triangle.branch"
            )
            summaryPill(
                title: String(localized: "Resolved macros", table: "EditorUX"),
                value: "\(preview.macroResolutionRows.filter(\.isResolved).count)",
                systemImage: "record.circle"
            )
            summaryPill(
                title: String(localized: "Import issues", table: "Common"),
                value: "\(preview.issueRows.count + preview.workflowIssueRows.count)",
                systemImage: "exclamationmark.circle"
            )
        }
    }

    private func macroResolutionRow(
        _ row: AutomationWorkflowDraftPreviewProjection.ImportMacroResolutionRow
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.isResolved ? "link.circle" : "questionmark.circle")
                .foregroundStyle(row.isResolved ? Brand.libraryGreen : Brand.sigAmber)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.taskKey)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Text(row.macroName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(row.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let macroID = row.macroID {
                Text(String(macroID.uuidString.prefix(8)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(rowBackground(tint: row.isResolved ? Brand.libraryGreen : Brand.sigAmber))
        .accessibilityElement(children: .combine)
    }

    private func idMapRow(_ row: AutomationWorkflowDraftPreviewProjection.ImportIDRow) -> some View {
        HStack(spacing: 8) {
            Text(row.key)
                .font(.caption.monospaced())
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(row.shortID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(rowBackground())
        .accessibilityElement(children: .combine)
    }

    private func importIssueRow(_ row: AutomationWorkflowDraftPreviewProjection.IssueRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(row.severity.importTint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.code)
                        .font(.caption)
                        .bold()
                    if let subject = row.subject {
                        Text(subject)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(row.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(rowBackground(tint: row.severity.importTint))
        .accessibilityElement(children: .combine)
    }

    private func workflowIssueRow(
        _ row: AutomationWorkflowDraftPreviewProjection.WorkflowIssueRow
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.code)
                .font(.caption)
                .bold()
            Text(row.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(tint: Brand.red500))
        .accessibilityElement(children: .combine)
    }

    private func subsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .bold()
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func summaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.caption.monospacedDigit())
                .bold()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground())
    }

    private func rowBackground(tint: Color? = nil) -> some View {
        let accent = tint ?? Color.primary
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(accent.opacity(tint == nil ? 0.035 : 0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(tint == nil ? 0.08 : 0.18), lineWidth: 0.6)
            )
    }
}

private extension AutomationWorkflowDraftPreviewProjection.Severity {
    var importTint: Color {
        switch self {
        case .error:
            return Brand.red500
        case .warning:
            return Brand.sigAmber
        }
    }
}

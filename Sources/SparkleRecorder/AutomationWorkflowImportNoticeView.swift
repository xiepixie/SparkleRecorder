import SwiftUI

struct AutomationWorkflowImportNoticeView: View {
    let notice: AutomationWorkflowImportNoticeState
    let onUndo: () -> Void
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.isReplacement ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                .foregroundStyle(Brand.libraryGreen)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.isReplacement ? String(localized: "Workflow replaced", table: "Automation") : String(localized: "Workflow imported", table: "Automation"))
                    .font(.caption)
                    .bold()
                Text(detailLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(undoButtonTitle, systemImage: undoButtonImage, action: onUndo)
                .buttonStyle(.borderless)
                .help(undoButtonTitle)

            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .buttonStyle(.borderless)
                .help(String(localized: "Refresh automation projection", table: "Automation"))

            Button("Dismiss import notice", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help(String(localized: "Dismiss import notice", table: "Common"))
                .accessibilityLabel(String(localized: "Dismiss import notice", table: "Common"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.libraryGreen.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Brand.libraryGreen.opacity(0.2), lineWidth: 0.7)
                )
        )
    }

    private var detailLabel: String {
        String(
            format: String(localized: "%@, %d tasks, %d dependencies", table: "Automation"),
            notice.workflowName,
            notice.taskCount,
            notice.dependencyCount
        )
    }

    private var undoButtonTitle: String {
        notice.isReplacement
            ? String(localized: "Restore Previous", table: "Common")
            : String(localized: "Undo Import", table: "Common")
    }

    private var undoButtonImage: String {
        notice.isReplacement ? "clock.arrow.circlepath" : "arrow.uturn.backward"
    }
}

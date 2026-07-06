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
                Text(notice.isReplacement ? NSLocalizedString("Workflow replaced", comment: "") : NSLocalizedString("Workflow imported", comment: ""))
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
                .help(NSLocalizedString("Refresh automation projection", comment: ""))

            Button("Dismiss import notice", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help(NSLocalizedString("Dismiss import notice", comment: ""))
                .accessibilityLabel(NSLocalizedString("Dismiss import notice", comment: ""))
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
            format: NSLocalizedString("%@, %d tasks, %d dependencies", comment: ""),
            notice.workflowName,
            notice.taskCount,
            notice.dependencyCount
        )
    }

    private var undoButtonTitle: String {
        notice.isReplacement
            ? NSLocalizedString("Restore Previous", comment: "")
            : NSLocalizedString("Undo Import", comment: "")
    }

    private var undoButtonImage: String {
        notice.isReplacement ? "clock.arrow.circlepath" : "arrow.uturn.backward"
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowTaskRowView: View {
    let task: AutomationTask
    let position: Int
    let taskCount: Int
    var isPreviewDragSource: Bool = false
    let onSelectTask: (UUID) -> Void
    let onMoveTask: (UUID, AutomationWorkflowTaskMoveDirection) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: selectTask) {
                Label(task.name, systemImage: systemImage)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Open task details", table: "Common"))

            HStack(spacing: 2) {
                if isPreviewDragSource {
                    Label(String(localized: "Moving", table: "Common"), systemImage: "arrow.up.and.down")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.libraryGreen)
                        .help(String(localized: "Task is being reordered", table: "Common"))
                }

                moveButton(
                    direction: .up,
                    title: String(localized: "Move task up", table: "Automation"),
                    systemImage: "chevron.up",
                    isDisabled: position == 0
                )
                moveButton(
                    direction: .down,
                    title: String(localized: "Move task down", table: "Automation"),
                    systemImage: "chevron.down",
                    isDisabled: position >= taskCount - 1
                )
            }
        }
        .padding(8)
        .automationSubsurface(
            cornerRadius: 8,
            tint: isPreviewDragSource ? Brand.libraryGreen : nil,
            isActive: isPreviewDragSource
        )
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: AutomationTaskDragPayload.string(for: task.id) as NSString)
        }
        .accessibilityElement(children: .contain)
    }

    private var systemImage: String {
        switch task.kind {
        case .macro:
            return "play.rectangle"
        case .condition:
            return "diamond"
        case .delay:
            return "timer"
        case .notification:
            return "bell"
        }
    }

    private func selectTask() {
        onSelectTask(task.id)
    }

    private func moveButton(
        direction: AutomationWorkflowTaskMoveDirection,
        title: String,
        systemImage: String,
        isDisabled: Bool
    ) -> some View {
        Button(title, systemImage: systemImage) {
            onMoveTask(task.id, direction)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(width: 22, height: 22)
        .disabled(isDisabled)
        .help(title)
    }
}

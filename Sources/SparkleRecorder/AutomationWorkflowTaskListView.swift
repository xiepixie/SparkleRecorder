import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowTaskListView: View {
    let tasks: [AutomationTask]
    var previewState: AutomationWorkflowTaskListPreviewState?
    let onSelectTask: (UUID) -> Void
    let onInsertMacroTask: (UUID, Int) -> Void
    let onMoveTask: (UUID, Int) -> Void

    @State private var activeInsertionIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("TASKS", comment: ""),
                count: tasks.count
            )

            if tasks.isEmpty {
                AutomationWorkflowTaskEmptyDropView(
                    isActive: activeInsertionIndex == 0,
                    onTargetChanged: { updateInsertionTarget(0, isTargeted: $0) },
                    onDropMacro: { macroID in
                        insertMacroTask(macroID, at: 0)
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    AutomationWorkflowTaskInsertionDropTarget(
                        index: 0,
                        activeInsertionIndex: $activeInsertionIndex,
                        onDropMacro: insertMacroTask,
                        onDropTask: moveTask
                    )

                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        AutomationWorkflowTaskRowView(
                            task: task,
                            position: index,
                            taskCount: tasks.count,
                            isPreviewDragSource: previewState?.draggedTaskID == task.id,
                            onSelectTask: onSelectTask,
                            onMoveTask: moveTaskByButton
                        )

                        AutomationWorkflowTaskInsertionDropTarget(
                            index: index + 1,
                            activeInsertionIndex: $activeInsertionIndex,
                            onDropMacro: insertMacroTask,
                            onDropTask: moveTask
                        )
                    }
                }
            }
        }
        .padding(8)
        .automationSubsurface(cornerRadius: 10)
        .onAppear(perform: applyPreviewState)
        .onChange(of: previewState) {
            applyPreviewState()
        }
    }

    private func applyPreviewState() {
        if let previewState {
            activeInsertionIndex = min(max(0, previewState.insertionIndex), tasks.count)
        }
    }

    private func updateInsertionTarget(_ index: Int, isTargeted: Bool) {
        if isTargeted {
            activeInsertionIndex = index
        } else if activeInsertionIndex == index {
            activeInsertionIndex = nil
        }
    }

    private func insertMacroTask(_ macroID: UUID, at index: Int) {
        activeInsertionIndex = nil
        onInsertMacroTask(macroID, index)
    }

    private func moveTask(_ taskID: UUID, to index: Int) {
        activeInsertionIndex = nil
        onMoveTask(taskID, index)
    }

    private func moveTaskByButton(_ taskID: UUID, _ direction: AutomationWorkflowTaskMoveDirection) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        switch direction {
        case .up:
            moveTask(taskID, to: max(0, index - 1))
        case .down:
            moveTask(taskID, to: min(tasks.count, index + 2))
        }
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowSettingsView: View {
    let workflow: AutomationWorkflow
    let status: AutomationDisplayStatus
    let statusDetail: String
    let nextScheduledOccurrence: Date?
    let nextScheduledTaskName: String?
    let workflowProjection: AutomationWorkflowProjection?
    var taskListPreviewState: AutomationWorkflowTaskListPreviewState?
    let onInsertMacroTask: (UUID, Int) -> Void
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: (AutomationWorkflow) -> Void
    let onExportWorkflowDraft: (AutomationWorkflow) -> Void
    let onShareWorkflowPackage: (AutomationWorkflow) -> Void
    let onDeleteWorkflow: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var nameDraft = ""
    @State private var isConfirmingDeleteWorkflow = false

    var body: some View {
        Form {
            Section {
                TextField(NSLocalizedString("Workflow Name", comment: ""), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveWorkflowName)

                HStack {
                    Spacer()
                    Button(NSLocalizedString("Save Workflow", comment: "")) {
                        saveWorkflowName()
                    }
                    .disabled(trimmedName.isEmpty || trimmedName == workflow.name)
                }
            } header: {
                Text(NSLocalizedString("General", comment: ""))
            }

            Section {
                HStack {
                    Label(status.label, systemImage: status.systemImage)
                        .foregroundStyle(status.tint)
                    Spacer()
                    Text(statusDetail)
                        .foregroundStyle(.secondary)
                }

                if let nextScheduledOccurrence {
                    HStack {
                        Label(NSLocalizedString("Next Schedule", comment: ""), systemImage: "clock")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(nextScheduledOccurrence, style: .time)
                            if let name = nextScheduledTaskName {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Status", comment: ""))
            }

            Section {
                Button(action: onImportWorkflowPackage) {
                    Label(NSLocalizedString("Import Workflow Package", comment: ""), systemImage: "square.and.arrow.down")
                }
                
                Button(action: { onExportWorkflowPackage(workflow) }) {
                    Label(NSLocalizedString("Export Workflow Package", comment: ""), systemImage: "square.and.arrow.up")
                }
                
                Button(action: { onExportWorkflowDraft(workflow) }) {
                    Label(NSLocalizedString("Export AI Draft", comment: ""), systemImage: "doc.badge.gearshape")
                }
                .help(NSLocalizedString("Export AI-editable draft JSON", comment: ""))
                
                Button(action: { onShareWorkflowPackage(workflow) }) {
                    Label(NSLocalizedString("Share Workflow", comment: ""), systemImage: "square.and.arrow.up.on.square")
                }
            } header: {
                Text(NSLocalizedString("Data", comment: ""))
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDeleteWorkflow = true
                } label: {
                    Label(NSLocalizedString("Delete Workflow", comment: ""), systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } header: {
                Text(NSLocalizedString("Danger Zone", comment: ""))
            }
            
            Section {
                AutomationWorkflowTaskListView(
                    tasks: workflow.tasks,
                    previewState: taskListPreviewState,
                    onSelectTask: onSelectTask,
                    onInsertMacroTask: onInsertMacroTask,
                    onMoveTask: moveTask
                )
                .frame(minHeight: 200)
            } header: {
                Text(NSLocalizedString("Task List Overview", comment: ""))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: 800)
        .onAppear(perform: resetDraft)
        .onChange(of: workflow.id) { resetDraft() }
        .onChange(of: workflow.name) { resetDraft() }
        .alert(deleteWorkflowTitle, isPresented: $isConfirmingDeleteWorkflow) {
            Button(NSLocalizedString("Delete", comment: ""), role: .destructive, action: deleteWorkflow)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(deleteWorkflowMessage)
        }
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetDraft() {
        nameDraft = workflow.name
    }

    private func saveWorkflowName() {
        guard !trimmedName.isEmpty, trimmedName != workflow.name else {
            return
        }
        var updated = workflow
        updated.name = trimmedName
        onAction(.upsertWorkflow(updated, at: Date()))
    }

    private func moveTask(_ taskID: UUID, to insertionIndex: Int) {
        guard let currentIndex = workflow.tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        var updated = workflow
        var task = updated.tasks.remove(at: currentIndex)
        let rawIndex = min(max(0, insertionIndex), workflow.tasks.count)
        let adjustedIndex = currentIndex < rawIndex ? rawIndex - 1 : rawIndex
        let targetIndex = min(max(0, adjustedIndex), updated.tasks.count)

        guard targetIndex != currentIndex else {
            return
        }

        if let graphPosition = graphPositionForMovedTask(
            in: updated.tasks,
            targetIndex: targetIndex,
            fallback: task.graphPosition
        ) {
            task.graphPosition = graphPosition
        }
        updated.tasks.insert(task, at: targetIndex)
        onAction(.upsertWorkflow(updated, at: Date()))
    }

    private func graphPositionForMovedTask(
        in remainingTasks: [AutomationTask],
        targetIndex: Int,
        fallback: AutomationGraphPoint?
    ) -> AutomationGraphPoint? {
        guard let workflowProjection else {
            return fallback
        }

        let nodesByTaskID = Dictionary(uniqueKeysWithValues: workflowProjection.nodes.map { ($0.taskID, $0) })
        let previousTask = targetIndex > 0 ? remainingTasks[targetIndex - 1] : nil
        let nextTask = targetIndex < remainingTasks.count ? remainingTasks[targetIndex] : nil

        var xOffset: Double = 0
        var yOffset: Double = 0

        if let pTask = previousTask, let prevNode = nodesByTaskID[pTask.id] {
            xOffset = prevNode.position.x
            yOffset = prevNode.position.y + 100
        } else if let nTask = nextTask, let nextNode = nodesByTaskID[nTask.id] {
            xOffset = nextNode.position.x
            yOffset = nextNode.position.y - 100
        } else {
            return fallback
        }
        
        return AutomationGraphPoint(x: xOffset, y: yOffset)
    }

    private var deleteWorkflowTitle: String {
        String(format: NSLocalizedString("Delete Workflow \"%@\"?", comment: ""), workflow.name)
    }

    private var deleteWorkflowMessage: String {
        NSLocalizedString("This action cannot be undone. All tasks, conditions, and run history will be permanently deleted.", comment: "")
    }

    private func deleteWorkflow() {
        onDeleteWorkflow(workflow.id)
    }
}

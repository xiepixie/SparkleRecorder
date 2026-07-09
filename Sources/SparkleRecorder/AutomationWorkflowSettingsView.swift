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
                TextField(String(localized: "Workflow Name", table: "Common"), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveWorkflowName)

                HStack {
                    Spacer()
                    Button(String(localized: "Save Workflow", table: "Automation")) {
                        saveWorkflowName()
                    }
                    .disabled(trimmedName.isEmpty || trimmedName == workflow.name)
                }
            } header: {
                Text("General", tableName: "Common")
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
                        Label(String(localized: "Next Schedule", table: "Common"), systemImage: "clock")
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
                Text("Status", tableName: "Common")
            }

            Section {
                Button(action: onImportWorkflowPackage) {
                    Label(String(localized: "Import Workflow Package", table: "Automation"), systemImage: "square.and.arrow.down")
                }
                
                Button(action: { onExportWorkflowPackage(workflow) }) {
                    Label(String(localized: "Export Workflow Package", table: "Automation"), systemImage: "square.and.arrow.up")
                }
                
                Button(action: { onExportWorkflowDraft(workflow) }) {
                    Label(String(localized: "Export AI Draft", table: "Common"), systemImage: "doc.badge.gearshape")
                }
                .help(String(localized: "Export AI-editable draft JSON", table: "Common"))
                
                Button(action: { onShareWorkflowPackage(workflow) }) {
                    Label(String(localized: "Share Workflow", table: "Automation"), systemImage: "square.and.arrow.up.on.square")
                }
            } header: {
                Text("Data", tableName: "Common")
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDeleteWorkflow = true
                } label: {
                    Label(String(localized: "Delete Workflow", table: "Automation"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Danger Zone", tableName: "Common")
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
                Text("Task List Overview", tableName: "Common")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: 800)
        .onAppear(perform: resetDraft)
        .onChange(of: workflow.id) { resetDraft() }
        .onChange(of: workflow.name) { resetDraft() }
        .alert(deleteWorkflowTitle, isPresented: $isConfirmingDeleteWorkflow) {
            Button(String(localized: "Delete", table: "Common"), role: .destructive, action: deleteWorkflow)
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
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
        String(format: String(localized: "Delete Workflow \"%@\"?", table: "Common"), workflow.name)
    }

    private var deleteWorkflowMessage: String {
        String(localized: "This action cannot be undone. All tasks, conditions, and run history will be permanently deleted.", table: "Common")
    }

    private func deleteWorkflow() {
        onDeleteWorkflow(workflow.id)
    }
}

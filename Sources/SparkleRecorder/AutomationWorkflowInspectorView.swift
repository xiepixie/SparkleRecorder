import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowInspectorView: View {
    let workflow: AutomationWorkflow
    let status: AutomationDisplayStatus
    let statusDetail: String
    let nextScheduledOccurrence: Date?
    let nextScheduledTaskName: String?
    let workflowProjection: AutomationWorkflowProjection?
    let pendingDependencySourceID: UUID?
    var taskListPreviewState: AutomationWorkflowTaskListPreviewState?
    let onAddConditionTask: (AutomationConditionKind) -> Void
    let onInsertMacroTask: (UUID, Int) -> Void
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onCancelLink: () -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: (AutomationWorkflow) -> Void
    let onExportWorkflowDraft: (AutomationWorkflow) -> Void
    let onShareWorkflowPackage: (AutomationWorkflow) -> Void
    let onDeleteWorkflow: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var nameDraft = ""
    @State private var isConfirmingDeleteWorkflow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(NSLocalizedString("Workflow name", comment: ""), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveWorkflowName)

                Button(action: saveWorkflowName) {
                    Label("Save Workflow", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AutomationQuietButtonStyle(tint: Brand.libraryBlue))
                .disabled(trimmedName.isEmpty || trimmedName == workflow.name)

                HStack(spacing: 8) {
                    Label(status.label, systemImage: status.systemImage)
                        .font(.caption)
                        .bold()
                        .foregroundStyle(status.tint)
                    Text(statusDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(status.tint.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(status.tint.opacity(0.16), lineWidth: 0.6)
                        )
                )
                .accessibilityElement(children: .combine)

                AutomationNextScheduleBadge(
                    date: nextScheduledOccurrence,
                    title: NSLocalizedString("Next", comment: ""),
                    detail: nextScheduledTaskName
                )

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onImportWorkflowPackage) {
                        Label(NSLocalizedString("Import Workflow Package", comment: ""), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AutomationQuietButtonStyle())

                    Button(action: { onExportWorkflowPackage(workflow) }) {
                        Label(NSLocalizedString("Export Workflow", comment: ""), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AutomationQuietButtonStyle())

                    Button(action: { onExportWorkflowDraft(workflow) }) {
                        Label(NSLocalizedString("Export AI Draft", comment: ""), systemImage: "doc.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AutomationQuietButtonStyle())
                    .help(NSLocalizedString("Export AI-editable draft JSON", comment: ""))

                    Button(action: { onShareWorkflowPackage(workflow) }) {
                        Label(NSLocalizedString("Share Workflow", comment: ""), systemImage: "square.and.arrow.up.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AutomationQuietButtonStyle())

                    HStack {
                        Button("Delete Workflow", systemImage: "trash") {
                            isConfirmingDeleteWorkflow = true
                        }
                        .buttonStyle(AutomationQuietButtonStyle(isDestructive: true))
                        .help(NSLocalizedString("Delete Workflow", comment: ""))

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            if let pendingDependencySourceID,
               let source = workflow.task(id: pendingDependencySourceID) {
                HStack(spacing: 8) {
                    Label(source.name, systemImage: "link")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Cancel", systemImage: "xmark", action: onCancelLink)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .frame(width: 24, height: 24)
                }
                .padding(10)
                .glassSurface(cornerRadius: 10, tint: Brand.sigAmber, interactive: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("ADD CONDITION", comment: "")
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        addConditionButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            manualApprovalButton
                            externalSignalButton
                        }
                        HStack(spacing: 8) {
                            screenTextButton
                            visualWaitButton
                        }
                    }
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            AutomationWorkflowTaskListView(
                tasks: workflow.tasks,
                previewState: taskListPreviewState,
                onSelectTask: onSelectTask,
                onInsertMacroTask: onInsertMacroTask,
                onMoveTask: moveTask
            )

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("DEPENDENCIES", comment: ""),
                    count: workflow.dependencies.count
                )

                ForEach(workflow.dependencies) { dependency in
                    Button {
                        onSelectDependency(dependency.id)
                    } label: {
                        HStack(spacing: 8) {
                            Label(dependencyTitle(dependency), systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .onAppear(perform: resetDraft)
        .onChange(of: workflow.id) {
            resetDraft()
        }
        .onChange(of: workflow.name) {
            resetDraft()
        }
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

    @ViewBuilder
    private var addConditionButtons: some View {
        manualApprovalButton
        externalSignalButton
        screenTextButton
        visualWaitButton
    }

    private var manualApprovalButton: some View {
        Button("Manual approval", systemImage: "hand.raised.fill") {
            onAddConditionTask(.manualApproval)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var externalSignalButton: some View {
        Button("External signal", systemImage: "antenna.radiowaves.left.and.right") {
            onAddConditionTask(.externalSignal(NSLocalizedString("Ready", comment: "")))
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var screenTextButton: some View {
        Button("Screen text", systemImage: "text.viewfinder") {
            onAddConditionTask(.ocrText(AutomationOCRCondition(text: "")))
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var visualWaitButton: some View {
        Button("Visual wait", systemImage: "viewfinder.rectangular") {
            onAddConditionTask(.visual(AutomationVisualCondition(type: .regionChanged)))
        }
        .buttonStyle(AutomationQuietButtonStyle())
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
        let previousNode = previousTask.flatMap { nodesByTaskID[$0.id] }
        let nextNode = nextTask.flatMap { nodesByTaskID[$0.id] }
        let gap = workflowProjection.nodeSize.height + 48

        switch (previousNode, nextNode) {
        case (.some(let previous), .some(let next)):
            return AutomationGraphPoint(
                x: min(previous.position.x, next.position.x),
                y: max(0, (previous.position.y + next.position.y) / 2)
            )
        case (.some(let previous), .none):
            return AutomationGraphPoint(
                x: previous.position.x,
                y: previous.position.y + gap
            )
        case (.none, .some(let next)):
            return AutomationGraphPoint(
                x: next.position.x,
                y: max(0, next.position.y - gap)
            )
        case (.none, .none):
            return fallback
        }
    }

    private var deleteWorkflowTitle: String {
        String(format: NSLocalizedString("Delete %@?", comment: ""), workflow.name)
    }

    private var deleteWorkflowMessage: String {
        String(
            format: NSLocalizedString("This removes the workflow with %d tasks and %d dependencies. Saved macros stay in your macro library.", comment: ""),
            workflow.tasks.count,
            workflow.dependencies.count
        )
    }

    private func deleteWorkflow() {
        onDeleteWorkflow(workflow.id)
    }

    private func dependencyTitle(_ dependency: AutomationDependency) -> String {
        let from = workflow.task(id: dependency.fromTaskID)?.name ?? NSLocalizedString("Missing task", comment: "")
        let to = workflow.task(id: dependency.toTaskID)?.name ?? NSLocalizedString("Missing task", comment: "")
        return "\(from) -> \(to)"
    }
}

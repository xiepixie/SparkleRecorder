import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowInspectorView: View {
    let workflow: AutomationWorkflow
    let pendingDependencySourceID: UUID?
    let onAddConditionTask: (AutomationConditionKind) -> Void
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onCancelLink: () -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: (AutomationWorkflow) -> Void
    let onShareWorkflowPackage: (AutomationWorkflow) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var nameDraft = ""

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
                .buttonStyle(.bordered)
                .disabled(trimmedName.isEmpty || trimmedName == workflow.name)

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onImportWorkflowPackage) {
                        Label(NSLocalizedString("Import Workflow Package", comment: ""), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { onExportWorkflowPackage(workflow) }) {
                        Label(NSLocalizedString("Export Workflow", comment: ""), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { onShareWorkflowPackage(workflow) }) {
                        Label(NSLocalizedString("Share Workflow", comment: ""), systemImage: "square.and.arrow.up.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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

                HStack(spacing: 8) {
                    Button("Manual approval", systemImage: "hand.raised.fill") {
                        onAddConditionTask(.manualApproval)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.sigAmber)

                    Button("External signal", systemImage: "antenna.radiowaves.left.and.right") {
                        onAddConditionTask(.externalSignal(NSLocalizedString("Ready", comment: "")))
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.sigTeal)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("TASKS", comment: ""),
                    count: workflow.tasks.count
                )

                ForEach(workflow.tasks) { task in
                    Button {
                        onSelectTask(task.id)
                    } label: {
                        Label(task.name, systemImage: task.systemImage)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }

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

    private func dependencyTitle(_ dependency: AutomationDependency) -> String {
        let from = workflow.task(id: dependency.fromTaskID)?.name ?? NSLocalizedString("Missing task", comment: "")
        let to = workflow.task(id: dependency.toTaskID)?.name ?? NSLocalizedString("Missing task", comment: "")
        return "\(from) -> \(to)"
    }
}

private extension AutomationTask {
    var systemImage: String {
        switch kind {
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
}

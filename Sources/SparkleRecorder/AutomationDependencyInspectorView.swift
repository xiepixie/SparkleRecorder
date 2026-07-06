import SwiftUI
import SparkleRecorderCore

struct AutomationDependencyInspectorView: View {
    let workflow: AutomationWorkflow
    let dependency: AutomationDependency
    let onSelectTask: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var triggerDraft: AutomationDependencyTriggerDraft = .onSuccess
    @State private var delaySeconds = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(title: NSLocalizedString("DEPENDENCY", comment: ""))

                AutomationInspectorReferenceButton(
                    title: taskName(dependency.fromTaskID),
                    systemImage: "circle",
                    tint: Brand.libraryBlue,
                    action: { onSelectTask(dependency.fromTaskID) }
                )

                AutomationInspectorReferenceButton(
                    title: taskName(dependency.toTaskID),
                    systemImage: "arrow.down.circle",
                    tint: Brand.sigTeal,
                    action: { onSelectTask(dependency.toTaskID) }
                )
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 8) {
                Picker(NSLocalizedString("Trigger", comment: ""), selection: $triggerDraft) {
                    ForEach(AutomationDependencyTriggerDraft.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent(NSLocalizedString("Delay", comment: "")) {
                    TextField(NSLocalizedString("Seconds", comment: ""), value: $delaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            HStack(spacing: 8) {
                Button("Save Dependency", systemImage: "checkmark", action: saveDependency)
                    .buttonStyle(.bordered)

                Button("Delete Dependency", systemImage: "trash", role: .destructive, action: deleteDependency)
                    .buttonStyle(.bordered)
                    .tint(Brand.red500)
            }
        }
        .onAppear(perform: resetDraft)
        .onChange(of: dependency.id) {
            resetDraft()
        }
        .onChange(of: dependency) {
            resetDraft()
        }
    }

    private func resetDraft() {
        triggerDraft = AutomationDependencyTriggerDraft.draft(for: dependency.trigger)
        delaySeconds = dependency.delay
    }

    private func saveDependency() {
        var updated = dependency
        updated.trigger = triggerDraft.trigger
        updated.delay = max(0, delaySeconds)
        onAction(.upsertDependency(workflowID: workflow.id, dependency: updated, at: Date()))
    }

    private func deleteDependency() {
        onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? NSLocalizedString("Missing task", comment: "")
    }

}

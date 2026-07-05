import SwiftUI
import SparkleRecorderCore

struct AutomationDependencyInspectorView: View {
    let workflow: AutomationWorkflow
    let dependency: AutomationDependency
    let onSelectTask: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var triggerMode = "onSuccess"
    @State private var delaySeconds = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(title: NSLocalizedString("DEPENDENCY", comment: ""))

                Button {
                    onSelectTask(dependency.fromTaskID)
                } label: {
                    Label(taskName(dependency.fromTaskID), systemImage: "circle")
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(8)
                .controlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: false)

                Button {
                    onSelectTask(dependency.toTaskID)
                } label: {
                    Label(taskName(dependency.toTaskID), systemImage: "arrow.down.circle")
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(8)
                .controlSurface(cornerRadius: 8, tint: Brand.sigTeal, isActive: false)
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)

            VStack(alignment: .leading, spacing: 8) {
                Picker(NSLocalizedString("Trigger", comment: ""), selection: $triggerMode) {
                    Text(NSLocalizedString("Success", comment: "")).tag("onSuccess")
                    Text(NSLocalizedString("Failure", comment: "")).tag("onFailure")
                    Text(NSLocalizedString("Timeout", comment: "")).tag("onTimeout")
                    Text(NSLocalizedString("Cancelled", comment: "")).tag("onCancelled")
                    Text(NSLocalizedString("Condition matched", comment: "")).tag("onConditionMatched")
                    Text(NSLocalizedString("Condition not matched", comment: "")).tag("onConditionNotMatched")
                    Text(NSLocalizedString("Always", comment: "")).tag("always")
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
                    .buttonStyle(.borderless)
                    .controlSurface(cornerRadius: 8, tint: Brand.libraryBlue, isActive: false)

                Button("Delete Dependency", systemImage: "trash", role: .destructive, action: deleteDependency)
                    .buttonStyle(.borderless)
                    .controlSurface(cornerRadius: 8, tint: Brand.red500, isActive: false)
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
        triggerMode = triggerTag(for: dependency.trigger)
        delaySeconds = dependency.delay
    }

    private func saveDependency() {
        var updated = dependency
        updated.trigger = trigger()
        updated.delay = max(0, delaySeconds)
        onAction(.upsertDependency(workflowID: workflow.id, dependency: updated, at: Date()))
    }

    private func deleteDependency() {
        onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? NSLocalizedString("Missing task", comment: "")
    }

    private func triggerTag(for trigger: AutomationDependencyTrigger) -> String {
        switch trigger {
        case .onSuccess:
            return "onSuccess"
        case .onFailure:
            return "onFailure"
        case .onTimeout:
            return "onTimeout"
        case .onCancelled:
            return "onCancelled"
        case .onConditionMatched:
            return "onConditionMatched"
        case .onConditionNotMatched:
            return "onConditionNotMatched"
        case .always:
            return "always"
        case .onOutcome(let predicate):
            return predicate.rawValue
        }
    }

    private func trigger() -> AutomationDependencyTrigger {
        switch triggerMode {
        case "onFailure":
            return .onFailure
        case "onTimeout":
            return .onTimeout
        case "onCancelled":
            return .onCancelled
        case "onConditionMatched":
            return .onConditionMatched
        case "onConditionNotMatched":
            return .onConditionNotMatched
        case "always":
            return .always
        default:
            return .onSuccess
        }
    }
}

import SparkleRecorderCore
import SwiftUI

struct AutomationTaskAdvancedEditorView: View {
    let task: AutomationTask
    @Binding var executionDraft: AutomationTaskExecutionDraft
    @Binding var conditionDraft: AutomationTaskConditionDraft
    @Binding var resourceDraft: AutomationTaskResourceDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            executionPolicySection
            resourceSection
        }
    }

    private var executionPolicySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "EXECUTION POLICY", table: "Common"))

            Toggle(String(localized: "Time limit", table: "Common"), isOn: $executionDraft.hasTimeout)
                .toggleStyle(.switch)

            if executionDraft.hasTimeout {
                numericField(
                    String(localized: "Seconds", table: "Common"),
                    value: $executionDraft.timeout,
                    width: 78
                )
            }

            LabeledContent(String(localized: "Retry attempts", table: "Common")) {
                TextField(
                    String(localized: "Count", table: "Common"),
                    value: $executionDraft.retryAttempts,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
            }

            if isConditionTask {
                Divider().opacity(0.5)
                conditionWaitPolicyEditor
            }
        }
        .padding(.vertical, 8)
    }

    private var conditionWaitPolicyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Condition wait", table: "Automation"), systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(String(localized: "Enable Timeout", table: "Common"), isOn: $conditionDraft.hasTimeout)
                .toggleStyle(.switch)

            if conditionDraft.hasTimeout {
                numericField(
                    String(localized: "Timeout (s)", table: "Common"),
                    value: $conditionDraft.timeout,
                    width: 78
                )
            }

            numericField(
                String(localized: "Polling (s)", table: "Common"),
                value: $conditionDraft.pollingInterval,
                width: 78
            )
        }
    }

    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "RESOURCES", table: "Common"))
            resourcePolicyEditor
        }
        .padding(.vertical, 8)
    }

    private var resourcePolicyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Resource policy", table: "Common"), systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(resourceOptions, id: \.resource) { option in
                    Toggle(isOn: resourceBinding(option.resource)) {
                        Label(option.title, systemImage: option.systemImage)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(requiredResources.contains(option.resource))
                }
            }

            if !requiredResources.isEmpty {
                Text("Required resources are locked by this task type.", tableName: "Automation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(String(localized: "Priority", table: "Common"), selection: $resourceDraft.priority) {
                ForEach(resourcePriorityOptions, id: \.self) { priority in
                    Text(resourcePriorityTitle(priority)).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .disabled(draftedResourceRequirement.resources.isEmpty)

            Toggle(
                String(localized: "Max resource wait", table: "EditorUX"),
                isOn: $resourceDraft.hasMaxWaitDuration
            )
            .toggleStyle(.switch)
            .disabled(draftedResourceRequirement.resources.isEmpty)

            if resourceDraft.hasMaxWaitDuration, !draftedResourceRequirement.resources.isEmpty {
                numericField(
                    String(localized: "Wait (s)", table: "EditorUX"),
                    value: $resourceDraft.maxWaitDuration,
                    width: 78
                )
            }
        }
    }

    private var draftedResourceRequirement: AutomationResourceRequirement {
        resourceDraft.requirement(
            preserving: task.resourceRequirement,
            requiredResources: requiredResources
        )
    }

    private var requiredResources: Set<AutomationResource> {
        isConditionTask ? conditionDraft.requiredResources : []
    }

    private var resourceOptions: [(resource: AutomationResource, title: String, systemImage: String)] {
        [
            (.foregroundInput, resourceTitle(.foregroundInput), "keyboard"),
            (.screenCapture, resourceTitle(.screenCapture), "display"),
            (.accessibility, resourceTitle(.accessibility), "accessibility"),
            (.network, resourceTitle(.network), "network")
        ]
    }

    private var resourcePriorityOptions: [AutomationResourcePriority] {
        [.low, .normal, .high]
    }

    private func resourceBinding(_ resource: AutomationResource) -> Binding<Bool> {
        Binding(
            get: {
                resourceDraft.resources.contains(resource) || requiredResources.contains(resource)
            },
            set: { newValue in
                if newValue {
                    resourceDraft.resources.insert(resource)
                } else {
                    resourceDraft.resources.remove(resource)
                }
            }
        )
    }

    private func resourceTitle(_ resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return String(localized: "Needs mouse and keyboard", table: "Common")
        case .screenCapture:
            return String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .network:
            return String(localized: "Network", table: "Common")
        }
    }

    private func resourcePriorityTitle(_ priority: AutomationResourcePriority) -> String {
        switch priority {
        case .low:
            return String(localized: "Low", table: "Common")
        case .normal:
            return String(localized: "Normal", table: "Common")
        case .high:
            return String(localized: "High", table: "Common")
        }
    }

    private func numericField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private var isConditionTask: Bool {
        if case .condition = task.kind {
            return true
        }
        return false
    }
}

import Foundation
import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowDraftDependencyEditorView: View {
    let document: AutomationWorkflowDraftDocument
    let onApply: (AutomationWorkflowDraftDependencyEdit) -> Void

    @State private var selectedDependencyID = ""
    @State private var fromTaskKey = ""
    @State private var toTaskKey = ""
    @State private var trigger = "success"
    @State private var delaySeconds = 0.0
    @State private var enabled = true

    private let triggers = [
        "success",
        "failure",
        "timeout",
        "cancelled",
        "conditionMatched",
        "conditionNotMatched",
        "always"
    ]

    var body: some View {
        if !document.workflow.dependencies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: String(localized: "DRAFT DEPENDENCY EDIT", table: "Automation"),
                    count: document.workflow.dependencies.count
                )

                Picker(String(localized: "Dependency", table: "Automation"), selection: $selectedDependencyID) {
                    ForEach(Array(document.workflow.dependencies.enumerated()), id: \.offset) { _, dependency in
                        Text(dependencyTitle(for: dependency)).tag(displayKey(for: dependency))
                    }
                }
                .onChange(of: selectedDependencyID) {
                    loadSelectedDependency()
                }

                HStack(spacing: 8) {
                    Picker(String(localized: "From", table: "Common"), selection: $fromTaskKey) {
                        ForEach(document.workflow.tasks, id: \.key) { task in
                            Text(task.name ?? task.key).tag(task.key)
                        }
                    }
                    .frame(maxWidth: 180)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Picker(String(localized: "To", table: "Common"), selection: $toTaskKey) {
                        ForEach(document.workflow.tasks, id: \.key) { task in
                            Text(task.name ?? task.key).tag(task.key)
                        }
                    }
                    .frame(maxWidth: 180)

                    Picker(String(localized: "Trigger", table: "Automation"), selection: $trigger) {
                        ForEach(triggers, id: \.self) { trigger in
                            Text(triggerTitle(for: trigger)).tag(trigger)
                        }
                    }
                    .frame(maxWidth: 180)
                }

                HStack(spacing: 8) {
                    Label(String(localized: "Delay", table: "EditorUX"), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Delay", table: "EditorUX"), value: $delaySeconds, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)

                    Toggle(String(localized: "Enabled", table: "Common"), isOn: $enabled)
                        .font(.caption)
                        .toggleStyle(.checkbox)

                    Spacer(minLength: 0)

                    Button(String(localized: "Remove Edge", table: "Common"), systemImage: "trash", role: .destructive, action: removeDependency)
                        .buttonStyle(.bordered)
                        .disabled(selectedDependency == nil)

                    Button(String(localized: "Apply Dependency", table: "Automation"), systemImage: "checkmark", action: applyDependency)
                        .buttonStyle(.bordered)
                        .disabled(!canApplyDependency)
                }
            }
            .padding(10)
            .sectionSurface(cornerRadius: 10)
            .onAppear(perform: selectInitialDependencyIfNeeded)
            .onChange(of: document) {
                selectInitialDependencyIfNeeded()
            }
        }
    }

    private var selectedDependency: AutomationWorkflowDraftDependency? {
        document.workflow.dependencies.first { displayKey(for: $0) == selectedDependencyID }
    }

    private var canApplyDependency: Bool {
        selectedDependency != nil &&
            !fromTaskKey.isEmpty &&
            !toTaskKey.isEmpty &&
            fromTaskKey != toTaskKey &&
            !trigger.isEmpty
    }

    private func selectInitialDependencyIfNeeded() {
        if selectedDependency == nil {
            selectedDependencyID = document.workflow.dependencies.first.map(displayKey(for:)) ?? ""
        }
        loadSelectedDependency()
    }

    private func loadSelectedDependency() {
        guard let selectedDependency else {
            fromTaskKey = document.workflow.tasks.first?.key ?? ""
            toTaskKey = document.workflow.tasks.dropFirst().first?.key ?? fromTaskKey
            trigger = "success"
            delaySeconds = 0
            enabled = true
            return
        }

        fromTaskKey = selectedDependency.from
        toTaskKey = selectedDependency.to
        trigger = selectedDependency.trigger
        delaySeconds = selectedDependency.delaySeconds ?? 0
        enabled = selectedDependency.enabled ?? true
    }

    private func applyDependency() {
        guard canApplyDependency,
              let selectedDependency else {
            return
        }

        onApply(AutomationWorkflowDraftDependencyEdit(
            selector: selector(for: selectedDependency),
            from: fromTaskKey,
            to: toTaskKey,
            trigger: trigger,
            delaySeconds: max(0, delaySeconds),
            enabled: enabled,
            removesDependency: false
        ))
    }

    private func removeDependency() {
        guard let selectedDependency else {
            return
        }

        onApply(AutomationWorkflowDraftDependencyEdit(
            selector: selector(for: selectedDependency),
            from: selectedDependency.from,
            to: selectedDependency.to,
            trigger: selectedDependency.trigger,
            delaySeconds: selectedDependency.delaySeconds ?? 0,
            enabled: selectedDependency.enabled ?? true,
            removesDependency: true
        ))
    }

    private func selector(for dependency: AutomationWorkflowDraftDependency) -> AutomationWorkflowDraftDependencySelector {
        if let key = dependency.key?.trimmedForDraftDependencyEdit.nilIfEmptyForDraftDependencyEdit {
            return AutomationWorkflowDraftDependencySelector(key: key)
        }
        return AutomationWorkflowDraftDependencySelector(
            from: dependency.from,
            to: dependency.to,
            trigger: dependency.trigger
        )
    }

    private func displayKey(for dependency: AutomationWorkflowDraftDependency) -> String {
        dependency.key?.trimmedForDraftDependencyEdit.nilIfEmptyForDraftDependencyEdit
            ?? "\(dependency.from)->\(dependency.to):\(dependency.trigger)"
    }

    private func dependencyTitle(for dependency: AutomationWorkflowDraftDependency) -> String {
        "\(dependency.from) -> \(dependency.to) · \(triggerTitle(for: dependency.trigger))"
    }

    private func triggerTitle(for trigger: String) -> String {
        switch trigger {
        case "failure":
            return String(localized: "Failure", table: "Common")
        case "timeout":
            return String(localized: "Timeout", table: "Common")
        case "cancelled":
            return String(localized: "Cancelled", table: "Common")
        case "conditionMatched":
            return String(localized: "Condition matched", table: "Automation")
        case "conditionNotMatched":
            return String(localized: "Condition not matched", table: "Automation")
        case "always":
            return String(localized: "Always", table: "Common")
        default:
            return String(localized: "Success", table: "Common")
        }
    }
}

private extension String {
    var trimmedForDraftDependencyEdit: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForDraftDependencyEdit: String? {
        isEmpty ? nil : self
    }
}

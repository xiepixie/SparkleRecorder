import SwiftUI
import SparkleRecorderCore

struct AutomationDependencyInspectorView: View {
    let workflow: AutomationWorkflow
    let dependency: AutomationDependency
    let onSelectTask: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var triggerDraft: AutomationDependencyTriggerDraft = .onSuccess
    @State private var delaySeconds = 0.0
    @State private var usesRecognizedTimeDelay = false
    @State private var maximumRecognizedDelaySeconds = 86_400.0
    @State private var selectedTab: DependencyInspectorTab = .link

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabPicker

            switch selectedTab {
            case .link:
                linkTab
            case .timing:
                timingTab
            }

            actionFooter
        }
        .onAppear(perform: resetDraft)
        .onChange(of: dependency.id) {
            selectedTab = .link
            resetDraft()
        }
        .onChange(of: dependency) {
            resetDraft()
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DependencyInspectorTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(NSLocalizedString("Dependency section", comment: ""))
    }

    private var linkTab: some View {
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

            if let sourceConditionSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Label(NSLocalizedString("Source condition", comment: ""), systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(Brand.libraryBlue)
                    Text(sourceConditionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { onSelectTask(dependency.fromTaskID) }) {
                        Label(NSLocalizedString("Edit Source Condition", comment: ""), systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .automationSubsurface(cornerRadius: 8)
            }
        }
        .padding(.vertical, 8)
    }

    private var timingTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(title: NSLocalizedString("LINK TRIGGER", comment: ""))

            Picker(NSLocalizedString("Run when", comment: ""), selection: $triggerDraft) {
                ForEach(triggerOptions) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            LabeledContent(delayFieldTitle) {
                TextField(NSLocalizedString("Seconds", comment: ""), value: $delaySeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 86)
            }

            if sourceCanProvideDynamicDelay {
                Toggle(NSLocalizedString("Use recognized time", comment: ""), isOn: $usesRecognizedTimeDelay)
                    .toggleStyle(.checkbox)
                    .help(NSLocalizedString(
                        "Read a duration from the source condition evidence and use the delay field as fallback.",
                        comment: ""
                    ))

                if usesRecognizedTimeDelay {
                    LabeledContent(NSLocalizedString("Maximum wait (s)", comment: "")) {
                        TextField(
                            NSLocalizedString("Seconds", comment: ""),
                            value: $maximumRecognizedDelaySeconds,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var actionFooter: some View {
        HStack(spacing: 8) {
            Button("Save Dependency", systemImage: "checkmark", action: saveDependency)
                .buttonStyle(.bordered)

            Button("Delete Dependency", systemImage: "trash", role: .destructive, action: deleteDependency)
                .buttonStyle(.bordered)
                .tint(Brand.red500)
        }
    }

    private func resetDraft() {
        triggerDraft = AutomationDependencyTriggerDraft.draft(for: dependency.trigger)
        if !triggerOptions.contains(triggerDraft) {
            triggerDraft = triggerOptions.first ?? .onSuccess
        }
        if sourceCanProvideDynamicDelay,
           let dynamicDelay = dependency.dynamicDelay,
           dynamicDelay.source == .conditionEvidenceDuration {
            usesRecognizedTimeDelay = true
            delaySeconds = dynamicDelay.fallbackDelay ?? dependency.delay
            maximumRecognizedDelaySeconds = dynamicDelay.maximumDelay ?? 86_400
        } else {
            usesRecognizedTimeDelay = false
            delaySeconds = dependency.delay
            maximumRecognizedDelaySeconds = 86_400
        }
    }

    private func saveDependency() {
        var updated = dependency
        updated.trigger = triggerDraft.trigger
        updated.delay = max(0, delaySeconds)
        if sourceCanProvideDynamicDelay, usesRecognizedTimeDelay {
            updated.dynamicDelay = AutomationDependencyDynamicDelay(
                source: .conditionEvidenceDuration,
                fallbackDelay: max(0, delaySeconds),
                maximumDelay: max(1, maximumRecognizedDelaySeconds)
            )
        } else {
            updated.dynamicDelay = nil
        }
        onAction(.upsertDependency(workflowID: workflow.id, dependency: updated, at: Date()))
    }

    private func deleteDependency() {
        onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? NSLocalizedString("Missing task", comment: "")
    }

    private var triggerOptions: [AutomationDependencyTriggerDraft] {
        AutomationDependencyTriggerDraft.options(for: workflow.task(id: dependency.fromTaskID))
    }

    private var delayFieldTitle: String {
        usesRecognizedTimeDelay
            ? NSLocalizedString("Fallback (s)", comment: "")
            : NSLocalizedString("Delay", comment: "")
    }

    private var sourceCanProvideDynamicDelay: Bool {
        guard let sourceTask = workflow.task(id: dependency.fromTaskID),
              case .condition(let condition) = sourceTask.kind else {
            return false
        }
        switch condition.kind {
        case .ocrText, .visual:
            return true
        case .manualApproval, .externalSignal, .previousOutcome:
            return false
        }
    }

    private var sourceConditionSummary: String? {
        guard let sourceTask = workflow.task(id: dependency.fromTaskID),
              case .condition(let condition) = sourceTask.kind else {
            return nil
        }
        return conditionSummary(condition)
    }

    private func conditionSummary(_ condition: AutomationConditionSpec) -> String {
        switch condition.kind {
        case .manualApproval:
            return NSLocalizedString("Manual approval", comment: "")
        case .externalSignal(let signalName):
            let trimmed = signalName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return NSLocalizedString("External signal", comment: "")
            }
            return String(format: NSLocalizedString("External signal: %@", comment: ""), trimmed)
        case .ocrText(let ocr):
            let trimmed = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return NSLocalizedString("OCR text", comment: "")
            }
            return String(format: NSLocalizedString("OCR text: %@", comment: ""), trimmed)
        case .visual(let visual):
            return AutomationVisualConditionPresentation.title(for: visual.type)
        case .previousOutcome(let predicate):
            return outcomePredicateTitle(predicate)
        }
    }

    private func outcomePredicateTitle(_ predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .anyTerminal:
            return NSLocalizedString("Any terminal", comment: "")
        case .success:
            return NSLocalizedString("Success", comment: "")
        case .failure:
            return NSLocalizedString("Failure", comment: "")
        case .timeout:
            return NSLocalizedString("Timeout", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        }
    }

}

private enum DependencyInspectorTab: String, CaseIterable, Identifiable {
    case link
    case timing

    var id: Self { self }

    var title: String {
        switch self {
        case .link:
            return NSLocalizedString("Link", comment: "")
        case .timing:
            return NSLocalizedString("Timing", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .link:
            return "link"
        case .timing:
            return "timer"
        }
    }
}

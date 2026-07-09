import SwiftUI
import SparkleRecorderCore

struct AutomationTaskDependencyAuthoringView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    @State private var targetTaskID: UUID?
    @State private var triggerDraft: AutomationDependencyTriggerDraft = .onSuccess
    @State private var delaySeconds = 0.0
    @State private var usesRecognizedTimeDelay = false
    @State private var maximumRecognizedDelaySeconds = 86_400.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: String(localized: "DEPENDENCIES", table: "Common"),
                count: relatedDependencies.count
            )

            createDependencySection

            if !outgoingDependencies.isEmpty {
                dependencyGroup(
                    title: String(localized: "OUTGOING", table: "Common"),
                    dependencies: outgoingDependencies,
                    direction: .outgoing
                )
            }

            if !incomingDependencies.isEmpty {
                dependencyGroup(
                    title: String(localized: "INCOMING", table: "Common"),
                    dependencies: incomingDependencies,
                    direction: .incoming
                )
            }

            if relatedDependencies.isEmpty && connectTargets.isEmpty {
                Label(String(localized: "Add another task to create a link", table: "Automation"), systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear(perform: repairTargetSelection)
        .onChange(of: task.id) {
            repairTargetSelection()
        }
        .onChange(of: task.kind) {
            repairTargetSelection()
        }
        .onChange(of: workflow.tasks.map(\.id)) {
            repairTargetSelection()
        }
        .onChange(of: workflow.dependencies) {
            repairTargetSelection()
        }
    }

    @ViewBuilder
    private var createDependencySection: some View {
        if connectTargets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Connect to", table: "Common"), selection: targetBinding) {
                    ForEach(connectTargets) { target in
                        Text(target.name).tag(Optional(target.id))
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Picker(String(localized: "Run when", table: "Automation"), selection: $triggerDraft) {
                        ForEach(triggerOptions) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(delayFieldTitle, value: $delaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                }

                if sourceCanProvideDynamicDelay {
                    Toggle(String(localized: "Use recognized time", table: "Common"), isOn: $usesRecognizedTimeDelay)
                        .toggleStyle(.checkbox)
                        .help(String(localized: "Read a duration from the source condition evidence and use the delay field as fallback.", table: "Automation"))

                    if usesRecognizedTimeDelay {
                        LabeledContent(String(localized: "Maximum wait (s)", table: "EditorUX")) {
                            TextField(
                                String(localized: "Seconds", table: "Common"),
                                value: $maximumRecognizedDelaySeconds,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                        }
                    }
                }

                Button(action: createDependency) {
                    Label(String(localized: "Create Link", table: "Common"), systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AutomationQuietButtonStyle(tint: Brand.sigAmber))
                .disabled(targetBinding.wrappedValue == nil)
            }
            .padding(8)
            .automationSubsurface(cornerRadius: 8)
        }
    }

    private func dependencyGroup(
        title: String,
        dependencies: [AutomationDependency],
        direction: DependencyDirection
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2)
                .bold()
                .foregroundStyle(.secondary)

            ForEach(dependencies) { dependency in
                dependencyRow(dependency, direction: direction)
            }
        }
    }

    private func dependencyRow(
        _ dependency: AutomationDependency,
        direction: DependencyDirection
    ) -> some View {
        HStack(spacing: 7) {
            Button {
                onSelectDependency(dependency.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(for: dependency, direction: direction))
                        .font(.caption)
                        .bold()
                        .lineLimit(1)
                    Text(rowDetail(for: dependency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(String(localized: "Select task", table: "Automation"), systemImage: "arrow.up.right.square") {
                onSelectTask(direction.peerTaskID(for: dependency))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(String(localized: "Select task", table: "Automation"))

            Button(String(localized: "Delete Dependency", table: "Automation"), systemImage: "trash", role: .destructive) {
                onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .foregroundStyle(Brand.red500)
            .help(String(localized: "Delete Dependency", table: "Automation"))
        }
        .padding(8)
        .automationSubsurface(cornerRadius: 8)
    }

    private var targetBinding: Binding<UUID?> {
        Binding(
            get: { targetTaskID ?? connectTargets.first?.id },
            set: { targetTaskID = $0 }
        )
    }

    private var connectTargets: [AutomationTask] {
        workflow.tasks.filter { candidate in
            candidate.id != task.id
                && !workflow.dependencies.contains {
                    $0.fromTaskID == task.id && $0.toTaskID == candidate.id
                }
        }
    }

    private var outgoingDependencies: [AutomationDependency] {
        workflow.dependencies.filter { $0.fromTaskID == task.id }
    }

    private var incomingDependencies: [AutomationDependency] {
        workflow.dependencies.filter { $0.toTaskID == task.id }
    }

    private var relatedDependencies: [AutomationDependency] {
        outgoingDependencies + incomingDependencies
    }

    private var triggerOptions: [AutomationDependencyTriggerDraft] {
        AutomationDependencyTriggerDraft.options(for: task)
    }

    private var delayFieldTitle: String {
        usesRecognizedTimeDelay
            ? String(localized: "Fallback", table: "Common")
            : String(localized: "Delay", table: "EditorUX")
    }

    private var sourceCanProvideDynamicDelay: Bool {
        guard case .condition(let condition) = task.kind else {
            return false
        }
        switch condition.kind {
        case .ocrText, .visual:
            return true
        case .manualApproval, .externalSignal, .previousOutcome:
            return false
        }
    }

    private func createDependency() {
        guard let targetTaskID = targetBinding.wrappedValue else {
            return
        }

        let dependency = AutomationDependency(
            fromTaskID: task.id,
            toTaskID: targetTaskID,
            trigger: triggerDraft.trigger,
            delay: max(0, delaySeconds),
            dynamicDelay: createdDynamicDelay
        )
        onAction(.upsertDependency(workflowID: workflow.id, dependency: dependency, at: Date()))
        onSelectDependency(dependency.id)
        self.targetTaskID = nil
    }

    private func repairTargetSelection() {
        if let targetTaskID,
           connectTargets.contains(where: { $0.id == targetTaskID }) {
            repairTriggerSelection()
            return
        }
        targetTaskID = connectTargets.first?.id
        repairTriggerSelection()
    }

    private func repairTriggerSelection() {
        if !sourceCanProvideDynamicDelay {
            usesRecognizedTimeDelay = false
            maximumRecognizedDelaySeconds = 86_400
        }
        guard !triggerOptions.contains(triggerDraft) else {
            return
        }
        triggerDraft = triggerOptions.first ?? .onSuccess
    }

    private var createdDynamicDelay: AutomationDependencyDynamicDelay? {
        guard sourceCanProvideDynamicDelay, usesRecognizedTimeDelay else {
            return nil
        }
        return AutomationDependencyDynamicDelay(
            source: .conditionEvidenceDuration,
            fallbackDelay: max(0, delaySeconds),
            maximumDelay: max(1, maximumRecognizedDelaySeconds)
        )
    }

    private func rowTitle(for dependency: AutomationDependency, direction: DependencyDirection) -> String {
        let peerName = taskName(direction.peerTaskID(for: dependency))
        switch direction {
        case .outgoing:
            return String(format: String(localized: "To %@", table: "Common"), peerName)
        case .incoming:
            return String(format: String(localized: "From %@", table: "Common"), peerName)
        }
    }

    private func rowDetail(for dependency: AutomationDependency) -> String {
        let trigger = AutomationDependencyTriggerDraft.draft(for: dependency.trigger).title
        if let dynamicDelayDetail = dynamicDelayDetail(for: dependency) {
            return String(
                format: String(localized: "%@ · %@", table: "Common"),
                trigger,
                dynamicDelayDetail
            )
        }
        if dependency.delay <= 0 {
            return trigger
        }
        return String(
            format: String(localized: "%@ · %.1fs delay", table: "EditorUX"),
            trigger,
            dependency.delay
        )
    }

    private func dynamicDelayDetail(for dependency: AutomationDependency) -> String? {
        guard let dynamicDelay = dependency.dynamicDelay,
              dynamicDelay.source == .conditionEvidenceDuration else {
            return nil
        }
        let fallbackDelay = dynamicDelay.fallbackDelay ?? dependency.delay
        guard fallbackDelay > 0 else {
            return String(localized: "Observed time", table: "Common")
        }
        return String(
            format: String(localized: "Observed time · fallback %@", table: "Common"),
            compactDelayLabel(for: fallbackDelay)
        )
    }

    private func compactDelayLabel(for delay: TimeInterval) -> String {
        let totalSeconds = Int(max(0, delay).rounded())
        guard totalSeconds > 0 else {
            return String(localized: "no delay", table: "EditorUX")
        }
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0, parts.count < 2 {
            parts.append("\(minutes)m")
        }
        if seconds > 0, parts.isEmpty {
            parts.append("\(seconds)s")
        }
        return parts.prefix(2).joined(separator: " ")
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? String(localized: "Missing task", table: "Automation")
    }
}

private enum DependencyDirection {
    case outgoing
    case incoming

    func peerTaskID(for dependency: AutomationDependency) -> UUID {
        switch self {
        case .outgoing:
            return dependency.toTaskID
        case .incoming:
            return dependency.fromTaskID
        }
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: NSLocalizedString("DEPENDENCIES", comment: ""),
                count: relatedDependencies.count
            )

            createDependencySection

            if !outgoingDependencies.isEmpty {
                dependencyGroup(
                    title: NSLocalizedString("OUTGOING", comment: ""),
                    dependencies: outgoingDependencies,
                    direction: .outgoing
                )
            }

            if !incomingDependencies.isEmpty {
                dependencyGroup(
                    title: NSLocalizedString("INCOMING", comment: ""),
                    dependencies: incomingDependencies,
                    direction: .incoming
                )
            }

            if relatedDependencies.isEmpty && connectTargets.isEmpty {
                Label(NSLocalizedString("Add another task to create a link", comment: ""), systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
        .onAppear(perform: repairTargetSelection)
        .onChange(of: task.id) {
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
                Picker(NSLocalizedString("Connect to", comment: ""), selection: targetBinding) {
                    ForEach(connectTargets) { target in
                        Text(target.name).tag(Optional(target.id))
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Picker(NSLocalizedString("Trigger", comment: ""), selection: $triggerDraft) {
                        ForEach(AutomationDependencyTriggerDraft.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(NSLocalizedString("Delay", comment: ""), value: $delaySeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                }

                Button(action: createDependency) {
                    Label(NSLocalizedString("Create Link", comment: ""), systemImage: "link.badge.plus")
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

            Button(NSLocalizedString("Select task", comment: ""), systemImage: "arrow.up.right.square") {
                onSelectTask(direction.peerTaskID(for: dependency))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(NSLocalizedString("Select task", comment: ""))

            Button(NSLocalizedString("Delete Dependency", comment: ""), systemImage: "trash", role: .destructive) {
                onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .foregroundStyle(Brand.red500)
            .help(NSLocalizedString("Delete Dependency", comment: ""))
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

    private func createDependency() {
        guard let targetTaskID = targetBinding.wrappedValue else {
            return
        }

        let dependency = AutomationDependency(
            fromTaskID: task.id,
            toTaskID: targetTaskID,
            trigger: triggerDraft.trigger,
            delay: max(0, delaySeconds)
        )
        onAction(.upsertDependency(workflowID: workflow.id, dependency: dependency, at: Date()))
        onSelectDependency(dependency.id)
        self.targetTaskID = nil
    }

    private func repairTargetSelection() {
        if let targetTaskID,
           connectTargets.contains(where: { $0.id == targetTaskID }) {
            return
        }
        targetTaskID = connectTargets.first?.id
    }

    private func rowTitle(for dependency: AutomationDependency, direction: DependencyDirection) -> String {
        let peerName = taskName(direction.peerTaskID(for: dependency))
        switch direction {
        case .outgoing:
            return String(format: NSLocalizedString("To %@", comment: ""), peerName)
        case .incoming:
            return String(format: NSLocalizedString("From %@", comment: ""), peerName)
        }
    }

    private func rowDetail(for dependency: AutomationDependency) -> String {
        let trigger = AutomationDependencyTriggerDraft.draft(for: dependency.trigger).title
        if dependency.delay <= 0 {
            return trigger
        }
        return String(
            format: NSLocalizedString("%@ · %.1fs delay", comment: ""),
            trigger,
            dependency.delay
        )
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? NSLocalizedString("Missing task", comment: "")
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

import SwiftUI
import SparkleRecorderCore

struct AutomationTaskBranchPanelView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let onSelectTask: (UUID) -> Void
    let onSelectDependency: (UUID) -> Void
    let onAction: (AutomationAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: NSLocalizedString("IF / THEN / ELSE", comment: ""),
                count: outgoingDependencies.count
            )

            Label(conditionSummary, systemImage: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(branchIDs, id: \.self) { branchID in
                branchGroup(branchID)
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
        .accessibilityElement(children: .contain)
    }

    private func branchGroup(_ branchID: String) -> some View {
        let dependencies = dependencies(for: branchID)
        return VStack(alignment: .leading, spacing: 7) {
            Label(branchTitle(branchID), systemImage: branchIcon(branchID))
                .font(.caption)
                .bold()
                .foregroundStyle(branchTint(branchID))

            if dependencies.isEmpty {
                Label(emptyBranchTitle(branchID), systemImage: "minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .automationSubsurface(cornerRadius: 8)
            } else {
                ForEach(dependencies) { dependency in
                    branchRow(dependency, branchID: branchID)
                }
            }
        }
    }

    private func branchRow(_ dependency: AutomationDependency, branchID: String) -> some View {
        HStack(spacing: 7) {
            Button {
                onSelectDependency(dependency.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(targetName(for: dependency))
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(branchDetail(for: dependency, branchID: branchID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let decision = branchDecision(for: dependency) {
                        AutomationTaskBranchDecisionSummaryView(decision: decision)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(NSLocalizedString("Select target task", comment: ""), systemImage: "arrow.up.right.square") {
                onSelectTask(dependency.toTaskID)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(NSLocalizedString("Select target task", comment: ""))

            Button(NSLocalizedString("Delete Branch", comment: ""), systemImage: "trash", role: .destructive) {
                onAction(.deleteDependency(workflowID: workflow.id, dependencyID: dependency.id, at: Date()))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .foregroundStyle(Brand.red500)
            .help(NSLocalizedString("Delete Branch", comment: ""))
        }
        .padding(8)
        .automationSubsurface(cornerRadius: 8, tint: branchTint(branchID))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(branchAccessibilityLabel(dependency, branchID: branchID))
    }

    private var outgoingDependencies: [AutomationDependency] {
        workflow.dependencies(from: task.id)
    }

    private var branchIDs: [String] {
        var ids = ["then", "else", "timeout"]
        if !dependencies(for: "always").isEmpty {
            ids.append("always")
        }
        if !dependencies(for: "cancel").isEmpty {
            ids.append("cancel")
        }
        return ids
    }

    private var conditionSummary: String {
        switch task.kind {
        case .condition(let spec):
            return String(
                format: NSLocalizedString("When %@ finishes, branches below decide the next task.", comment: ""),
                spec.name
            )
        case .macro, .delay, .notification:
            return NSLocalizedString("Branches below decide the next task.", comment: "")
        }
    }

    private var dependencyEdgesByID: [UUID: AutomationDependencyEdgeProjection] {
        Dictionary(uniqueKeysWithValues: dependencyEdges.map { ($0.id, $0) })
    }

    private func dependencies(for branchID: String) -> [AutomationDependency] {
        outgoingDependencies.filter { dependency in
            branchIDForTrigger(dependency.trigger) == branchID
        }
    }

    private func branchIDForTrigger(_ trigger: AutomationDependencyTrigger) -> String {
        switch AutomationDependencyTriggerDraft.draft(for: trigger) {
        case .onSuccess, .onConditionMatched:
            return "then"
        case .onFailure, .onConditionNotMatched:
            return "else"
        case .onTimeout:
            return "timeout"
        case .onCancelled:
            return "cancel"
        case .always:
            return "always"
        }
    }

    private func branchTitle(_ branchID: String) -> String {
        switch branchID {
        case "then":
            return NSLocalizedString("Then", comment: "")
        case "else":
            return NSLocalizedString("Else", comment: "")
        case "timeout":
            return NSLocalizedString("Timeout", comment: "")
        case "cancel":
            return NSLocalizedString("Cancel", comment: "")
        default:
            return NSLocalizedString("Always", comment: "")
        }
    }

    private func branchIcon(_ branchID: String) -> String {
        switch branchID {
        case "then":
            return "checkmark.circle"
        case "else":
            return "xmark.circle"
        case "timeout":
            return "timer"
        case "cancel":
            return "slash.circle"
        default:
            return "arrow.right.circle"
        }
    }

    private func branchTint(_ branchID: String) -> Color {
        switch branchID {
        case "then":
            return Brand.libraryGreen
        case "else":
            return Brand.red500
        case "timeout":
            return Brand.sigAmber
        case "cancel":
            return .secondary
        default:
            return Brand.libraryBlue
        }
    }

    private func emptyBranchTitle(_ branchID: String) -> String {
        String(
            format: NSLocalizedString("No %@ branch", comment: ""),
            branchTitle(branchID).lowercased()
        )
    }

    private func targetName(for dependency: AutomationDependency) -> String {
        workflow.task(id: dependency.toTaskID)?.name ?? NSLocalizedString("Missing task", comment: "")
    }

    private func branchDetail(for dependency: AutomationDependency, branchID: String) -> String {
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

    private func branchDecision(for dependency: AutomationDependency) -> AutomationBranchDecisionProjection? {
        dependencyEdgesByID[dependency.id]?.branchDecision
    }

    private func branchAccessibilityLabel(_ dependency: AutomationDependency, branchID: String) -> String {
        let base = String(
            format: NSLocalizedString("%@ branch to %@, %@", comment: ""),
            branchTitle(branchID),
            targetName(for: dependency),
            branchDetail(for: dependency, branchID: branchID)
        )
        guard let decision = branchDecision(for: dependency) else {
            return base
        }
        return "\(base), \(decision.status.label), \(decision.detail)"
    }
}

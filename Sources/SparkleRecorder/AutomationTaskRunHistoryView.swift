import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunHistoryView: View {
    let runs: [AutomationTaskRun]
    let workflow: AutomationWorkflow
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    var resourceRequirement: AutomationResourceRequirement?
    var retryPolicy: AutomationRetryPolicy = .none
    var initialSelectedRunID: UUID?
    var macros: [SavedMacro] = []
    var onImportWorkflowFromDraftPreview: (AutomationWorkflow, URL?) -> Void = { _, _ in }

    @State private var selectedRunID: UUID?

    init(
        runs: [AutomationTaskRun],
        workflow: AutomationWorkflow,
        dependencyEdges: [AutomationDependencyEdgeProjection],
        resourceRequirement: AutomationResourceRequirement? = nil,
        retryPolicy: AutomationRetryPolicy = .none,
        initialSelectedRunID: UUID? = nil,
        macros: [SavedMacro] = [],
        onImportWorkflowFromDraftPreview: @escaping (AutomationWorkflow, URL?) -> Void = { _, _ in }
    ) {
        self.runs = runs
        self.workflow = workflow
        self.dependencyEdges = dependencyEdges
        self.resourceRequirement = resourceRequirement
        self.retryPolicy = retryPolicy
        self.initialSelectedRunID = initialSelectedRunID
        self.macros = macros
        self.onImportWorkflowFromDraftPreview = onImportWorkflowFromDraftPreview
        _selectedRunID = State(initialValue: initialSelectedRunID)
    }

    var body: some View {
        let visibleRuns = Array(runs.prefix(5))
        let selectedRun = selectedRun(from: visibleRuns)

        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: String(localized: "RUN HISTORY", table: "Automation"),
                count: runs.count
            )

            if runs.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No task runs yet", tableName: "Automation")
                            .font(.caption)
                            .bold()
                        Text("Manual or scheduled runs will appear here with timing, outcome, and evidence.", tableName: "Automation")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleRuns) { run in
                        Button {
                            selectedRunID = run.id
                        } label: {
                            AutomationTaskRunRowView(
                                run: run,
                                resourceRequirement: resourceRequirement,
                                isSelected: selectedRun?.id == run.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(String(localized: "Shows run details", table: "Common"))

                        if run.id != visibleRuns.last?.id {
                            Divider().opacity(0.45)
                        }
                    }
                }

                if let selectedRun {
                    AutomationTaskRunDetailView(
                        run: selectedRun,
                        workflow: workflow,
                        dependencyEdges: dependencyEdges,
                        display: AutomationTaskRunDisplay(
                            run: selectedRun,
                            resourceRequirement: resourceRequirement
                        ),
                        retryPolicy: retryPolicy,
                        hasLaterAttempt: hasLaterAttempt(after: selectedRun),
                        macros: macros,
                        onImportWorkflowFromDraftPreview: onImportWorkflowFromDraftPreview
                    )
                }

                if runs.count > visibleRuns.count {
                    Text(String(format: String(localized: "%d older runs hidden", table: "Automation"), runs.count - visibleRuns.count))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .onChange(of: initialSelectedRunID) {
            selectedRunID = initialSelectedRunID
        }
    }

    private func selectedRun(from visibleRuns: [AutomationTaskRun]) -> AutomationTaskRun? {
        if let selectedRunID,
           let selected = runs.first(where: { $0.id == selectedRunID }) {
            return selected
        }
        return visibleRuns.first
    }

    private func hasLaterAttempt(after run: AutomationTaskRun) -> Bool {
        runs.contains {
            $0.executionID == run.executionID &&
                $0.attempt > run.attempt
        }
    }
}

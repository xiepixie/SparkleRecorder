import SparkleRecorderCore
import SwiftUI

struct AutomationTaskRunEditorView: View {
    let workflow: AutomationWorkflow
    let task: AutomationTask
    let taskProjection: AutomationTaskNodeProjection?
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let macros: [SavedMacro]
    let runs: [AutomationTaskRun]
    let initialSelectedRunID: UUID?
    let selectedMacroHasSurfaces: Bool
    @Binding var scheduleDraft: AutomationTaskScheduleDraft
    @Binding var executionDraft: AutomationTaskExecutionDraft
    let onRun: () -> Void
    let onCancel: (UUID?) -> Void
    let onImportWorkflowFromDraftPreview: @MainActor (AutomationWorkflow, URL?) async throws -> Void

    var body: some View {
        let history = AutomationTaskRunHistoryPresentation.make(
            runs: runs,
            workflowID: workflow.id,
            taskID: task.id,
            initialSelectedRunID: initialSelectedRunID
        )

        VStack(alignment: .leading, spacing: 14) {
            AutomationTaskRunControlView(
                taskName: task.name,
                isEnabled: task.isEnabled,
                resourceRequirement: task.resourceRequirement,
                activeRunID: history.activeRunID,
                onRun: onRun,
                onCancel: { onCancel(history.activeRunID) }
            )

            if let taskProjection {
                AutomationTaskRuntimeDetailView(projection: taskProjection)
            }

            scheduleSection

            AutomationTaskRunHistoryView(
                presentation: history,
                workflow: workflow,
                dependencyEdges: dependencyEdges,
                resourceRequirement: task.resourceRequirement,
                retryPolicy: task.retryPolicy,
                initialSelectedRunID: initialSelectedRunID,
                macros: macros,
                onImportWorkflowFromDraftPreview: onImportWorkflowFromDraftPreview
            )
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(title: String(localized: "SCHEDULE", table: "Common"))

            Picker(String(localized: "Schedule", table: "Common"), selection: $scheduleDraft.mode) {
                ForEach(AutomationTaskScheduleMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch scheduleDraft.mode {
            case .manual:
                Label(String(localized: "Manual start only", table: "Common"), systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .once:
                DatePicker(
                    String(localized: "Start", table: "Common"),
                    selection: $scheduleDraft.onceDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
            case .repeating:
                DatePicker(
                    String(localized: "Start", table: "Common"),
                    selection: $scheduleDraft.repeatStart,
                    displayedComponents: [.date, .hourAndMinute]
                )

                HStack(spacing: 8) {
                    LabeledContent(String(localized: "Every", table: "Common")) {
                        TextField(
                            String(localized: "Count", table: "Common"),
                            value: $scheduleDraft.repeatEvery,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 58)
                    }

                    Picker(String(localized: "Unit", table: "Common"), selection: $scheduleDraft.repeatUnit) {
                        ForEach(AutomationTaskRepeatUnit.allCases, id: \.self) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if isMacroTask, selectedMacroHasSurfaces {
                Picker(
                    String(localized: "Target application", table: "Automation"),
                    selection: $executionDraft.targetApplicationPolicy
                ) {
                    ForEach(AutomationTargetApplicationPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                Text(executionDraft.targetApplicationPolicy.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if executionDraft.targetApplicationPolicy != .doNotActivate {
                    Picker(
                        String(localized: "Wait after window appears", table: "Automation"),
                        selection: $executionDraft.targetApplicationReadyDelay
                    ) {
                        Text("No wait", tableName: "Automation").tag(TimeInterval(0))
                        Text("2s").tag(TimeInterval(2))
                        Text("5s").tag(TimeInterval(5))
                        Text("10s").tag(TimeInterval(10))
                        Text("20s").tag(TimeInterval(20))
                        Text("30s").tag(TimeInterval(30))
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var isMacroTask: Bool {
        if case .macro = task.kind {
            return true
        }
        return false
    }
}

private extension AutomationTaskScheduleMode {
    var title: String {
        switch self {
        case .manual:
            return String(localized: "Manual", table: "Common")
        case .once:
            return String(localized: "Once", table: "Common")
        case .repeating:
            return String(localized: "Repeating", table: "Common")
        }
    }
}

private extension AutomationTaskRepeatUnit {
    var title: String {
        switch self {
        case .minutes:
            return String(localized: "Minutes", table: "Common")
        case .hours:
            return String(localized: "Hours", table: "Common")
        case .days:
            return String(localized: "Days", table: "Common")
        case .weeks:
            return String(localized: "Weeks", table: "Common")
        }
    }
}

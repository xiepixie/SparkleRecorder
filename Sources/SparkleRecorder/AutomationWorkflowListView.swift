import SwiftUI
import SparkleRecorderCore

struct AutomationWorkflowListView: View {
    let projection: AutomationOverviewProjection
    let macros: [SavedMacro]
    @Binding var selectedWorkflowID: UUID?
    let selectedWorkflow: AutomationWorkflow?
    let onSelectWorkflow: (UUID?) -> Void
    let onCreateWorkflow: () -> Void
    let onImportWorkflowPackage: () -> Void
    let onExportWorkflowPackage: () -> Void
    let onShareWorkflowPackage: () -> Void
    let onAddMacroTask: (SavedMacro) -> Void
    let onAddConditionTask: (AutomationConditionKind) -> Void
    let isRecordingMacro: Bool
    let recordsMacroIntoWorkflow: Bool
    let isRecordingIntoWorkflow: Bool
    let recordHotkeyName: String?
    let onRecordMacro: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let workflowHeight = min(max(proxy.size.height * 0.34, 156), 286)

            VStack(alignment: .leading, spacing: 0) {
                workflowSection
                    .frame(height: workflowHeight)

                Divider().opacity(0.5)

                ScrollView {
                    AutomationMacroTaskLibraryView(
                        macros: macros,
                        selectedWorkflow: selectedWorkflow,
                        isRecordingMacro: isRecordingMacro,
                        recordsMacroIntoWorkflow: recordsMacroIntoWorkflow,
                        isRecordingIntoWorkflow: isRecordingIntoWorkflow,
                        recordHotkeyName: recordHotkeyName,
                        onRecordMacro: onRecordMacro,
                        onAddMacroTask: onAddMacroTask,
                        onAddConditionTask: onAddConditionTask
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("WORKFLOWS", comment: ""))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(projection.workflows.count, format: .number)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                Button(NSLocalizedString("New Workflow", comment: ""), systemImage: "plus", action: onCreateWorkflow)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .help(NSLocalizedString("New Workflow", comment: ""))

                Button(NSLocalizedString("Import Workflow Package", comment: ""), systemImage: "square.and.arrow.down", action: onImportWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .help(NSLocalizedString("Import Workflow Package", comment: ""))

                Button(NSLocalizedString("Export All Workflows", comment: ""), systemImage: "square.and.arrow.up", action: onExportWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .disabled(projection.workflows.isEmpty)
                    .help(NSLocalizedString("Export All Workflows", comment: ""))

                Button(NSLocalizedString("Share All Workflows", comment: ""), systemImage: "square.and.arrow.up.on.square", action: onShareWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .disabled(projection.workflows.isEmpty)
                    .help(NSLocalizedString("Share All Workflows", comment: ""))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                if projection.workflows.isEmpty {
                    AutomationEmptyState(
                        systemImage: "square.stack.3d.up.slash",
                        title: NSLocalizedString("No workflows", comment: ""),
                        subtitle: NSLocalizedString("Create an automation workflow to see it in this list.", comment: "")
                    )
                    .frame(maxWidth: .infinity, minHeight: 156)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(projection.workflows) { workflow in
                            Button {
                                onSelectWorkflow(workflow.id)
                            } label: {
                                AutomationWorkflowRow(
                                    workflow: workflow,
                                    isSelected: (selectedWorkflowID ?? projection.workflows.first?.id) == workflow.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .scrollIndicators(.hidden)
        }
    }
}

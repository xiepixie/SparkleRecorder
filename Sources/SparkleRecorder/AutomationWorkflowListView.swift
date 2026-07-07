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

    enum Tab {
        case workflows
        case library
    }

    @State private var selectedTab: Tab = .workflows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $selectedTab) {
                Text(NSLocalizedString("Workflows", comment: "")).tag(Tab.workflows)
                Text(NSLocalizedString("Library", comment: "")).tag(Tab.library)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if selectedTab == .workflows {
                HStack(spacing: 8) {
                    AutomationSectionHeader(
                        title: NSLocalizedString("WORKFLOWS", comment: ""),
                        count: projection.workflows.count
                    )

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

                ScrollView {
                    if projection.workflows.isEmpty {
                        AutomationEmptyState(
                            systemImage: "square.stack.3d.up.slash",
                            title: NSLocalizedString("No workflows", comment: ""),
                            subtitle: NSLocalizedString("Create an automation workflow to see it in this list.", comment: "")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
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
            } else {
                ScrollView {
                    AutomationMacroTaskLibraryView(
                        macros: macros,
                        selectedWorkflow: selectedWorkflow,
                        onAddMacroTask: onAddMacroTask,
                        onAddConditionTask: onAddConditionTask
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AutomationSectionHeader(
                    title: NSLocalizedString("WORKFLOWS", comment: ""),
                    count: projection.workflows.count
                )

                Button("New Workflow", systemImage: "plus", action: onCreateWorkflow)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .help(NSLocalizedString("New Workflow", comment: ""))
                    .accessibilityLabel(NSLocalizedString("New Workflow", comment: ""))

                Button("Import Workflow Package", systemImage: "square.and.arrow.down", action: onImportWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .help(NSLocalizedString("Import Workflow Package", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Import Workflow Package", comment: ""))

                Button("Export All Workflows", systemImage: "square.and.arrow.up", action: onExportWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .disabled(projection.workflows.isEmpty)
                    .help(NSLocalizedString("Export All Workflows", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Export All Workflows", comment: ""))

                Button("Share All Workflows", systemImage: "square.and.arrow.up.on.square", action: onShareWorkflowPackage)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: 26, height: 26)
                    .disabled(projection.workflows.isEmpty)
                    .help(NSLocalizedString("Share All Workflows", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Share All Workflows", comment: ""))
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
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(projection.workflows) { workflow in
                            AutomationWorkflowRow(
                                workflow: workflow,
                                isSelected: (selectedWorkflowID ?? projection.workflows.first?.id) == workflow.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectWorkflow(workflow.id)
                            }
                        }
                    }
                }

                AutomationMacroTaskLibraryView(
                    macros: macros,
                    selectedWorkflow: selectedWorkflow,
                    onAddMacroTask: onAddMacroTask
                )
                .padding(.top, 14)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }
}

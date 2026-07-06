import SwiftUI
import SparkleRecorderCore

struct AutomationMacroTaskLibraryView: View {
    let macros: [SavedMacro]
    let selectedWorkflow: AutomationWorkflow?
    let onAddMacroTask: (SavedMacro) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AutomationSectionHeader(
                title: NSLocalizedString("MACROS", comment: ""),
                count: macros.count
            )

            if macros.isEmpty {
                AutomationEmptyState(
                    systemImage: "record.circle",
                    title: NSLocalizedString("No macros yet", comment: ""),
                    subtitle: NSLocalizedString("Record a macro before adding automation tasks.", comment: "")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(macros) { macro in
                        AutomationMacroTaskRow(
                            macro: macro,
                            selectedWorkflow: selectedWorkflow,
                            onAddMacroTask: onAddMacroTask
                        )
                    }
                }
            }
        }
    }
}

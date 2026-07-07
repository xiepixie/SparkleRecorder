import SwiftUI
import SparkleRecorderCore

struct AutomationMacroTaskLibraryView: View {
    let macros: [SavedMacro]
    let selectedWorkflow: AutomationWorkflow?
    let onAddMacroTask: (SavedMacro) -> Void
    let onAddConditionTask: (AutomationConditionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(title: NSLocalizedString("ADD CONDITION", comment: ""))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        manualApprovalButton
                        externalSignalButton
                    }
                    HStack(spacing: 6) {
                        screenTextButton
                        regionChangedButton
                    }
                    HStack(spacing: 6) {
                        imageAppearedButton
                        imageDisappearedButton
                    }
                    HStack(spacing: 6) {
                        pixelMatchedButton
                    }
                }
                .disabled(selectedWorkflow == nil)
            }

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

    private var manualApprovalButton: some View {
        Button(action: { onAddConditionTask(.manualApproval) }) {
            Label(NSLocalizedString("Manual approval", comment: ""), systemImage: "hand.raised.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var externalSignalButton: some View {
        Button(action: { onAddConditionTask(.externalSignal(NSLocalizedString("Ready", comment: ""))) }) {
            Label(NSLocalizedString("External signal", comment: ""), systemImage: "antenna.radiowaves.left.and.right")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var screenTextButton: some View {
        Button(action: { onAddConditionTask(.ocrText(AutomationOCRCondition(text: ""))) }) {
            Label(NSLocalizedString("Screen text", comment: ""), systemImage: "text.viewfinder")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var regionChangedButton: some View {
        Button(action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .regionChanged))) }) {
            Label(
                AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.regionChanged),
                systemImage: "viewfinder.rectangular"
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var imageAppearedButton: some View {
        Button(action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .imageAppeared))) }) {
            Label(
                AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageAppeared),
                systemImage: "photo"
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var imageDisappearedButton: some View {
        Button(action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .imageDisappeared))) }) {
            Label(
                AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageDisappeared),
                systemImage: "photo.on.rectangle"
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }

    private var pixelMatchedButton: some View {
        Button(action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .pixelMatched))) }) {
            Label(
                AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.pixelMatched),
                systemImage: "paintpalette"
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }
}

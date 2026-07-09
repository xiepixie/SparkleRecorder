import SwiftUI
import SparkleRecorderCore

struct AutomationMacroTaskLibraryView: View {
    let macros: [SavedMacro]
    let selectedWorkflow: AutomationWorkflow?
    let isRecordingMacro: Bool
    let recordsMacroIntoWorkflow: Bool
    let isRecordingIntoWorkflow: Bool
    let recordHotkeyName: String?
    let onRecordMacro: (() -> Void)?
    let onAddMacroTask: (SavedMacro) -> Void
    let onAddConditionTask: (AutomationConditionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(title: String(localized: "SOURCE", table: "Common"))
                recordMacroButton
            }

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(
                    title: String(localized: "MACROS", table: "EditorUX"),
                    count: macros.count
                )

                if macros.isEmpty {
                    AutomationEmptyState(
                        systemImage: "record.circle",
                        title: String(localized: "No macros yet", table: "EditorUX"),
                        subtitle: String(localized: "Record a macro before adding automation tasks.", table: "Automation")
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

            VStack(alignment: .leading, spacing: 8) {
                AutomationSectionHeader(title: String(localized: "CONDITION BLOCKS", table: "Automation"))

                VStack(alignment: .leading, spacing: 6) {
                    manualApprovalButton
                    externalSignalButton
                    screenTextButton
                    regionChangedButton
                    imageAppearedButton
                    imageDisappearedButton
                    pixelMatchedButton
                }
                .disabled(selectedWorkflow == nil)
                .opacity(selectedWorkflow == nil ? 0.55 : 1)
            }
        }
    }

    private var recordMacroButton: some View {
        Button {
            onRecordMacro?()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill((isRecordingMacro ? Brand.red500 : Color.primary).opacity(isRecordingMacro ? 0.18 : 0.055))
                        .frame(width: 24, height: 24)

                    Image(systemName: isRecordingMacro ? "stop.fill" : "record.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isRecordingMacro ? Brand.red500 : .secondary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRecordingMacro
                         ? String(localized: "Stop recording", table: "Recording")
                         : String(localized: "Record macro", table: "Recording"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(recordMacroDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let recordHotkeyName, !recordHotkeyName.isEmpty {
                    Text(recordHotkeyName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
        .disabled(onRecordMacro == nil)
        .accessibilityLabel(isRecordingMacro
                            ? String(localized: "Stop recording", table: "Recording")
                            : String(localized: "Record macro", table: "Recording"))
    }

    private var recordMacroDetail: String {
        if isRecordingMacro {
            return isRecordingIntoWorkflow
                ? String(localized: "Capturing workflow task", table: "Automation")
                : String(localized: "Capturing source", table: "Common")
        }
        return recordsMacroIntoWorkflow
            ? String(localized: "New source task", table: "Automation")
            : String(localized: "New source macro", table: "EditorUX")
    }

    private var manualApprovalButton: some View {
        conditionButton(
            title: String(localized: "Manual approval", table: "Common"),
            detail: String(localized: "Human decision", table: "Common"),
            systemImage: "hand.raised.fill",
            tint: Brand.libraryBlue,
            action: { onAddConditionTask(.manualApproval) }
        )
    }

    private var externalSignalButton: some View {
        conditionButton(
            title: String(localized: "External signal", table: "Common"),
            detail: String(localized: "Named app signal", table: "Common"),
            systemImage: "antenna.radiowaves.left.and.right",
            tint: Brand.sigTeal,
            action: { onAddConditionTask(.externalSignal(String(localized: "Ready", table: "Common"))) }
        )
    }

    private var screenTextButton: some View {
        conditionButton(
            title: String(localized: "Screen text", table: "Recording"),
            detail: String(localized: "OCR text target", table: "EditorUX"),
            systemImage: "text.viewfinder",
            tint: Brand.sigAmber,
            action: { onAddConditionTask(.ocrText(AutomationOCRCondition(text: ""))) }
        )
    }

    private var regionChangedButton: some View {
        conditionButton(
            title: AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.regionChanged),
            detail: String(localized: "Watched area + baseline", table: "Common"),
            systemImage: "viewfinder.rectangular",
            tint: Brand.sigViolet,
            action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .regionChanged))) }
        )
    }

    private var imageAppearedButton: some View {
        conditionButton(
            title: AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageAppeared),
            detail: String(localized: "Watched area + image", table: "Common"),
            systemImage: "photo",
            tint: Brand.libraryGreen,
            action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .imageAppeared))) }
        )
    }

    private var imageDisappearedButton: some View {
        conditionButton(
            title: AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.imageDisappeared),
            detail: String(localized: "Watched area + image", table: "Common"),
            systemImage: "photo.on.rectangle",
            tint: Brand.libraryGreen,
            action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .imageDisappeared))) }
        )
    }

    private var pixelMatchedButton: some View {
        conditionButton(
            title: AutomationVisualConditionPresentation.title(for: AutomationVisualConditionType.pixelMatched),
            detail: String(localized: "Pixel + color", table: "Common"),
            systemImage: "paintpalette",
            tint: Brand.sigPink,
            action: { onAddConditionTask(.visual(AutomationVisualCondition(type: .pixelMatched))) }
        )
    }

    private func conditionButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AutomationQuietButtonStyle())
    }
}

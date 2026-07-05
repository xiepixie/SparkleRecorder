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
                        Button {
                            onAddMacroTask(macro)
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(cardAccentColor(for: macro.accent).opacity(0.9))
                                    Image(systemName: macro.icon ?? "wave.3.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(macro.name)
                                        .font(.caption)
                                        .bold()
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(String(format: NSLocalizedString("%d events", comment: ""), macro.eventCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(selectedWorkflow == nil ? .secondary : Brand.libraryGreen)
                                    .accessibilityHidden(true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .controlSurface(cornerRadius: 8, tint: Brand.libraryGreen, isActive: false)
                        }
                        .buttonStyle(.plain)
                        .help(NSLocalizedString("Add macro as task", comment: ""))
                        .accessibilityLabel(String(
                            format: NSLocalizedString("Add %@ as task", comment: ""),
                            macro.name
                        ))
                    }
                }
            }
        }
    }
}

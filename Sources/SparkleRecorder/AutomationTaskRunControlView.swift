import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunControlView: View {
    let taskName: String
    let isEnabled: Bool
    let resourceRequirement: AutomationResourceRequirement
    let activeRunID: UUID?
    let onRun: () -> Void
    let onCancel: () -> Void

    @State private var isConfirmingRun = false
    @State private var isConfirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AutomationSectionHeader(title: String(localized: "RUN CONTROL", table: "Automation"))

            HStack(alignment: .center, spacing: 8) {
                Label(statusTitle, systemImage: statusImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(statusTint)
                    .lineLimit(1)

                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if activeRunID == nil {
                    Button(String(localized: "Run Task", table: "Automation"), systemImage: "play.fill") {
                        isConfirmingRun = true
                    }
                    .buttonStyle(AutomationQuietButtonStyle(tint: Brand.libraryGreen))
                    .disabled(!isEnabled)
                    .help(runButtonHelp)
                } else {
                    Button(String(localized: "Cancel Run", table: "Automation"), systemImage: "xmark.circle", role: .destructive) {
                        isConfirmingCancel = true
                    }
                    .buttonStyle(AutomationQuietButtonStyle(isDestructive: true))
                    .help(String(localized: "Cancel the current run", table: "Automation"))
                }
            }
        }
        .padding(.vertical, 8)
        .alert(runConfirmationTitle, isPresented: $isConfirmingRun) {
            Button(String(localized: "Run Task", table: "Automation"), action: onRun)
            Button(String(localized: "Cancel", table: "Common"), role: .cancel) {}
        } message: {
            Text(runConfirmationMessage)
        }
        .alert(cancelConfirmationTitle, isPresented: $isConfirmingCancel) {
            Button(String(localized: "Cancel Run", table: "Automation"), role: .destructive, action: onCancel)
            Button(String(localized: "Keep Running", table: "Automation"), role: .cancel) {}
        } message: {
            Text(cancelConfirmationMessage)
        }
    }

    private var statusTitle: String {
        if activeRunID != nil {
            return String(localized: "Running", table: "Automation")
        }
        if !isEnabled {
            return String(localized: "Disabled", table: "Common")
        }
        return String(localized: "Ready", table: "Common")
    }

    private var statusImage: String {
        if activeRunID != nil {
            return "dot.radiowaves.left.and.right"
        }
        if !isEnabled {
            return "pause.circle"
        }
        return "hand.tap"
    }

    private var statusTint: Color {
        if activeRunID != nil {
            return Brand.libraryGreen
        }
        if !isEnabled {
            return .secondary
        }
        return resourceRequirement.requiresForegroundInput ? Brand.sigAmber : Brand.libraryBlue
    }

    private var statusDetail: String {
        if activeRunID != nil {
            return String(localized: "Current run is active", table: "Automation")
        }
        if !isEnabled {
            return String(localized: "Enable the task before running", table: "Automation")
        }
        if resourceRequirement.requiresForegroundInput {
            return String(localized: "May use mouse and keyboard", table: "Automation")
        }
        return resourceLabel
    }

    private var resourceLabel: String {
        if resourceRequirement.resources.isEmpty {
            return String(localized: "No exclusive resources", table: "Common")
        }
        return resourceRequirement.resources
            .sorted { $0.rawValue < $1.rawValue }
            .map(resourceTitle(for:))
            .joined(separator: ", ")
    }

    private var runButtonHelp: String {
        isEnabled
            ? String(localized: "Start this task now", table: "Automation")
            : String(localized: "Enable the task before running", table: "Automation")
    }

    private var runConfirmationTitle: String {
        String(format: String(localized: "Run %@?", table: "Automation"), taskName)
    }

    private var runConfirmationMessage: String {
        if resourceRequirement.requiresForegroundInput {
            return String(
                format: String(localized: "This starts \"%@\" now and may control the mouse and keyboard while it runs.", table: "Common"),
                taskName
            )
        }
        return String(
            format: String(localized: "This starts \"%@\" now using its configured automation resources.", table: "Common"),
            taskName
        )
    }

    private var cancelConfirmationTitle: String {
        String(format: String(localized: "Cancel %@?", table: "Common"), taskName)
    }

    private var cancelConfirmationMessage: String {
        String(
            format: String(localized: "This cancels the current run for \"%@\".", table: "Common"),
            taskName
        )
    }

    private func resourceTitle(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return String(localized: "Mouse and keyboard", table: "Common")
        case .screenCapture:
            return String(localized: "Screen capture", table: "Recording")
        case .accessibility:
            return String(localized: "Accessibility", table: "Settings")
        case .network:
            return String(localized: "Network", table: "Common")
        }
    }
}

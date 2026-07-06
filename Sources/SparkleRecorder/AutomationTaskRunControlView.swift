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
            AutomationSectionHeader(title: NSLocalizedString("RUN CONTROL", comment: ""))

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
                    Button(NSLocalizedString("Run Task", comment: ""), systemImage: "play.fill") {
                        isConfirmingRun = true
                    }
                    .buttonStyle(AutomationQuietButtonStyle(tint: Brand.libraryGreen))
                    .disabled(!isEnabled)
                    .help(runButtonHelp)
                } else {
                    Button(NSLocalizedString("Cancel Run", comment: ""), systemImage: "xmark.circle", role: .destructive) {
                        isConfirmingCancel = true
                    }
                    .buttonStyle(AutomationQuietButtonStyle(isDestructive: true))
                    .help(NSLocalizedString("Cancel the current run", comment: ""))
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
        .alert(runConfirmationTitle, isPresented: $isConfirmingRun) {
            Button(NSLocalizedString("Run Task", comment: ""), action: onRun)
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(runConfirmationMessage)
        }
        .alert(cancelConfirmationTitle, isPresented: $isConfirmingCancel) {
            Button(NSLocalizedString("Cancel Run", comment: ""), role: .destructive, action: onCancel)
            Button(NSLocalizedString("Keep Running", comment: ""), role: .cancel) {}
        } message: {
            Text(cancelConfirmationMessage)
        }
    }

    private var statusTitle: String {
        if activeRunID != nil {
            return NSLocalizedString("Running", comment: "")
        }
        if !isEnabled {
            return NSLocalizedString("Disabled", comment: "")
        }
        return NSLocalizedString("Ready", comment: "")
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
            return NSLocalizedString("Current run is active", comment: "")
        }
        if !isEnabled {
            return NSLocalizedString("Enable the task before running", comment: "")
        }
        if resourceRequirement.requiresForegroundInput {
            return NSLocalizedString("May use mouse and keyboard", comment: "")
        }
        return resourceLabel
    }

    private var resourceLabel: String {
        if resourceRequirement.resources.isEmpty {
            return NSLocalizedString("No exclusive resources", comment: "")
        }
        return resourceRequirement.resources
            .sorted { $0.rawValue < $1.rawValue }
            .map(resourceTitle(for:))
            .joined(separator: ", ")
    }

    private var runButtonHelp: String {
        isEnabled
            ? NSLocalizedString("Start this task now", comment: "")
            : NSLocalizedString("Enable the task before running", comment: "")
    }

    private var runConfirmationTitle: String {
        String(format: NSLocalizedString("Run %@?", comment: ""), taskName)
    }

    private var runConfirmationMessage: String {
        if resourceRequirement.requiresForegroundInput {
            return String(
                format: NSLocalizedString("This starts \"%@\" now and may control the mouse and keyboard while it runs.", comment: ""),
                taskName
            )
        }
        return String(
            format: NSLocalizedString("This starts \"%@\" now using its configured automation resources.", comment: ""),
            taskName
        )
    }

    private var cancelConfirmationTitle: String {
        String(format: NSLocalizedString("Cancel %@?", comment: ""), taskName)
    }

    private var cancelConfirmationMessage: String {
        String(
            format: NSLocalizedString("This cancels the current run for \"%@\".", comment: ""),
            taskName
        )
    }

    private func resourceTitle(for resource: AutomationResource) -> String {
        switch resource {
        case .foregroundInput:
            return NSLocalizedString("Mouse and keyboard", comment: "")
        case .screenCapture:
            return NSLocalizedString("Screen capture", comment: "")
        case .accessibility:
            return NSLocalizedString("Accessibility", comment: "")
        case .network:
            return NSLocalizedString("Network", comment: "")
        }
    }
}

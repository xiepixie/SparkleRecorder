import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceDiagnosticsView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Focus", comment: ""),
                value: focusLabel
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Preview", comment: ""),
                value: previewLabel
            )

            Label(nextCheckLabel, systemImage: nextCheckImage)
                .font(.caption)
                .foregroundStyle(nextCheckStyle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var focusLabel: String {
        if payload.report.isSuccess {
            return NSLocalizedString("Completed run", comment: "")
        }

        if let failedEventIndex = payload.report.failedEventIndex {
            return String(format: NSLocalizedString("Event #%d", comment: ""), failedEventIndex + 1)
        }

        if let outcome = run.outcome {
            switch outcome {
            case .timedOut:
                return NSLocalizedString("Timeout", comment: "")
            case .permissionDenied:
                return NSLocalizedString("Permission", comment: "")
            case .missingMacro:
                return NSLocalizedString("Missing macro", comment: "")
            case .conditionNotMatched:
                return NSLocalizedString("Else branch", comment: "")
            case .conditionMatched:
                return NSLocalizedString("Then branch", comment: "")
            case .failed:
                return NSLocalizedString("Playback error", comment: "")
            case .cancelled:
                return NSLocalizedString("Cancelled run", comment: "")
            case .resourceConflict:
                return NSLocalizedString("Resource conflict", comment: "")
            case .rejected:
                return NSLocalizedString("Rejected run", comment: "")
            case .succeeded:
                return NSLocalizedString("Completed run", comment: "")
            }
        }

        return NSLocalizedString("Report", comment: "")
    }

    private var previewLabel: String {
        if payload.screenshotData != nil {
            return NSLocalizedString("Inline screenshot", comment: "")
        }

        if payload.screenshotURL != nil {
            return NSLocalizedString("Screenshot file", comment: "")
        }

        return payload.report.isSuccess
            ? NSLocalizedString("No failure screenshot needed", comment: "")
            : NSLocalizedString("No screenshot saved", comment: "")
    }

    private var nextCheckImage: String {
        payload.report.isSuccess ? "checkmark.circle" : "checklist"
    }

    private var nextCheckStyle: Color {
        payload.report.isSuccess ? .secondary : Brand.sigAmber
    }

    private var nextCheckLabel: String {
        if payload.report.isSuccess {
            return NSLocalizedString("Keep this report as a run audit trail.", comment: "")
        }

        if payload.source == .latestMacro {
            return NSLocalizedString("Latest macro evidence is not tied to this run; prefer per-run evidence after the next playback.", comment: "")
        }

        if payload.screenshotData != nil {
            return NSLocalizedString("Compare the failed event with the inline screenshot before editing the macro.", comment: "")
        }

        if payload.screenshotURL != nil {
            return NSLocalizedString("Open the saved screenshot, then compare the target window and failed event.", comment: "")
        }

        if let errorMessage = payload.report.errorMessage,
           !errorMessage.isEmpty {
            return NSLocalizedString("Start with the error message, then inspect the macro target and window context.", comment: "")
        }

        return NSLocalizedString("Review the report timing and macro package before retrying.", comment: "")
    }
}

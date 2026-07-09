import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceDiagnosticsView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: String(localized: "Focus", table: "Common"),
                value: focusLabel
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Preview", table: "Common"),
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
            return String(localized: "Completed run", table: "Common")
        }

        if let failedEventIndex = payload.report.failedEventIndex {
            return String(format: String(localized: "Event #%d", table: "EditorUX"), failedEventIndex + 1)
        }

        if let outcome = run.outcome {
            switch outcome {
            case .timedOut:
                return String(localized: "Timeout", table: "Common")
            case .permissionDenied:
                return String(localized: "Permission", table: "Common")
            case .missingMacro:
                return String(localized: "Missing macro", table: "EditorUX")
            case .conditionNotMatched:
                return String(localized: "Else branch", table: "Automation")
            case .conditionMatched:
                return String(localized: "Then branch", table: "Common")
            case .failed:
                return String(localized: "Playback error", table: "Common")
            case .cancelled:
                return String(localized: "Cancelled run", table: "Common")
            case .resourceConflict:
                return String(localized: "Resource conflict", table: "Common")
            case .rejected:
                return String(localized: "Rejected run", table: "Common")
            case .succeeded:
                return String(localized: "Completed run", table: "Common")
            }
        }

        return String(localized: "Report", table: "Common")
    }

    private var previewLabel: String {
        if payload.screenshotData != nil {
            return String(localized: "Inline screenshot", table: "Common")
        }

        if payload.screenshotURL != nil {
            return String(localized: "Screenshot file", table: "Common")
        }

        return payload.report.isSuccess
            ? String(localized: "No failure screenshot needed", table: "Common")
            : String(localized: "No screenshot saved", table: "Common")
    }

    private var nextCheckImage: String {
        payload.report.isSuccess ? "checkmark.circle" : "checklist"
    }

    private var nextCheckStyle: Color {
        payload.report.isSuccess ? .secondary : Brand.sigAmber
    }

    private var nextCheckLabel: String {
        if payload.report.isSuccess {
            return String(localized: "Keep this report as a run audit trail.", table: "Common")
        }

        if payload.source == .latestMacro {
            return String(localized: "Latest macro evidence is not tied to this run; prefer per-run evidence after the next playback.", table: "Common")
        }

        if payload.screenshotData != nil {
            return String(localized: "Compare the failed event with the inline screenshot before editing the macro.", table: "Common")
        }

        if payload.screenshotURL != nil {
            return String(localized: "Open the saved screenshot, then compare the target window and failed event.", table: "Common")
        }

        if let errorMessage = payload.report.errorMessage,
           !errorMessage.isEmpty {
            return String(localized: "Start with the error message, then inspect the macro target and window context.", table: "Common")
        }

        return String(localized: "Review the report timing and macro package before retrying.", table: "Common")
    }
}

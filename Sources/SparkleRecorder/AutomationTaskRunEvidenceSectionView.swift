import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceSectionView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload?
    let isLoading: Bool
    let errorMessage: String
    let initialActionFeedback: AutomationTaskRunEvidenceActionFeedback?
    let onLoad: () -> Void

    @State private var actionFeedback: AutomationTaskRunEvidenceActionFeedback?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(evidenceTitle, systemImage: "doc.richtext")
                    .font(.caption)
                    .bold()
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(loadButtonTitle, systemImage: "arrow.clockwise", action: onLoad)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(run.macroID == nil || isLoading)
            }

            if let evidenceID = run.evidenceID {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Evidence ID", table: "Common"),
                    value: shortID(evidenceID)
                )
            }

            Text(evidenceSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if run.macroID == nil {
                Label(String(localized: "No macro package evidence for this task", table: "Common"), systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading evidence", tableName: "Common")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let payload {
                evidencePayloadContent(payload)
            } else if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(String(localized: "Evidence has not been loaded", table: "Common"), systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            if actionFeedback == nil {
                actionFeedback = initialActionFeedback
            }
        }
        .onChange(of: payload?.reportURL) {
            actionFeedback = initialActionFeedback
        }
    }

    private var loadButtonTitle: String {
        payload == nil
            ? String(localized: "Load Evidence", table: "Common")
            : String(localized: "Reload Evidence", table: "Common")
    }

    private var evidenceTitle: String {
        switch payload?.source {
        case .perRun:
            return String(localized: "Run evidence", table: "Common")
        case .latestMatchingRun:
            return String(localized: "Latest macro evidence", table: "Common")
        case .latestMacro:
            return String(localized: "Latest macro evidence", table: "Common")
        case nil:
            return run.evidenceID == nil
                ? String(localized: "Latest macro evidence", table: "Common")
                : String(localized: "Run evidence", table: "Common")
        }
    }

    private var evidenceSummary: String {
        switch payload?.source {
        case .perRun:
            return String(localized: "Stable report loaded from this run evidence ID.", table: "Common")
        case .latestMatchingRun:
            return String(localized: "Legacy latest report matches this run ID.", table: "Common")
        case .latestMacro:
            return String(localized: "Latest saved report for this macro package.", table: "Common")
        case nil:
            return run.evidenceID == nil
                ? String(localized: "Latest saved report for this macro package.", table: "Common")
                : String(localized: "Loads the report bound to this run evidence ID.", table: "Common")
        }
    }

    @ViewBuilder
    private func evidencePayloadContent(_ payload: AutomationTaskRunEvidencePayload) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: String(localized: "Source", table: "Common"),
                value: sourceLabel(payload.source)
            )
            AutomationTaskRunEvidenceBindingView(run: run, payload: payload)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    evidenceFileButtons(payload)
                }
                VStack(alignment: .leading, spacing: 6) {
                    evidenceFileButtons(payload)
                }
            }
            if let actionFeedback {
                evidenceActionFeedbackView(actionFeedback)
            }
            if let manifest = payload.manifest {
                AutomationTaskRunEvidenceManifestView(manifest: manifest)
            }
            AutomationTaskRunDetailRowView(
                title: String(localized: "Report run", table: "Common"),
                value: shortID(payload.report.runID)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Result", table: "Common"),
                value: payload.report.isSuccess
                    ? String(localized: "Success", table: "Common")
                    : String(localized: "Failed", table: "Common")
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Started", table: "Common"),
                value: timeSummary(payload.report.startTime)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Duration", table: "Common"),
                value: durationLabel(payload.report.duration)
            )
            if let failedEventIndex = payload.report.failedEventIndex {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Failed event", table: "Common"),
                    value: String(format: String(localized: "#%d", table: "Common"), failedEventIndex + 1)
                )
            }
            if let errorMessage = payload.report.errorMessage,
               !errorMessage.isEmpty {
                AutomationTaskRunDetailRowView(
                    title: String(localized: "Error", table: "Common"),
                    value: errorMessage
                )
            }
            AutomationTaskRunEvidenceDiagnosticsView(run: run, payload: payload)
            if let screenshotData = payload.screenshotData {
                AutomationTaskRunEvidenceScreenshotPreviewView(
                    screenshotData: screenshotData,
                    loadedAt: payload.loadedAt
                )
            }
            AutomationTaskRunEvidenceReadinessView(run: run, payload: payload)
        }

        if payload.screenshotData == nil {
            Label(missingScreenshotLabel(for: payload), systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func evidenceFileButtons(_ payload: AutomationTaskRunEvidencePayload) -> some View {
        Button(String(localized: "Reveal Report", table: "Common"), systemImage: "doc.text.magnifyingglass") {
            actionFeedback = AutomationTaskRunEvidencePresenter.revealReport(payload.reportURL)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        if let screenshotURL = payload.screenshotURL {
            Button(String(localized: "Open Screenshot", table: "Common"), systemImage: "photo") {
                actionFeedback = AutomationTaskRunEvidencePresenter.openScreenshot(screenshotURL)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func evidenceActionFeedbackView(
        _ feedback: AutomationTaskRunEvidenceActionFeedback
    ) -> some View {
        Label(actionFeedbackMessage(feedback), systemImage: actionFeedbackSystemImage(feedback))
            .font(.caption)
            .foregroundStyle(actionFeedbackTint(feedback))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(actionFeedbackMessage(feedback))
    }

    private func timeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, duration)
        if seconds < 10 {
            return String(format: String(localized: "%.1fs", table: "Common"), seconds)
        }
        return String(format: String(localized: "%.0fs", table: "Common"), seconds.rounded())
    }

    private func missingScreenshotLabel(for payload: AutomationTaskRunEvidencePayload) -> String {
        payload.screenshotURL == nil
            ? String(localized: "No screenshot saved", table: "Common")
            : String(localized: "Screenshot preview unavailable", table: "Common")
    }

    private func actionFeedbackMessage(_ feedback: AutomationTaskRunEvidenceActionFeedback) -> String {
        switch feedback {
        case .succeeded(.revealReport):
            return String(localized: "Report revealed in Finder.", table: "Common")
        case .succeeded(.openScreenshot):
            return String(localized: "Screenshot opened in the default image viewer.", table: "Common")
        case .failed(.revealReport, let message), .failed(.openScreenshot, let message):
            return message
        }
    }

    private func actionFeedbackSystemImage(_ feedback: AutomationTaskRunEvidenceActionFeedback) -> String {
        switch feedback {
        case .succeeded(.revealReport):
            return "folder.badge.gearshape"
        case .succeeded(.openScreenshot):
            return "photo.badge.checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func actionFeedbackTint(_ feedback: AutomationTaskRunEvidenceActionFeedback) -> Color {
        switch feedback {
        case .succeeded:
            return Brand.libraryGreen
        case .failed:
            return Brand.sigAmber
        }
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }

    private func sourceLabel(_ source: AutomationTaskRunEvidenceSource) -> String {
        switch source {
        case .perRun:
            return String(localized: "Per-run", table: "Common")
        case .latestMatchingRun:
            return String(localized: "Latest match", table: "Common")
        case .latestMacro:
            return String(localized: "Latest macro", table: "Common")
        }
    }
}

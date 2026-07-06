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
                    title: NSLocalizedString("Evidence ID", comment: ""),
                    value: shortID(evidenceID)
                )
            }

            Text(evidenceSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if run.macroID == nil {
                Label(NSLocalizedString("No macro package evidence for this task", comment: ""), systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(NSLocalizedString("Loading evidence", comment: ""))
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
                Label(NSLocalizedString("Evidence has not been loaded", comment: ""), systemImage: "doc.text.magnifyingglass")
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
            ? NSLocalizedString("Load Evidence", comment: "")
            : NSLocalizedString("Reload Evidence", comment: "")
    }

    private var evidenceTitle: String {
        switch payload?.source {
        case .perRun:
            return NSLocalizedString("Run evidence", comment: "")
        case .latestMatchingRun:
            return NSLocalizedString("Latest macro evidence", comment: "")
        case .latestMacro:
            return NSLocalizedString("Latest macro evidence", comment: "")
        case nil:
            return run.evidenceID == nil
                ? NSLocalizedString("Latest macro evidence", comment: "")
                : NSLocalizedString("Run evidence", comment: "")
        }
    }

    private var evidenceSummary: String {
        switch payload?.source {
        case .perRun:
            return NSLocalizedString("Stable report loaded from this run evidence ID.", comment: "")
        case .latestMatchingRun:
            return NSLocalizedString("Legacy latest report matches this run ID.", comment: "")
        case .latestMacro:
            return NSLocalizedString("Latest saved report for this macro package.", comment: "")
        case nil:
            return run.evidenceID == nil
                ? NSLocalizedString("Latest saved report for this macro package.", comment: "")
                : NSLocalizedString("Loads the report bound to this run evidence ID.", comment: "")
        }
    }

    @ViewBuilder
    private func evidencePayloadContent(_ payload: AutomationTaskRunEvidencePayload) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Source", comment: ""),
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
                title: NSLocalizedString("Report run", comment: ""),
                value: shortID(payload.report.runID)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Result", comment: ""),
                value: payload.report.isSuccess
                    ? NSLocalizedString("Success", comment: "")
                    : NSLocalizedString("Failed", comment: "")
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Started", comment: ""),
                value: timeSummary(payload.report.startTime)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Duration", comment: ""),
                value: durationLabel(payload.report.duration)
            )
            if let failedEventIndex = payload.report.failedEventIndex {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Failed event", comment: ""),
                    value: String(format: NSLocalizedString("#%d", comment: ""), failedEventIndex + 1)
                )
            }
            if let errorMessage = payload.report.errorMessage,
               !errorMessage.isEmpty {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Error", comment: ""),
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
        Button(NSLocalizedString("Reveal Report", comment: ""), systemImage: "doc.text.magnifyingglass") {
            actionFeedback = AutomationTaskRunEvidencePresenter.revealReport(payload.reportURL)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        if let screenshotURL = payload.screenshotURL {
            Button(NSLocalizedString("Open Screenshot", comment: ""), systemImage: "photo") {
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
            return String(format: NSLocalizedString("%.1fs", comment: ""), seconds)
        }
        return String(format: NSLocalizedString("%.0fs", comment: ""), seconds.rounded())
    }

    private func missingScreenshotLabel(for payload: AutomationTaskRunEvidencePayload) -> String {
        payload.screenshotURL == nil
            ? NSLocalizedString("No screenshot saved", comment: "")
            : NSLocalizedString("Screenshot preview unavailable", comment: "")
    }

    private func actionFeedbackMessage(_ feedback: AutomationTaskRunEvidenceActionFeedback) -> String {
        switch feedback {
        case .succeeded(.revealReport):
            return NSLocalizedString("Report revealed in Finder.", comment: "")
        case .succeeded(.openScreenshot):
            return NSLocalizedString("Screenshot opened in the default image viewer.", comment: "")
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
            return NSLocalizedString("Per-run", comment: "")
        case .latestMatchingRun:
            return NSLocalizedString("Latest match", comment: "")
        case .latestMacro:
            return NSLocalizedString("Latest macro", comment: "")
        }
    }
}

import SwiftUI
import SparkleRecorderCore

struct MacroRunEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let macro: SavedMacro

    @State private var payload: AutomationTaskRunEvidencePayload?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Brand.libraryBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest run", tableName: "Automation")
                        .font(.headline)
                    Text(macro.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(String(localized: "Done", table: "Common")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView(
                        String(localized: "Could not load the latest run", table: "Automation"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if let payload {
                    evidence(payload)
                } else {
                    ContentUnavailableView(
                        String(localized: "No runs yet", table: "Automation"),
                        systemImage: "clock.badge.questionmark",
                        description: Text("Preview or run this macro to create a report and ending screenshot.", tableName: "Automation")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
        }
        .frame(width: 520, height: 430)
        .task(id: macro.id) { await load() }
    }

    private func evidence(_ payload: AutomationTaskRunEvidencePayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    payload.report.isSuccess
                        ? String(localized: "Completed", table: "Automation")
                        : String(localized: "Failed", table: "Common"),
                    systemImage: payload.report.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(payload.report.isSuccess ? Brand.libraryGreen : .red)
                .font(.headline)
                Spacer()
                Text(payload.report.startTime, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }

            LabeledContent(String(localized: "Duration", table: "Common")) {
                Text(payload.report.duration, format: .number.precision(.fractionLength(1))) + Text("s")
            }

            if let error = payload.report.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let screenshotData = payload.screenshotData {
                AutomationTaskRunEvidenceScreenshotPreviewView(
                    screenshotData: screenshotData,
                    loadedAt: payload.loadedAt
                )
            } else {
                Label(
                    String(localized: "The report was saved, but no ending screenshot was captured.", table: "Automation"),
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()
            HStack {
                Button {
                    _ = AutomationTaskRunEvidencePresenter.revealReport(payload.reportURL)
                } label: {
                    Label(String(localized: "Show report", table: "Automation"), systemImage: "doc.text.magnifyingglass")
                }
                if let screenshotURL = payload.screenshotURL {
                    Button {
                        _ = AutomationTaskRunEvidencePresenter.openScreenshot(screenshotURL)
                    } label: {
                        Label(String(localized: "Open screenshot", table: "Common"), systemImage: "photo")
                    }
                }
                Spacer()
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await AutomationTaskRunEvidencePresenter.loadLatestEvidence(macroID: macro.id)
            guard !Task.isCancelled else { return }
            payload = loaded
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            payload = nil
        }
        isLoading = false
    }
}

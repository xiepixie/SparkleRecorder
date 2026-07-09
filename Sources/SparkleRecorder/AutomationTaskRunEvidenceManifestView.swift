import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceManifestView: View {
    let manifest: RunEvidenceManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: String(localized: "Evidence created", table: "Common"),
                value: timeSummary(manifest.createdAt)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Manifest run", table: "Common"),
                value: shortID(manifest.runID)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Macro", table: "EditorUX"),
                value: shortID(manifest.macroID)
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Report file", table: "Common"),
                value: manifest.reportFilename
            )
            AutomationTaskRunDetailRowView(
                title: String(localized: "Screenshot file", table: "Common"),
                value: manifest.screenshotFilename ?? String(localized: "None", table: "Common")
            )
        }
    }

    private func timeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceManifestView: View {
    let manifest: RunEvidenceManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Evidence created", comment: ""),
                value: timeSummary(manifest.createdAt)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Manifest run", comment: ""),
                value: shortID(manifest.runID)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Macro", comment: ""),
                value: shortID(manifest.macroID)
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Report file", comment: ""),
                value: manifest.reportFilename
            )
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Screenshot file", comment: ""),
                value: manifest.screenshotFilename ?? NSLocalizedString("None", comment: "")
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

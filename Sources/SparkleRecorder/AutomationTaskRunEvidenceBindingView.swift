import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceBindingView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: String(localized: "Binding", table: "Common"),
                value: bindingLabel
            )

            if let bindingWarning {
                Label(bindingWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bindingLabel: String {
        switch payload.source {
        case .perRun:
            guard payload.manifest != nil else {
                return String(localized: "Report file", table: "Common")
            }
            return bindingWarning == nil
                ? String(localized: "Verified", table: "Common")
                : String(localized: "Needs review", table: "Common")
        case .latestMatchingRun:
            return String(localized: "Legacy latest match", table: "Common")
        case .latestMacro:
            return String(localized: "Latest macro only", table: "Common")
        }
    }

    private var bindingWarning: String? {
        if let evidenceID = run.evidenceID,
           let manifest = payload.manifest,
           manifest.evidenceID != evidenceID {
            return String(localized: "Manifest evidence ID does not match this run.", table: "Common")
        }

        if let manifest = payload.manifest,
           manifest.runID != payload.report.runID {
            return String(localized: "Manifest run ID does not match the report.", table: "Common")
        }

        if let evidenceID = run.evidenceID,
           payload.report.runID != evidenceID,
           payload.source != .latestMacro {
            return String(localized: "Report run ID does not match this run.", table: "Common")
        }

        return nil
    }
}

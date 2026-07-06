import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceBindingView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AutomationTaskRunDetailRowView(
                title: NSLocalizedString("Binding", comment: ""),
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
                return NSLocalizedString("Report file", comment: "")
            }
            return bindingWarning == nil
                ? NSLocalizedString("Verified", comment: "")
                : NSLocalizedString("Needs review", comment: "")
        case .latestMatchingRun:
            return NSLocalizedString("Legacy latest match", comment: "")
        case .latestMacro:
            return NSLocalizedString("Latest macro only", comment: "")
        }
    }

    private var bindingWarning: String? {
        if let evidenceID = run.evidenceID,
           let manifest = payload.manifest,
           manifest.evidenceID != evidenceID {
            return NSLocalizedString("Manifest evidence ID does not match this run.", comment: "")
        }

        if let manifest = payload.manifest,
           manifest.runID != payload.report.runID {
            return NSLocalizedString("Manifest run ID does not match the report.", comment: "")
        }

        if let evidenceID = run.evidenceID,
           payload.report.runID != evidenceID,
           payload.source != .latestMacro {
            return NSLocalizedString("Report run ID does not match this run.", comment: "")
        }

        return nil
    }
}

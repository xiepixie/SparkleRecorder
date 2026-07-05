import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunHistoryView: View {
    let runs: [AutomationTaskRun]

    var body: some View {
        let visibleRuns = runs.prefix(5)

        VStack(alignment: .leading, spacing: 10) {
            AutomationSectionHeader(
                title: NSLocalizedString("RUN HISTORY", comment: ""),
                count: runs.count
            )

            if runs.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("No task runs yet", comment: ""))
                            .font(.caption)
                            .bold()
                        Text(NSLocalizedString("Manual or scheduled runs will appear here with timing, outcome, and evidence.", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleRuns) { run in
                        AutomationTaskRunRowView(run: run)
                        if run.id != visibleRuns.last?.id {
                            Divider().opacity(0.45)
                        }
                    }
                }

                if runs.count > visibleRuns.count {
                    Text(String(format: NSLocalizedString("%d older runs hidden", comment: ""), runs.count - visibleRuns.count))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .sectionSurface(cornerRadius: 10)
    }
}

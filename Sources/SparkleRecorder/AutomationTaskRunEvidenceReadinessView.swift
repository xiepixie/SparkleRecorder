import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceReadinessView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AutomationSectionHeader(
                title: NSLocalizedString("DRILL-IN READINESS", comment: ""),
                count: rows.count
            )

            ForEach(rows) { row in
                readinessRow(row)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func readinessRow(_ row: ReadinessRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(row.title, systemImage: row.systemImage)
                    .foregroundStyle(row.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(row.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(row.tint.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(row.tint.opacity(0.14), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var rows: [ReadinessRow] {
        [
            ReadinessRow(
                id: "visual-diagnostics",
                title: NSLocalizedString("Visual diagnostics", comment: ""),
                status: diagnosticsStatus,
                detail: diagnosticsDetail,
                systemImage: diagnosticsSystemImage,
                tint: hasConditionDiagnostics ? Brand.libraryGreen : Brand.sigAmber
            ),
            ReadinessRow(
                id: "branch-evidence",
                title: NSLocalizedString("Branch evidence", comment: ""),
                status: branchStatus,
                detail: branchDetail,
                systemImage: "arrow.triangle.branch",
                tint: hasDurableBranchEvidence ? Brand.libraryGreen : .secondary
            ),
            ReadinessRow(
                id: "file-actions",
                title: NSLocalizedString("File actions", comment: ""),
                status: fileActionStatus,
                detail: fileActionDetail,
                systemImage: "folder.badge.gearshape",
                tint: payload.screenshotURL == nil ? Brand.sigAmber : Brand.libraryGreen
            )
        ]
    }

    private var hasDurableBranchEvidence: Bool {
        !(run.branchEvidence ?? []).isEmpty
    }

    private var hasConditionDiagnostics: Bool {
        run.conditionEvidence != nil
    }

    private var diagnosticsStatus: String {
        hasConditionDiagnostics
            ? NSLocalizedString("Durable", comment: "")
            : NSLocalizedString("Missing payload", comment: "")
    }

    private var diagnosticsSystemImage: String {
        hasConditionDiagnostics ? "eye" : "eye.slash"
    }

    private var diagnosticsDetail: String {
        guard let evidence = run.conditionEvidence else {
            return NSLocalizedString("No watched region, last sample, OCR text, pixel color, template score, or crop reference is saved in this run yet.", comment: "")
        }

        var parts = [
            evidence.observedSummary,
            String(format: NSLocalizedString("%d samples", comment: ""), evidence.sampleCount)
        ]
        if let score = evidence.score {
            parts.append(String(format: NSLocalizedString("score %.2f", comment: ""), score))
        }
        if let threshold = evidence.threshold {
            parts.append(String(format: NSLocalizedString("threshold %.2f", comment: ""), threshold))
        }
        if !evidence.artifacts.isEmpty {
            parts.append(String(
                format: NSLocalizedString("%d artifacts", comment: ""),
                evidence.artifacts.count
            ))
        }
        return parts.joined(separator: " | ")
    }

    private var branchStatus: String {
        if hasDurableBranchEvidence {
            return NSLocalizedString("Durable", comment: "")
        }

        switch payload.source {
        case .perRun:
            return NSLocalizedString("No branch payload", comment: "")
        case .latestMatchingRun, .latestMacro:
            return NSLocalizedString("No durable binding", comment: "")
        }
    }

    private var branchDetail: String {
        if let branchEvidence = run.branchEvidence,
           !branchEvidence.isEmpty {
            return String(
                format: NSLocalizedString("%d branch decisions are persisted on this run history record; the Branch Evidence section shows trigger, target run, delay, join policy, and reason.", comment: ""),
                branchEvidence.count
            )
        }

        return NSLocalizedString("This report has no persisted branch decisions for the selected run. Older or branchless runs may still show projection context outside the macro evidence report.", comment: "")
    }

    private var fileActionStatus: String {
        payload.screenshotURL == nil
            ? NSLocalizedString("Report only", comment: "")
            : NSLocalizedString("Ready", comment: "")
    }

    private var fileActionDetail: String {
        if payload.screenshotURL == nil {
            return NSLocalizedString("Reveal Report can locate the bound report file in Finder. No failure screenshot is available for Open Screenshot.", comment: "")
        }
        return NSLocalizedString("Reveal Report locates the bound report in Finder; Open Screenshot opens the saved failure image in the default viewer and reports failure if the file is gone.", comment: "")
    }

    private struct ReadinessRow: Identifiable {
        let id: String
        let title: String
        let status: String
        let detail: String
        let systemImage: String
        let tint: Color
    }
}

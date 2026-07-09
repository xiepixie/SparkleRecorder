import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunEvidenceReadinessView: View {
    let run: AutomationTaskRun
    let payload: AutomationTaskRunEvidencePayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AutomationSectionHeader(
                title: String(localized: "DRILL-IN READINESS", table: "Common"),
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
                title: String(localized: "Visual diagnostics", table: "Common"),
                status: diagnosticsStatus,
                detail: diagnosticsDetail,
                systemImage: diagnosticsSystemImage,
                tint: hasConditionDiagnostics ? Brand.libraryGreen : Brand.sigAmber
            ),
            ReadinessRow(
                id: "branch-evidence",
                title: String(localized: "Branch evidence", table: "Common"),
                status: branchStatus,
                detail: branchDetail,
                systemImage: "arrow.triangle.branch",
                tint: hasDurableBranchEvidence ? Brand.libraryGreen : .secondary
            ),
            ReadinessRow(
                id: "file-actions",
                title: String(localized: "File actions", table: "Common"),
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
            ? String(localized: "Durable", table: "Common")
            : String(localized: "Missing payload", table: "Common")
    }

    private var diagnosticsSystemImage: String {
        hasConditionDiagnostics ? "eye" : "eye.slash"
    }

    private var diagnosticsDetail: String {
        guard let evidence = run.conditionEvidence else {
            return String(localized: "No watched region, last sample, OCR text, pixel color, template score, or crop reference is saved in this run yet.", table: "Common")
        }

        var parts = [
            evidence.observedSummary,
            String(format: String(localized: "%d samples", table: "Common"), evidence.sampleCount)
        ]
        if let score = evidence.score {
            parts.append(String(format: String(localized: "score %.2f", table: "Common"), score))
        }
        if let threshold = evidence.threshold {
            parts.append(String(format: String(localized: "threshold %.2f", table: "Common"), threshold))
        }
        if !evidence.artifacts.isEmpty {
            parts.append(String(
                format: String(localized: "%d artifacts", table: "Common"),
                evidence.artifacts.count
            ))
        }
        return parts.joined(separator: " | ")
    }

    private var branchStatus: String {
        if hasDurableBranchEvidence {
            return String(localized: "Durable", table: "Common")
        }

        switch payload.source {
        case .perRun:
            return String(localized: "No branch payload", table: "Common")
        case .latestMatchingRun, .latestMacro:
            return String(localized: "No durable binding", table: "Common")
        }
    }

    private var branchDetail: String {
        if let branchEvidence = run.branchEvidence,
           !branchEvidence.isEmpty {
            return String(
                format: String(localized: "%d branch decisions are persisted on this run history record; the Branch Evidence section shows trigger, target run, delay, join policy, and reason.", table: "Common"),
                branchEvidence.count
            )
        }

        return String(localized: "This report has no persisted branch decisions for the selected run. Older or branchless runs may still show projection context outside the macro evidence report.", table: "Common")
    }

    private var fileActionStatus: String {
        payload.screenshotURL == nil
            ? String(localized: "Report only", table: "Common")
            : String(localized: "Ready", table: "Common")
    }

    private var fileActionDetail: String {
        if payload.screenshotURL == nil {
            return String(localized: "Reveal Report can locate the bound report file in Finder. No failure screenshot is available for Open Screenshot.", table: "Common")
        }
        return String(localized: "Reveal Report locates the bound report in Finder; Open Screenshot opens the saved failure image in the default viewer and reports failure if the file is gone.", table: "Common")
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

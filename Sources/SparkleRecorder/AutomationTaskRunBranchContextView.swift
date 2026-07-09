import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunBranchContextView: View {
    let run: AutomationTaskRun
    let workflow: AutomationWorkflow
    let dependencyEdges: [AutomationDependencyEdgeProjection]

    var body: some View {
        let rows = branchRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                AutomationSectionHeader(
                    title: hasDurableEvidence
                        ? String(localized: "BRANCH EVIDENCE", table: "Common")
                        : String(localized: "BRANCH CONTEXT", table: "Common"),
                    count: rows.count
                )

                Text(hasDurableEvidence
                    ? String(localized: "Persisted on this run", table: "Common")
                    : String(localized: "Projection fallback", table: "Common"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                ForEach(rows) { row in
                    branchRow(row)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func branchRow(_ row: BranchContextRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(row.relationshipLabel, systemImage: row.relationshipIcon)
                    .foregroundStyle(row.relationshipTint)

                Text(row.pathLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            AutomationTaskBranchDecisionSummaryView(decision: row.decision)

            if let evidence = row.evidence {
                AutomationTaskRunBranchEvidenceDetailsView(evidence: evidence)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(row.relationshipTint.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(row.relationshipTint.opacity(0.16), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var branchRows: [BranchContextRow] {
        let durableRows = durableBranchRows
        if !durableRows.isEmpty {
            return durableRows
        }

        return dependencyEdges.compactMap { edge in
            guard let decision = edge.branchDecision,
                  decision.sourceRunID == run.id || decision.targetRunID == run.id else {
                return nil
            }

            return BranchContextRow(
                id: edge.id,
                decision: decision,
                relationship: decision.targetRunID == run.id ? .incoming : .outgoing,
                fromTaskName: taskName(edge.fromTaskID),
                toTaskName: taskName(edge.toTaskID),
                triggerLabel: edge.triggerLabel,
                evidence: nil
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.decision.decidedAt ?? .distantPast
            let rhsDate = rhs.decision.decidedAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.pathLabel < rhs.pathLabel
            }
            return lhsDate > rhsDate
        }
    }

    private var hasDurableEvidence: Bool {
        !(run.branchEvidence ?? []).isEmpty
    }

    private var durableBranchRows: [BranchContextRow] {
        let edgeByID = Dictionary(uniqueKeysWithValues: dependencyEdges.map { ($0.id, $0) })
        return (run.branchEvidence ?? []).map { evidence in
            let edge = edgeByID[evidence.dependencyID]
            return BranchContextRow(
                id: evidence.dependencyID,
                decision: AutomationBranchDecisionProjection(
                    sourceRunID: evidence.sourceRunID,
                    targetRunID: evidence.targetRunID,
                    executionID: evidence.executionID,
                    decidedAt: evidence.decidedAt,
                    status: evidence.status,
                    outcomeLabel: outcomeLabel(for: evidence.sourceOutcome),
                    detail: evidence.reason
                ),
                relationship: evidence.targetRunID == run.id ? .incoming : .outgoing,
                fromTaskName: taskName(evidence.sourceTaskID),
                toTaskName: taskName(evidence.targetTaskID),
                triggerLabel: edge?.triggerLabel ?? triggerLabel(for: evidence.trigger),
                evidence: evidence
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.decision.decidedAt ?? .distantPast
            let rhsDate = rhs.decision.decidedAt ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.pathLabel < rhs.pathLabel
            }
            return lhsDate > rhsDate
        }
    }

    private func taskName(_ taskID: UUID) -> String {
        workflow.task(id: taskID)?.name ?? String(localized: "Missing task", table: "Automation")
    }

    private struct BranchContextRow: Identifiable {
        enum Relationship {
            case incoming
            case outgoing
        }

        let id: UUID
        let decision: AutomationBranchDecisionProjection
        let relationship: Relationship
        let fromTaskName: String
        let toTaskName: String
        let triggerLabel: String
        let evidence: AutomationBranchDecisionEvidence?

        var relationshipLabel: String {
            switch relationship {
            case .incoming:
                return String(localized: "Started by branch", table: "Common")
            case .outgoing:
                return String(localized: "Decision from this run", table: "Common")
            }
        }

        var relationshipIcon: String {
            switch relationship {
            case .incoming:
                return "arrow.down.right.circle"
            case .outgoing:
                return "arrow.triangle.branch"
            }
        }

        var relationshipTint: Color {
            switch relationship {
            case .incoming:
                return Brand.libraryBlue
            case .outgoing:
                return decision.status == .triggered ? Brand.libraryGreen : .secondary
            }
        }

        var pathLabel: String {
            "\(fromTaskName) -> \(toTaskName) · \(triggerLabel)"
        }
    }

    private func triggerLabel(for trigger: AutomationDependencyTrigger) -> String {
        switch trigger {
        case .onSuccess:
            return String(localized: "On success", table: "Common")
        case .onFailure:
            return String(localized: "On failure", table: "Common")
        case .onTimeout:
            return String(localized: "On timeout", table: "Common")
        case .onCancelled:
            return String(localized: "On cancel", table: "Common")
        case .onConditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .onConditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .onOutcome(let predicate):
            return predicateLabel(for: predicate)
        case .always:
            return String(localized: "Always", table: "Common")
        }
    }

    private func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            return String(localized: "Success", table: "Common")
        case .failure:
            return String(localized: "Failure", table: "Common")
        case .timeout:
            return String(localized: "Timeout", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .anyTerminal:
            return String(localized: "Any terminal outcome", table: "Common")
        }
    }

    private func outcomeLabel(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return String(localized: "Success", table: "Common")
        case .failed:
            return String(localized: "Failure", table: "Common")
        case .cancelled:
            return String(localized: "Cancelled", table: "Common")
        case .timedOut:
            return String(localized: "Timeout", table: "Common")
        case .resourceConflict:
            return String(localized: "Resource conflict", table: "Common")
        case .permissionDenied:
            return String(localized: "Permission denied", table: "Settings")
        case .conditionMatched:
            return String(localized: "Condition matched", table: "Automation")
        case .conditionNotMatched:
            return String(localized: "Condition not matched", table: "Automation")
        case .missingMacro:
            return String(localized: "Missing macro", table: "EditorUX")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
        }
    }
}

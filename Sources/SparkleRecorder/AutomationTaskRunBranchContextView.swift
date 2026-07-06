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
                        ? NSLocalizedString("BRANCH EVIDENCE", comment: "")
                        : NSLocalizedString("BRANCH CONTEXT", comment: ""),
                    count: rows.count
                )

                Text(hasDurableEvidence
                    ? NSLocalizedString("Persisted on this run", comment: "")
                    : NSLocalizedString("Projection fallback", comment: ""))
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
        workflow.task(id: taskID)?.name ?? NSLocalizedString("Missing task", comment: "")
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
                return NSLocalizedString("Started by branch", comment: "")
            case .outgoing:
                return NSLocalizedString("Decision from this run", comment: "")
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
            return NSLocalizedString("On success", comment: "")
        case .onFailure:
            return NSLocalizedString("On failure", comment: "")
        case .onTimeout:
            return NSLocalizedString("On timeout", comment: "")
        case .onCancelled:
            return NSLocalizedString("On cancel", comment: "")
        case .onConditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .onConditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .onOutcome(let predicate):
            return predicateLabel(for: predicate)
        case .always:
            return NSLocalizedString("Always", comment: "")
        }
    }

    private func predicateLabel(for predicate: AutomationOutcomePredicate) -> String {
        switch predicate {
        case .success:
            return NSLocalizedString("Success", comment: "")
        case .failure:
            return NSLocalizedString("Failure", comment: "")
        case .timeout:
            return NSLocalizedString("Timeout", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .anyTerminal:
            return NSLocalizedString("Any terminal outcome", comment: "")
        }
    }

    private func outcomeLabel(for outcome: AutomationOutcome) -> String {
        switch outcome {
        case .succeeded:
            return NSLocalizedString("Success", comment: "")
        case .failed:
            return NSLocalizedString("Failure", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled", comment: "")
        case .timedOut:
            return NSLocalizedString("Timeout", comment: "")
        case .resourceConflict:
            return NSLocalizedString("Resource conflict", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Permission denied", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Condition matched", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Condition not matched", comment: "")
        case .missingMacro:
            return NSLocalizedString("Missing macro", comment: "")
        case .rejected:
            return NSLocalizedString("Rejected", comment: "")
        }
    }
}

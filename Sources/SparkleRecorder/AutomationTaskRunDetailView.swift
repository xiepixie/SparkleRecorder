import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunDetailView: View {
    let run: AutomationTaskRun
    let workflow: AutomationWorkflow
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let display: AutomationTaskRunDisplay
    let retryPolicy: AutomationRetryPolicy
    let hasLaterAttempt: Bool

    @State private var evidencePayload: AutomationTaskRunEvidencePayload?
    @State private var evidenceErrorMessage = ""
    @State private var isLoadingEvidence = false
    @State private var evidenceRequestRunID: UUID?
    @Environment(\.automationTaskRunEvidenceMacroPackageBaseURL) private var macroPackageBaseURL
    @Environment(\.automationTaskRunEvidenceAutoload) private var shouldAutoloadEvidence
    @Environment(\.automationTaskRunEvidenceInitialActionFeedback) private var initialEvidenceActionFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(display.title, systemImage: display.systemImage)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(display.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(display.primaryDate, style: .time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Text(display.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let conditionEvidence = run.conditionEvidence {
                AutomationTaskRunConditionEvidenceView(evidence: conditionEvidence)
            }

            VStack(alignment: .leading, spacing: 5) {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Run", comment: ""),
                    value: shortID(run.id)
                )
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Execution", comment: ""),
                    value: shortID(run.executionID)
                )
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Attempt", comment: ""),
                    value: attemptSummary
                )
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Upstream", comment: ""),
                    value: upstreamSummary
                )
                if let macroID = run.macroID {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Macro", comment: ""),
                        value: shortID(macroID)
                    )
                }
                if let leaseID = run.leaseID {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Lease", comment: ""),
                        value: shortID(leaseID)
                    )
                }
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 5) {
                AutomationTaskRunDetailRowView(
                    title: NSLocalizedString("Created", comment: ""),
                    value: timeSummary(run.createdAt)
                )
                if let scheduledStartTime = run.scheduledStartTime {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Scheduled", comment: ""),
                        value: timeSummary(scheduledStartTime)
                    )
                }
                if let earliestStartTime = run.earliestStartTime {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Ready", comment: ""),
                        value: timeSummary(earliestStartTime)
                    )
                }
                if let actualStartTime = run.actualStartTime {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Started", comment: ""),
                        value: timeSummary(actualStartTime)
                    )
                }
                if let completedAt = run.completedAt {
                    AutomationTaskRunDetailRowView(
                        title: NSLocalizedString("Completed", comment: ""),
                        value: timeSummary(completedAt)
                    )
                }
            }

            AutomationTaskRunBranchContextView(
                run: run,
                workflow: workflow,
                dependencyEdges: dependencyEdges
            )

            if run.evidenceID != nil || run.macroID != nil {
                Divider().opacity(0.45)

                AutomationTaskRunEvidenceSectionView(
                    run: run,
                    payload: evidencePayload,
                    isLoading: isLoadingEvidence,
                    errorMessage: evidenceErrorMessage,
                    initialActionFeedback: initialEvidenceActionFeedback,
                    onLoad: loadEvidence
                )
            }

            Divider().opacity(0.45)

            Label(nextCheckSummary, systemImage: nextCheckImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .automationSubsurface(cornerRadius: 8, tint: display.tint)
        .accessibilityElement(children: .contain)
        .onChange(of: run.id) {
            resetEvidence()
        }
        .task(id: run.id) {
            if shouldAutoloadEvidence,
               evidencePayload == nil,
               evidenceErrorMessage.isEmpty,
               !isLoadingEvidence {
                loadEvidence()
            }
        }
    }

    private var attemptSummary: String {
        let maxAttempts = retryPolicy.maxAttempts
        guard maxAttempts > 1 else {
            return String(format: NSLocalizedString("%d", comment: ""), run.attempt)
        }
        return String(
            format: NSLocalizedString("%d of %d", comment: ""),
            run.attempt,
            maxAttempts
        )
    }

    private var upstreamSummary: String {
        guard !run.upstreamRunIDs.isEmpty else {
            return NSLocalizedString("None", comment: "")
        }
        return String(format: NSLocalizedString("%d runs", comment: ""), run.upstreamRunIDs.count)
    }

    private var retryExhausted: Bool {
        guard retryPolicy.maxAttempts > 1,
              run.attempt >= retryPolicy.maxAttempts,
              !hasLaterAttempt else {
            return false
        }

        switch run.outcome {
        case .failed, .timedOut:
            return true
        case .succeeded, .cancelled, .resourceConflict, .permissionDenied, .conditionMatched,
             .conditionNotMatched, .missingMacro, .rejected, nil:
            return false
        }
    }

    private var nextCheckImage: String {
        retryExhausted ? "exclamationmark.triangle" : "wrench.and.screwdriver"
    }

    private var nextCheckSummary: String {
        if retryExhausted {
            return NSLocalizedString("No retry attempts remain. Review the failed step or timeout branch before running again.", comment: "")
        }

        guard let outcome = run.outcome else {
            switch run.status {
            case .planned:
                return NSLocalizedString("Waiting for its planned start.", comment: "")
            case .waitingForDependencies:
                return NSLocalizedString("Waiting for upstream work to finish.", comment: "")
            case .waitingForResource:
                return NSLocalizedString("Waiting for a required resource to become available.", comment: "")
            case .queued:
                return NSLocalizedString("Queued and ready for the runner.", comment: "")
            case .running:
                return NSLocalizedString("Running now; waiting for the next outcome.", comment: "")
            case .completed:
                return NSLocalizedString("Completed without a recorded outcome.", comment: "")
            }
        }

        switch outcome {
        case .succeeded:
            return NSLocalizedString("This run completed successfully.", comment: "")
        case .failed(let report):
            if let failedEventIndex = report?.failedEventIndex {
                return String(
                    format: NSLocalizedString("Review event #%d and its target window before retrying.", comment: ""),
                    failedEventIndex + 1
                )
            }
            return NSLocalizedString("Review the macro target, window context, and latest evidence before retrying.", comment: "")
        case .cancelled:
            return NSLocalizedString("Cancelled before completion; confirm whether this branch should stop or continue.", comment: "")
        case .timedOut:
            return NSLocalizedString("Check the timeout, watched condition, or timeout branch before retrying.", comment: "")
        case .resourceConflict:
            return NSLocalizedString("Check foreground input timing and resource priority.", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Grant the required permission before retrying.", comment: "")
        case .conditionMatched:
            return NSLocalizedString("Then branch is eligible after this condition.", comment: "")
        case .conditionNotMatched:
            return NSLocalizedString("Else branch is eligible after this condition.", comment: "")
        case .missingMacro:
            return NSLocalizedString("Reconnect the saved macro or replace this task.", comment: "")
        case .rejected:
            return NSLocalizedString("Fix the rejection reason before retrying.", comment: "")
        }
    }

    private func timeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }

    private func loadEvidence() {
        guard run.macroID != nil else {
            evidencePayload = nil
            evidenceErrorMessage = NSLocalizedString("This run has no macro package evidence.", comment: "")
            isLoadingEvidence = false
            return
        }

        let requestedRunID = run.id
        evidenceRequestRunID = requestedRunID
        isLoadingEvidence = true
        evidenceErrorMessage = ""

        Task {
            do {
                let payload = try await AutomationTaskRunEvidencePresenter.loadEvidence(
                    for: run,
                    macroPackageBaseURL: macroPackageBaseURL
                )
                guard evidenceRequestRunID == requestedRunID else {
                    return
                }
                evidencePayload = payload
                evidenceErrorMessage = payload == nil
                    ? noEvidenceMessage
                    : ""
                isLoadingEvidence = false
            } catch {
                guard evidenceRequestRunID == requestedRunID else {
                    return
                }
                evidencePayload = nil
                evidenceErrorMessage = String(
                    format: NSLocalizedString("Could not load evidence: %@", comment: ""),
                    String(describing: error)
                )
                isLoadingEvidence = false
            }
        }
    }

    private var noEvidenceMessage: String {
        if run.evidenceID != nil {
            return NSLocalizedString("No per-run evidence report found for this run yet.", comment: "")
        }
        return NSLocalizedString("No evidence report found for this macro.", comment: "")
    }

    private func resetEvidence() {
        evidencePayload = nil
        evidenceErrorMessage = ""
        isLoadingEvidence = false
        evidenceRequestRunID = nil
    }
}

private struct AutomationTaskRunEvidenceMacroPackageBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

private struct AutomationTaskRunEvidenceAutoloadKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AutomationTaskRunEvidenceInitialActionFeedbackKey: EnvironmentKey {
    static let defaultValue: AutomationTaskRunEvidenceActionFeedback? = nil
}

extension EnvironmentValues {
    var automationTaskRunEvidenceMacroPackageBaseURL: URL? {
        get { self[AutomationTaskRunEvidenceMacroPackageBaseURLKey.self] }
        set { self[AutomationTaskRunEvidenceMacroPackageBaseURLKey.self] = newValue }
    }

    var automationTaskRunEvidenceAutoload: Bool {
        get { self[AutomationTaskRunEvidenceAutoloadKey.self] }
        set { self[AutomationTaskRunEvidenceAutoloadKey.self] = newValue }
    }

    var automationTaskRunEvidenceInitialActionFeedback: AutomationTaskRunEvidenceActionFeedback? {
        get { self[AutomationTaskRunEvidenceInitialActionFeedbackKey.self] }
        set { self[AutomationTaskRunEvidenceInitialActionFeedbackKey.self] = newValue }
    }
}

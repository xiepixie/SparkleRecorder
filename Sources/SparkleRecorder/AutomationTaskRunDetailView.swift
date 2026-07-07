import SwiftUI
import SparkleRecorderCore

struct AutomationTaskRunDetailView: View {
    let run: AutomationTaskRun
    let workflow: AutomationWorkflow
    let dependencyEdges: [AutomationDependencyEdgeProjection]
    let display: AutomationTaskRunDisplay
    let retryPolicy: AutomationRetryPolicy
    let hasLaterAttempt: Bool
    var macros: [SavedMacro] = []
    var onImportWorkflowFromDraftPreview: (AutomationWorkflow, URL?) -> Void = { _, _ in }

    @State private var evidencePayload: AutomationTaskRunEvidencePayload?
    @State private var evidenceErrorMessage = ""
    @State private var isLoadingEvidence = false
    @State private var evidenceRequestRunID: UUID?
    @State private var semanticReviewState: SemanticRecordingReviewState?
    @State private var semanticReviewErrorMessage = ""
    @State private var isOpeningSemanticReview = false
    @State private var semanticReviewRequestRunID: UUID?
    @State private var semanticReviewInitialEventID: UUID?
    @State private var semanticReviewInitialFrameID: UUID?
    @State private var semanticReviewRunTargetPresentation: SemanticRecordingReviewRunTargetPresentation?
    @State private var semanticReviewRunTargetEvidence: SemanticRecordingReviewRunTargetEvidence?
    @State private var semanticReviewBundleFeedback: SemanticRecordingReviewArtifactActionFeedback?
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

            macroReviewSection

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
            resetSemanticReview()
        }
        .task(id: run.id) {
            if shouldAutoloadEvidence,
               evidencePayload == nil,
               evidenceErrorMessage.isEmpty,
               !isLoadingEvidence {
                loadEvidence()
            }
        }
        .sheet(item: $semanticReviewState) { state in
            SemanticRecordingReviewFixtureView(
                state: state,
                workflow: workflow,
                macros: macros,
                selectedEventID: semanticReviewInitialEventID,
                selectedFrameID: semanticReviewInitialFrameID,
                initialRunTargetPresentation: semanticReviewRunTargetPresentation,
                initialRunTargetEvidence: semanticReviewRunTargetEvidence,
                onImportWorkflow: onImportWorkflowFromDraftPreview
            )
                .frame(minWidth: 1_180, idealWidth: 1_280, minHeight: 760, idealHeight: 820)
        }
    }

    private var macroReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(NSLocalizedString("Macro Review", comment: ""), systemImage: "film.stack")
                    .font(.caption)
                    .bold()
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(
                    NSLocalizedString(macroReviewPresentation.buttonTitle(isOpening: isOpeningSemanticReview), comment: ""),
                    systemImage: "rectangle.stack.badge.play"
                ) {
                    openSemanticReview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isOpeningSemanticReview)

                if macroReviewPresentation.canRevealLinkedBundle {
                    Button("", systemImage: "arrow.up.right.square") {
                        revealLinkedSemanticReviewBundle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isOpeningSemanticReview)
                    .help(NSLocalizedString("Reveal linked Macro Review bundle", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Reveal linked Macro Review bundle", comment: ""))

                    Button("", systemImage: "folder") {
                        chooseSemanticReviewBundle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isOpeningSemanticReview)
                    .help(NSLocalizedString("Choose a different Macro Review bundle", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Choose a different Macro Review bundle", comment: ""))
                }
            }

            Text(localizedMacroReviewSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            macroReviewDecisionRows

            macroReviewReadiness

            if let reference = macroReviewPresentation.recordingReference {
                linkedSemanticRecordingDetails(reference)
            }

            if isOpeningSemanticReview {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(NSLocalizedString("Opening review bundle", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !semanticReviewErrorMessage.isEmpty {
                Label(semanticReviewErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Brand.sigAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let semanticReviewBundleFeedback {
                macroReviewFeedback(semanticReviewBundleFeedback)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.6)
                )
        )
    }

    private var macroReviewDecisionRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(macroReviewPresentation.decisionRows.enumerated()), id: \.offset) { _, row in
                macroReviewDecisionRow(row)
            }
        }
    }

    private func macroReviewDecisionRow(
        _ row: AutomationMacroReviewSourcePresentation.DecisionRow
    ) -> some View {
        let tint = macroReviewDecisionTint(row.tone)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(NSLocalizedString(row.title, comment: ""), systemImage: macroReviewDecisionImage(row.tone))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(NSLocalizedString(row.value, comment: ""))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)

            Text(NSLocalizedString(row.detail, comment: ""))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.13), lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private func macroReviewDecisionTint(
        _ tone: AutomationMacroReviewSourcePresentation.DecisionRow.Tone
    ) -> Color {
        switch tone {
        case .ready:
            return Brand.libraryGreen
        case .needsInput:
            return Brand.sigAmber
        case .reviewOnly:
            return Brand.libraryBlue
        }
    }

    private func macroReviewDecisionImage(
        _ tone: AutomationMacroReviewSourcePresentation.DecisionRow.Tone
    ) -> String {
        switch tone {
        case .ready:
            return "checkmark.circle"
        case .needsInput:
            return "exclamationmark.triangle"
        case .reviewOnly:
            return "lock.doc"
        }
    }

    private var macroReviewReadiness: some View {
        let badges = macroReviewPresentation.readinessBadges
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    macroReviewBadge(title: badge.title, value: badge.value)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    macroReviewBadge(title: badge.title, value: badge.value)
                }
            }
        }
    }

    private func linkedSemanticRecordingDetails(
        _ reference: MacroSemanticRecordingReference
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                macroReviewBadge(
                    title: NSLocalizedString("Recording", comment: ""),
                    value: shortID(reference.recordingID)
                )
                macroReviewBadge(
                    title: NSLocalizedString("Events", comment: ""),
                    value: "\(reference.eventCount)"
                )
                macroReviewBadge(
                    title: NSLocalizedString("Captured", comment: ""),
                    value: compactDate(reference.capturedAt)
                )
                macroReviewBadge(
                    title: NSLocalizedString("Manifest", comment: ""),
                    value: compactPath(reference.manifestRelativePath)
                )
            }
            VStack(alignment: .leading, spacing: 5) {
                macroReviewBadge(
                    title: NSLocalizedString("Recording", comment: ""),
                    value: shortID(reference.recordingID)
                )
                macroReviewBadge(
                    title: NSLocalizedString("Events", comment: ""),
                    value: "\(reference.eventCount)"
                )
                macroReviewBadge(
                    title: NSLocalizedString("Captured", comment: ""),
                    value: compactDate(reference.capturedAt)
                )
                macroReviewBadge(
                    title: NSLocalizedString("Manifest", comment: ""),
                    value: compactPath(reference.manifestRelativePath)
                )
            }
        }
    }

    private func macroReviewBadge(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString(title, comment: ""))
                .foregroundStyle(.tertiary)
            Text(NSLocalizedString(value, comment: ""))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }

    private func macroReviewFeedback(
        _ feedback: SemanticRecordingReviewArtifactActionFeedback
    ) -> some View {
        let presentation = semanticReviewFeedbackPresentation(feedback)
        return Label(presentation.message, systemImage: presentation.systemImage)
            .font(.caption)
            .foregroundStyle(presentation.tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var macroReviewPresentation: AutomationMacroReviewSourcePresentation {
        AutomationMacroReviewSourcePresentation.make(
            run: run,
            workflow: workflow,
            macros: macros
        )
    }

    private var localizedMacroReviewSummary: String {
        if let macroName = macroReviewPresentation.macroName,
           let reference = macroReviewPresentation.recordingReference {
            return String(
                format: NSLocalizedString(
                    "Open the semantic recording captured with %@. It includes %d timeline events; this run does not carry a separate semantic bundle yet.",
                    comment: ""
                ),
                macroName,
                reference.eventCount
            )
        }

        return NSLocalizedString(macroReviewPresentation.summary, comment: "")
    }

    private func semanticReviewFeedbackPresentation(
        _ feedback: SemanticRecordingReviewArtifactActionFeedback
    ) -> (message: String, systemImage: String, tint: Color) {
        switch feedback {
        case .succeeded(.open, let path):
            return (
                String(format: NSLocalizedString("Opened %@", comment: ""), compactPath(path)),
                "checkmark.circle",
                .secondary
            )
        case .succeeded(.reveal, let path):
            return (
                String(format: NSLocalizedString("Revealed %@", comment: ""), compactPath(path)),
                "checkmark.circle",
                .secondary
            )
        case .failed(.open, let message):
            return (
                String(format: NSLocalizedString("Open failed: %@", comment: ""), message),
                "exclamationmark.triangle",
                Brand.sigAmber
            )
        case .failed(.reveal, let message):
            return (
                String(format: NSLocalizedString("Reveal failed: %@", comment: ""), message),
                "exclamationmark.triangle",
                Brand.sigAmber
            )
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

    private func compactDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func compactPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 2 else {
            return path
        }
        return parts.suffix(2).joined(separator: "/")
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

    private func openSemanticReview() {
        semanticReviewBundleFeedback = nil
        if macroReviewPresentation.recordingReference != nil {
            openLinkedSemanticReview(macroReviewPresentation)
        } else {
            chooseSemanticReviewBundle()
        }
    }

    private func chooseSemanticReviewBundle() {
        let requestedRunID = run.id
        semanticReviewRequestRunID = requestedRunID
        isOpeningSemanticReview = true
        semanticReviewErrorMessage = ""
        semanticReviewBundleFeedback = nil
        SemanticRecordingReviewPresenter.openBundle { result in
            guard semanticReviewRequestRunID == requestedRunID else {
                return
            }
            isOpeningSemanticReview = false
            switch result {
            case .success(let state):
                presentSemanticReview(state)
            case .failure(let error):
                semanticReviewState = nil
                semanticReviewErrorMessage = String(
                    format: NSLocalizedString("Could not open Macro Review: %@", comment: ""),
                    String(describing: error)
                )
            }
        }
    }

    private func revealLinkedSemanticReviewBundle() {
        guard let reference = macroReviewPresentation.recordingReference else {
            return
        }
        semanticReviewErrorMessage = ""
        semanticReviewBundleFeedback = SemanticRecordingReviewPresenter.revealBundle(
            from: reference
        )
    }

    private func openLinkedSemanticReview(
        _ presentation: AutomationMacroReviewSourcePresentation
    ) {
        guard let reference = presentation.recordingReference else {
            chooseSemanticReviewBundle()
            return
        }
        let requestedRunID = run.id
        semanticReviewRequestRunID = requestedRunID
        isOpeningSemanticReview = true
        semanticReviewErrorMessage = ""
        semanticReviewBundleFeedback = nil
        Task {
            do {
                let state = try await SemanticRecordingReviewPresenter.reviewState(
                    from: reference,
                    sourceName: presentation.macroName ?? NSLocalizedString("Macro Review", comment: "")
                )
                await MainActor.run {
                    guard semanticReviewRequestRunID == requestedRunID else {
                        return
                    }
                    isOpeningSemanticReview = false
                    presentSemanticReview(state)
                }
            } catch {
                await MainActor.run {
                    guard semanticReviewRequestRunID == requestedRunID else {
                        return
                    }
                    isOpeningSemanticReview = false
                    semanticReviewState = nil
                    semanticReviewErrorMessage = String(
                        format: NSLocalizedString("Could not open linked Macro Review: %@", comment: ""),
                        String(describing: error)
                    )
                }
            }
        }
    }

    private func presentSemanticReview(_ state: SemanticRecordingReviewState) {
        let target = SemanticRecordingReviewRunTarget.make(
            run: run,
            bundle: state.bundle
        )
        semanticReviewInitialEventID = target.selectedEventID
        semanticReviewInitialFrameID = target.selectedFrameID
        semanticReviewRunTargetPresentation = .make(target: target)
        semanticReviewRunTargetEvidence = .make(target: target)
        semanticReviewState = state
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

    private func resetSemanticReview() {
        semanticReviewState = nil
        semanticReviewErrorMessage = ""
        isOpeningSemanticReview = false
        semanticReviewRequestRunID = nil
        semanticReviewInitialEventID = nil
        semanticReviewInitialFrameID = nil
        semanticReviewRunTargetPresentation = nil
        semanticReviewRunTargetEvidence = nil
        semanticReviewBundleFeedback = nil
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

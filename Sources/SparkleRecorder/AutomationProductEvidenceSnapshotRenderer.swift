import AppKit
import SwiftUI
import SparkleRecorderCore

enum AutomationProductEvidenceSnapshotScenario: String, CaseIterable {
    case idle
    case dragLinkAuthoring = "drag-link-authoring"
    case taskReorderAuthoring = "task-reorder-authoring"
    case running
    case failedRunDetail = "failed-run-detail"
    case failedRunPreviewUnavailable = "failed-run-preview-unavailable"
    case visualDiagnostics = "visual-diagnostics-drill-in"
    case branchEvidence = "branch-evidence"
    case templateBaselinePreviewRefs = "template-baseline-preview-refs"
    case semanticReviewTimeline = "semantic-review-timeline"
    case semanticReviewDraftPreview = "semantic-review-draft-preview"
    case semanticReviewRunDetail = "semantic-review-run-detail"

    init?(argument: String) {
        switch argument {
        case "idle", "idle-workflow":
            self = .idle
        case "drag-link", "drag-link-authoring":
            self = .dragLinkAuthoring
        case "task-reorder", "task-reorder-authoring", "reorder":
            self = .taskReorderAuthoring
        case "running", "running-workflow":
            self = .running
        case "failed-run", "failed-run-detail":
            self = .failedRunDetail
        case "failed-run-preview-unavailable", "preview-unavailable":
            self = .failedRunPreviewUnavailable
        case "visual-diagnostics", "visual-diagnostics-drill-in":
            self = .visualDiagnostics
        case "branch", "branch-evidence", "branch-evidence-drill-in":
            self = .branchEvidence
        case "template-baseline-preview-refs", "preview-refs", "semantic-preview-refs":
            self = .templateBaselinePreviewRefs
        case "semantic-review", "semantic-review-timeline", "review-timeline":
            self = .semanticReviewTimeline
        case "semantic-review-draft-preview", "review-draft-preview", "semantic-draft-preview":
            self = .semanticReviewDraftPreview
        case "semantic-review-run-detail", "review-run-detail", "macro-review-run-detail":
            self = .semanticReviewRunDetail
        default:
            return nil
        }
    }

    var filename: String {
        switch self {
        case .idle:
            return "idle-workflow.png"
        case .dragLinkAuthoring:
            return "drag-link-authoring.png"
        case .taskReorderAuthoring:
            return "task-reorder-authoring.png"
        case .running:
            return "running-workflow.png"
        case .failedRunDetail:
            return "failed-run-detail.png"
        case .failedRunPreviewUnavailable:
            return "failed-run-preview-unavailable.png"
        case .visualDiagnostics:
            return "visual-diagnostics-drill-in.png"
        case .branchEvidence:
            return "branch-evidence-drill-in.png"
        case .templateBaselinePreviewRefs:
            return "template-baseline-preview-refs.png"
        case .semanticReviewTimeline:
            return "semantic-review-timeline.png"
        case .semanticReviewDraftPreview:
            return "semantic-review-draft-preview.png"
        case .semanticReviewRunDetail:
            return "semantic-review-run-detail.png"
        }
    }

    var defaultHeight: Double {
        switch self {
        case .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .semanticReviewRunDetail:
            return 1_560
        case .branchEvidence:
            return 1_120
        case .templateBaselinePreviewRefs:
            return 980
        case .semanticReviewTimeline:
            return 1_040
        case .semanticReviewDraftPreview:
            return 1_080
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running:
            return 940
        }
    }

    var selectedTaskID: UUID? {
        switch self {
        case .idle, .taskReorderAuthoring:
            return nil
        case .dragLinkAuthoring:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c202")
        case .running:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c20b")
        case .failedRunDetail, .failedRunPreviewUnavailable, .semanticReviewRunDetail:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c20a")
        case .visualDiagnostics:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c20b")
        case .branchEvidence:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c206")
        case .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewDraftPreview:
            return nil
        }
    }

    var selectedRunID: UUID? {
        switch self {
        case .failedRunDetail, .failedRunPreviewUnavailable, .semanticReviewRunDetail:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c409")
        case .visualDiagnostics:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c40c")
        case .branchEvidence:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c406")
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewDraftPreview:
            return nil
        }
    }

    var pendingDependencySourceID: UUID? {
        switch self {
        case .dragLinkAuthoring:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c202")
        case .idle, .taskReorderAuthoring, .running, .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence,
             .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return nil
        case .templateBaselinePreviewRefs:
            return nil
        }
    }

    var pendingDependencyTrigger: AutomationDependencyTriggerDraft {
        switch self {
        case .dragLinkAuthoring:
            return .onConditionMatched
        case .idle, .taskReorderAuthoring, .running, .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence,
             .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return .onSuccess
        case .templateBaselinePreviewRefs:
            return .onSuccess
        }
    }

    var shouldAutoloadRunEvidence: Bool {
        switch self {
        case .failedRunDetail, .failedRunPreviewUnavailable:
            return true
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .visualDiagnostics, .branchEvidence,
             .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return false
        }
    }

    var macroPackageFixtureDirectoryName: String {
        switch self {
        case .failedRunPreviewUnavailable:
            return "fixture-macros-preview-unavailable"
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .failedRunDetail, .visualDiagnostics,
             .branchEvidence, .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewDraftPreview,
             .semanticReviewRunDetail:
            return "fixture-macros"
        }
    }

    var taskListPreviewState: AutomationWorkflowTaskListPreviewState? {
        switch self {
        case .taskReorderAuthoring:
            return AutomationWorkflowTaskListPreviewState(
                draggedTaskID: Self.fixedUUID("00000000-0000-0000-0000-00000000c203"),
                insertionIndex: 1
            )
        case .idle, .dragLinkAuthoring, .running, .failedRunDetail,
             .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return nil
        }
    }

    var shouldWriteUnreadableFailureScreenshot: Bool {
        self == .failedRunPreviewUnavailable
    }

    var initialEvidenceActionFeedback: AutomationTaskRunEvidenceActionFeedback? {
        switch self {
        case .failedRunDetail:
            return .succeeded(.revealReport)
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running,
             .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return nil
        }
    }

    var initialArtifactActionFeedbacks: [String: AutomationConditionEvidenceArtifactActionFeedback] {
        switch self {
        case .visualDiagnostics:
            return ["regionSampleImage": .succeeded(.reveal)]
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running,
             .failedRunDetail, .failedRunPreviewUnavailable, .branchEvidence, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewDraftPreview, .semanticReviewRunDetail:
            return [:]
        }
    }

    func linkPreview(in workflow: AutomationWorkflowProjection?) -> AutomationFlowGraphLinkPreviewState? {
        guard self == .dragLinkAuthoring,
              let workflow,
              let sourceID = pendingDependencySourceID,
              let targetNode = workflow.nodes.first(where: {
                  $0.taskID == Self.fixedUUID("00000000-0000-0000-0000-00000000c203")
              }) else {
            return nil
        }

        return AutomationFlowGraphLinkPreviewState(
            sourceTaskID: sourceID,
            end: AutomationGraphPoint(
                x: targetNode.position.x + 22,
                y: targetNode.position.y + workflow.nodeSize.height / 2
            )
        )
    }

    static func fixedUUID(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            fatalError("Invalid product evidence fixture UUID: \(value)")
        }
        return uuid
    }
}

private struct SemanticRecordingPreviewRefsEvidenceView: View {
    let bundle: SemanticRecordingBundle

    private var source: RecordingSourcePreviewReference? {
        bundle.sourcePreviews.first { $0.id == SemanticRecordingFixture.sourceOCRRefID } ??
            bundle.sourcePreviews.first
    }

    private var template: RecordingSourcePreviewReference? {
        bundle.sourcePreviews.first { $0.kind == .imageTemplate }
    }

    private var runtimeSample: RecordingRuntimeSampleReference? {
        bundle.runtimeSamples.first
    }

    private var comparison: RecordingPreviewComparison? {
        bundle.previewComparisons.first
    }

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.12, blue: 0.13)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                header

                if let source, let runtimeSample, let comparison {
                    HStack(alignment: .top, spacing: 18) {
                        previewCard(
                            title: "Source Reference",
                            subtitle: source.label ?? source.kind.rawValue,
                            accent: Color(red: 0.34, green: 0.72, blue: 0.95),
                            previewTitle: "Recorded frame crop",
                            previewDetail: source.artifactRef?.path ?? "No source artifact",
                            rows: [
                                ("Kind", source.kind.rawValue),
                                ("Frame", shortID(source.frameID)),
                                ("Event", shortID(source.eventID)),
                                ("Bounds", formattedBounds(source.bounds)),
                                ("Image", formattedImageSize(source.imageSize)),
                                ("Digest", source.contentDigest?.value ?? "not set")
                            ]
                        )

                        previewCard(
                            title: "Runtime Sample",
                            subtitle: runtimeSample.kind.rawValue,
                            accent: Color(red: 0.48, green: 0.76, blue: 0.52),
                            previewTitle: "Last watched region",
                            previewDetail: runtimeSample.artifactRef.path,
                            rows: [
                                ("Run", shortID(runtimeSample.runID)),
                                ("Task", shortID(runtimeSample.taskID)),
                                ("Condition", shortID(runtimeSample.conditionID)),
                                ("Bounds", formattedBounds(runtimeSample.bounds)),
                                ("Image", formattedImageSize(runtimeSample.imageSize)),
                                ("Digest", runtimeSample.contentDigest?.value ?? "not set")
                            ]
                        )

                        decisionCard(comparison)
                    }

                    lowerRail(source: source, runtimeSample: runtimeSample, comparison: comparison)
                } else {
                    missingFixture
                }
            }
            .padding(42)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Template / Baseline Preview References")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
            Text("Fixture evidence for the accepted S0 -> S1 contract: source reference, runtime sample, and comparison decision render together from a SemanticRecordingBundle value model.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingFixture: some View {
        Text("Semantic recording fixture is missing source, runtime, or comparison references.")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color(red: 1.00, green: 0.50, blue: 0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func decisionCard(_ comparison: RecordingPreviewComparison) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(
                title: "Decision",
                subtitle: comparison.outcome.rawValue,
                accent: Color(red: 1.00, green: 0.72, blue: 0.30)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    Text(formattedPercent(comparison.score))
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("score")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Spacer()
                    Text("threshold \(formattedPercent(comparison.threshold))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(Color(red: 1.00, green: 0.72, blue: 0.30).opacity(0.85))
                            .frame(width: proxy.size.width * CGFloat(clampedScore(comparison.score)))
                    }
                }
                .frame(height: 8)
            }

            detailRows([
                ("Matcher", "\(comparison.matcher.kind) \(comparison.matcher.version)"),
                ("Provider", comparison.matcher.provider ?? "not set"),
                ("Source ref", shortID(comparison.sourcePreviewRefID)),
                ("Runtime ref", shortID(comparison.runtimeSampleRefID)),
                ("Diff", comparison.diffArtifactRef?.path ?? "not set"),
                ("Reason", comparison.reason ?? "not set")
            ])
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func previewCard(
        title: String,
        subtitle: String,
        accent: Color,
        previewTitle: String,
        previewDetail: String,
        rows: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(title: title, subtitle: subtitle, accent: accent)
            previewBox(title: previewTitle, detail: previewDetail, accent: accent)
            detailRows(rows)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func cardHeader(title: String, subtitle: String, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
            }
        }
    }

    private func previewBox(title: String, detail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("safe ref")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 7)
                    .stroke(accent.opacity(0.42), lineWidth: 1)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(2)
                    .padding(12)
            }
            .frame(height: 148)
        }
    }

    private func detailRows(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .frame(width: 74, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func lowerRail(
        source: RecordingSourcePreviewReference,
        runtimeSample: RecordingRuntimeSampleReference,
        comparison: RecordingPreviewComparison
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if let template {
                railItem(
                    title: "Related Template",
                    value: template.artifactRef?.path ?? "not set",
                    detail: "Image template ref \(shortID(template.id)) from frame \(shortID(template.frameID))."
                )
            }
            railItem(
                title: "Bundle",
                value: "schema \(bundle.schemaVersion.major).\(bundle.schemaVersion.minor)",
                detail: "Recording \(shortID(bundle.id)); \(bundle.frames.count) frames, \(bundle.visualObservations.count) observations."
            )
            railItem(
                title: "Safety",
                value: "safe relative artifact refs",
                detail: "SwiftUI renders ids and presenter-ready refs; app-edge code remains responsible for opening files."
            )
            railItem(
                title: "Trace",
                value: "\(shortID(source.id)) -> \(shortID(runtimeSample.id)) -> \(shortID(comparison.id))",
                detail: "The same ids can be cited by CLI and AI suggestions without embedding image bytes."
            )
        }
    }

    private func railItem(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func formattedBounds(_ bounds: RecordingBounds?) -> String {
        guard let rect = bounds?.rect else { return "not set" }
        return String(
            format: "%.0f, %.0f  %.0fx%.0f",
            rect.x,
            rect.y,
            rect.width,
            rect.height
        )
    }

    private func formattedImageSize(_ imageSize: RecordingImageSize?) -> String {
        guard let imageSize else { return "not set" }
        return "\(imageSize.width)x\(imageSize.height)"
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private func clampedScore(_ value: Double?) -> Double {
        min(1, max(0, value ?? 0))
    }

    private func shortID(_ id: UUID?) -> String {
        guard let id else { return "not set" }
        return String(id.uuidString.prefix(8))
    }
}

@MainActor
enum AutomationProductEvidenceSnapshotRenderer {
    static func render(
        scenario: AutomationProductEvidenceSnapshotScenario,
        outputURL: URL,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        if scenario == .templateBaselinePreviewRefs {
            let view = SemanticRecordingPreviewRefsEvidenceView(
                bundle: SemanticRecordingFixture.checkoutBundle(createdAt: now)
            )
            .frame(width: width, height: height)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .background(Color(red: 0.10, green: 0.12, blue: 0.13))

            try writeSwiftUISnapshot(
                view,
                outputURL: outputURL,
                width: width,
                height: height,
                scale: scale
            )
            return
        }
        if scenario == .semanticReviewTimeline {
            let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: now)
            let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
            let projection = SemanticRecordingReviewProjection(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: SemanticRecordingFixture.waitEventID
            )
            let candidateID = projection.selectedFrame?.conditionCandidates.first?.id
            let view = SemanticRecordingReviewFixtureView(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: SemanticRecordingFixture.waitEventID,
                initialDraftPatchCandidateID: candidateID
            )
            .frame(width: width, height: height)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .background(Color(red: 0.08, green: 0.09, blue: 0.10))

            try writeSwiftUISnapshot(
                view,
                outputURL: outputURL,
                width: width,
                height: height,
                scale: scale
            )
            return
        }
        if scenario == .semanticReviewDraftPreview {
            let state = try semanticReviewDraftPreviewState(
                now: now,
                sourceDirectory: outputURL.deletingLastPathComponent()
            )
            let view = AutomationWorkflowDraftPreviewSheet(
                state: state,
                existingWorkflowName: "Checkout workflow",
                onImportWorkflow: { _, _ in }
            )
            .frame(width: width, height: height)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .background(Color(red: 0.08, green: 0.09, blue: 0.10))

            try writeSwiftUISnapshot(
                view,
                outputURL: outputURL,
                width: width,
                height: height,
                scale: scale
            )
            return
        }

        let state = state(for: scenario, now: now)
        let projection = AutomationViewProjection.overview(from: state)
        let snapshot = AutomationRepositorySnapshot(
            workflows: state.workflows,
            runHistory: state.runs,
            refreshedAt: now
        )
        let selectedWorkflow = projection.workflows.first
        let selectedWorkflowID = selectedWorkflow?.id
        let selection = scenario.selectedTaskID.map(AutomationAuthoringSelection.task) ?? .workflow
        let artifactBaseURL = outputURL.deletingLastPathComponent()
        try seedVisualDiagnosticArtifacts(in: artifactBaseURL)
        let macroPackageBaseURL = artifactBaseURL.appendingPathComponent(
            scenario.macroPackageFixtureDirectoryName,
            isDirectory: true
        )
        try seedFailedRunEvidence(
            in: macroPackageBaseURL,
            now: now,
            writeUnreadableScreenshot: scenario.shouldWriteUnreadableFailureScreenshot
        )

        let view = AutomationMainContentView(
            state: state,
            projection: projection,
            macros: fixtureMacros(now: now, scenario: scenario),
            refreshState: .loaded(snapshot),
            initialSelectedWorkflowID: selectedWorkflowID,
            initialSelection: selection,
            initialSelectedRunID: scenario.selectedRunID,
            initialPendingDependencySourceID: scenario.pendingDependencySourceID,
            initialPendingDependencyTrigger: scenario.pendingDependencyTrigger,
            initialFlowGraphLinkPreview: scenario.linkPreview(in: selectedWorkflow),
            initialTaskListPreviewState: scenario.taskListPreviewState,
            onRefresh: {},
            onAction: { _ in }
        )
        .frame(width: width, height: height)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.automationConditionDiagnosticArtifactBaseURL, artifactBaseURL)
        .environment(
            \.automationConditionDiagnosticArtifactInitialFeedbacks,
            scenario.initialArtifactActionFeedbacks
        )
        .environment(\.automationTaskRunEvidenceMacroPackageBaseURL, macroPackageBaseURL)
        .environment(\.automationTaskRunEvidenceAutoload, scenario.shouldAutoloadRunEvidence)
        .environment(\.automationTaskRunEvidenceInitialActionFeedback, scenario.initialEvidenceActionFeedback)
        .background(Color(red: 0.10, green: 0.12, blue: 0.13))

        try writeSwiftUISnapshot(
            view,
            outputURL: outputURL,
            width: width,
            height: height,
            scale: scale
        )
    }

    private static func semanticReviewDraftPreviewState(
        now: Date,
        sourceDirectory: URL?
    ) throws -> AutomationWorkflowDraftPreviewState {
        let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: now)
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        guard let candidate = projection.selectedFrame?.conditionCandidates.first(where: { $0.kind == .imageAppeared }) else {
            throw SnapshotError.fixturePreparationFailed("Semantic Review fixture did not expose an imageAppeared candidate.")
        }

        let patchResult = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                newTaskKey: "wait_checkout_button",
                threshold: 0.88
            )
        )
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: patchResult.patch,
            readArtifact: { path in
                Data("semantic-review-draft-preview:\(path)".utf8)
            },
            writeAsset: { _, _ in }
        )
        let document = AutomationWorkflowDraftDocument(
            workflow: AutomationWorkflowDraft(name: "Checkout Review Draft")
        )
        let patched = try AutomationWorkflowDraftPatchApplier.apply(
            materialized.patch,
            to: document
        )

        return AutomationWorkflowDraftPreviewPresenter.previewState(
            document: patched.document,
            sourceName: "Macro Review checkout patch",
            sourceDirectory: sourceDirectory,
            loadedAt: now,
            macroCatalog: []
        )
    }

    private static func writeSwiftUISnapshot<Content: View>(
        _ view: Content,
        outputURL: URL,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) throws {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let darkAppearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.appearance = darkAppearance
        hostingView.appearance = darkAppearance

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = darkAppearance
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.70))
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((width * scale).rounded()),
            pixelsHigh: Int((height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else {
            throw SnapshotError.renderFailed
        }
        bitmap.size = NSSize(width: width, height: height)
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }

        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: outputURL, options: .atomic)
    }

    private static func seedFailedRunEvidence(
        in baseURL: URL,
        now: Date,
        writeUnreadableScreenshot: Bool
    ) throws {
        let macroID = AutomationProductEvidenceSnapshotScenario.fixedUUID("00000000-0000-0000-0000-00000000c102")
        let evidenceID = AutomationProductEvidenceSnapshotScenario.fixedUUID("00000000-0000-0000-0000-00000000c409")
        let evidenceURL = baseURL
            .appendingPathComponent("\(macroID.uuidString).sparkrec", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(evidenceID.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: evidenceURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let report = RunReport(
            runID: evidenceID,
            startTime: now.addingTimeInterval(-180),
            duration: 20,
            isSuccess: false,
            failedEventIndex: 2,
            errorMessage: "Upload receipt was not visible"
        )
        let manifest = RunEvidenceManifest(
            evidenceID: evidenceID,
            macroID: macroID,
            runID: evidenceID,
            screenshotFilename: "failure.png",
            createdAt: now.addingTimeInterval(-159)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(report).write(
            to: evidenceURL.appendingPathComponent("report.json", isDirectory: false),
            options: .atomic
        )
        try encoder.encode(manifest).write(
            to: evidenceURL.appendingPathComponent("manifest.json", isDirectory: false),
            options: .atomic
        )
        let screenshotURL = evidenceURL.appendingPathComponent("failure.png", isDirectory: false)
        if writeUnreadableScreenshot {
            let data = Data("not a decodable image; fixture intentionally exercises preview fallback".utf8)
            try data.write(to: screenshotURL, options: .atomic)
        } else {
            try writeFixturePNG(
                to: screenshotURL,
                size: NSSize(width: 960, height: 540)
            ) { rect in
                drawFailedRunScreenshotFixture(in: rect)
            }
        }
    }

    private static func seedVisualDiagnosticArtifacts(in baseURL: URL) throws {
        let artifactDirectory = baseURL
            .appendingPathComponent("fixture-artifacts", isDirectory: true)
            .appendingPathComponent("visual-condition", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        try writeFixturePNG(
            to: artifactDirectory.appendingPathComponent("condition-last-sample.png"),
            size: NSSize(width: 960, height: 540)
        ) { rect in
            drawLastSampleFixture(in: rect)
        }

        try writeFixturePNG(
            to: artifactDirectory.appendingPathComponent("condition-region-sample.png"),
            size: NSSize(width: 360, height: 220)
        ) { rect in
            drawRegionSampleFixture(in: rect)
        }
    }

    private static func writeFixturePNG(
        to url: URL,
        size: NSSize,
        drawing: (NSRect) -> Void
    ) throws {
        let image = NSImage(size: size)
        image.lockFocus()
        drawing(NSRect(origin: .zero, size: size))
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try pngData.write(to: url, options: .atomic)
    }

    private static func drawLastSampleFixture(in rect: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1).setFill()
        rect.fill()
        drawPanel(
            NSRect(x: 92, y: 72, width: 776, height: 390),
            fill: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.16, alpha: 1),
            stroke: NSColor(calibratedRed: 0.38, green: 0.55, blue: 0.70, alpha: 0.45)
        )
        drawPanel(
            NSRect(x: 320, y: 170, width: 320, height: 180),
            fill: NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.20, alpha: 1),
            stroke: NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 0.75)
        )
        drawText("Battle result", at: NSPoint(x: 132, y: 410), size: 26, color: .white)
        drawText("Reward ready", at: NSPoint(x: 376, y: 266), size: 24, color: .white)
        drawText("Spinner absent", at: NSPoint(x: 382, y: 228), size: 16, color: NSColor.systemOrange)
        drawText("last sample / display", at: NSPoint(x: 680, y: 88), size: 13, color: NSColor.secondaryLabelColor)
    }

    private static func drawRegionSampleFixture(in rect: NSRect) {
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.15, alpha: 1).setFill()
        rect.fill()
        drawPanel(
            NSRect(x: 28, y: 36, width: 304, height: 142),
            fill: NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.21, alpha: 1),
            stroke: NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 0.78)
        )
        drawText("Watched region", at: NSPoint(x: 58, y: 132), size: 17, color: .white)
        drawText("loading_spinner_template: not visible", at: NSPoint(x: 58, y: 94), size: 13, color: NSColor.systemOrange)
        drawText("similarity 0.12 < 0.91", at: NSPoint(x: 58, y: 70), size: 13, color: NSColor.secondaryLabelColor)
    }

    private static func drawFailedRunScreenshotFixture(in rect: NSRect) {
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).setFill()
        rect.fill()
        drawPanel(
            NSRect(x: 88, y: 70, width: 784, height: 400),
            fill: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.16, alpha: 1),
            stroke: NSColor(calibratedRed: 0.34, green: 0.42, blue: 0.50, alpha: 0.5)
        )
        drawText("Receipt upload", at: NSPoint(x: 132, y: 410), size: 26, color: .white)
        drawText("Expected receipt confirmation", at: NSPoint(x: 132, y: 360), size: 16, color: NSColor.secondaryLabelColor)
        drawPanel(
            NSRect(x: 214, y: 180, width: 532, height: 142),
            fill: NSColor(calibratedRed: 0.15, green: 0.08, blue: 0.09, alpha: 1),
            stroke: NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.36, alpha: 0.75)
        )
        drawText("Upload stalled", at: NSPoint(x: 270, y: 272), size: 22, color: .white)
        drawText("No receipt was visible after event #3", at: NSPoint(x: 270, y: 236), size: 15, color: NSColor.systemPink)
        drawText("failure screenshot / run C409", at: NSPoint(x: 652, y: 92), size: 13, color: NSColor.secondaryLabelColor)
    }

    private static func drawPanel(_ rect: NSRect, fill: NSColor, stroke: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private static func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color
        ]
        text.draw(at: point, withAttributes: attributes)
    }

    private static func state(
        for scenario: AutomationProductEvidenceSnapshotScenario,
        now: Date
    ) -> AutomationRunState {
        var state = AutomationRunState.ownerCFixture(now: now)
        if scenario == .idle {
            state.runs = state.runs.filter(\.isTerminal)
        }
        return state
    }

    private static func fixtureMacros(
        now: Date,
        scenario: AutomationProductEvidenceSnapshotScenario
    ) -> [SavedMacro] {
        [
            fixtureMacro(
                id: "00000000-0000-0000-0000-00000000c101",
                name: "Open nightly workspace",
                accent: "blue",
                createdAt: now.addingTimeInterval(-12_000)
            ),
            fixtureMacro(
                id: "00000000-0000-0000-0000-00000000c102",
                name: "Upload report",
                accent: "green",
                createdAt: now.addingTimeInterval(-10_000),
                semanticRecording: scenario == .semanticReviewRunDetail
                    ? MacroSemanticRecordingReference(
                        recordingID: SemanticRecordingFixture.recordingID,
                        bundleRelativePath: "SemanticRecordings/checkout-demo",
                        manifestRelativePath: "SemanticRecordings/checkout-demo/manifest.json",
                        capturedAt: now.addingTimeInterval(-9_600),
                        eventCount: 3
                    )
                    : nil
            ),
            fixtureMacro(
                id: "00000000-0000-0000-0000-00000000c901",
                name: "Collect battle rewards",
                accent: "yellow",
                createdAt: now.addingTimeInterval(-8_000)
            ),
            fixtureMacro(
                id: "00000000-0000-0000-0000-00000000c902",
                name: "Clear notification badges",
                accent: "red",
                createdAt: now.addingTimeInterval(-6_000)
            )
        ]
    }

    private static func fixtureMacro(
        id: String,
        name: String,
        accent: String,
        createdAt: Date,
        semanticRecording: MacroSemanticRecordingReference? = nil
    ) -> SavedMacro {
        SavedMacro(
            id: AutomationProductEvidenceSnapshotScenario.fixedUUID(id),
            name: name,
            events: [
                RecordedEvent(
                    kind: .leftMouseDown,
                    time: 0.12,
                    x: 180,
                    y: 260,
                    keyCode: 0,
                    flags: 0,
                    mouseButton: 0,
                    clickCount: 1,
                    scrollDeltaY: 0,
                    scrollDeltaX: 0
                ),
                RecordedEvent(
                    kind: .leftMouseUp,
                    time: 0.20,
                    x: 180,
                    y: 260,
                    keyCode: 0,
                    flags: 0,
                    mouseButton: 0,
                    clickCount: 1,
                    scrollDeltaY: 0,
                    scrollDeltaX: 0
                ),
                RecordedEvent(
                    kind: .keyDown,
                    time: 1.15,
                    x: 0,
                    y: 0,
                    keyCode: 36,
                    flags: 0,
                    mouseButton: 0,
                    clickCount: 0,
                    scrollDeltaY: 0,
                    scrollDeltaX: 0
                )
            ],
            createdAt: createdAt,
            modifiedAt: createdAt.addingTimeInterval(900),
            accent: accent,
            tags: ["workflow-fixture"],
            semanticRecording: semanticRecording,
            playCount: 4,
            lastPlayedAt: createdAt.addingTimeInterval(1_800),
            totalRunTime: 84
        )
    }

    enum SnapshotError: Error, CustomStringConvertible {
        case renderFailed
        case pngEncodingFailed
        case fixturePreparationFailed(String)

        var description: String {
            switch self {
            case .renderFailed:
                return "Could not render Workflow fixture view."
            case .pngEncodingFailed:
                return "Could not encode Workflow fixture snapshot as PNG."
            case .fixturePreparationFailed(let message):
                return message
            }
        }
    }
}

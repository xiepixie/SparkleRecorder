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
    case editorPreviewAffordances = "editor-preview-affordances"
    case templateBaselinePreviewRefs = "template-baseline-preview-refs"
    case semanticReviewTimeline = "semantic-review-timeline"
    case semanticReviewStoredBundle = "semantic-review-stored-bundle"
    case semanticReviewMissingArtifacts = "semantic-review-missing-artifacts"
    case semanticReviewPixelColor = "semantic-review-pixel-color"
    case semanticReviewMaterializedActions = "semantic-review-materialized-actions"
    case semanticReviewDraftPreview = "semantic-review-draft-preview"
    case semanticReviewRunDetail = "semantic-review-run-detail"
    case semanticReviewRunTarget = "semantic-review-run-target"

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
        case "editor-preview-affordances", "macro-editor-preview-affordances", "editor-preview":
            self = .editorPreviewAffordances
        case "template-baseline-preview-refs", "preview-refs", "semantic-preview-refs":
            self = .templateBaselinePreviewRefs
        case "semantic-review", "semantic-review-timeline", "review-timeline":
            self = .semanticReviewTimeline
        case "semantic-review-stored-bundle", "review-stored-bundle", "stored-review":
            self = .semanticReviewStoredBundle
        case "semantic-review-missing-artifacts", "review-missing-artifacts", "missing-review-artifacts":
            self = .semanticReviewMissingArtifacts
        case "semantic-review-pixel-color", "review-pixel-color", "pixel-color":
            self = .semanticReviewPixelColor
        case "semantic-review-materialized-actions", "review-materialized-actions", "materialized-review-actions":
            self = .semanticReviewMaterializedActions
        case "semantic-review-draft-preview", "review-draft-preview", "semantic-draft-preview":
            self = .semanticReviewDraftPreview
        case "semantic-review-run-detail", "review-run-detail", "macro-review-run-detail":
            self = .semanticReviewRunDetail
        case "semantic-review-run-target", "review-run-target", "macro-review-run-target":
            self = .semanticReviewRunTarget
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
        case .editorPreviewAffordances:
            return "editor-preview-affordances.png"
        case .templateBaselinePreviewRefs:
            return "template-baseline-preview-refs.png"
        case .semanticReviewTimeline:
            return "semantic-review-timeline.png"
        case .semanticReviewStoredBundle:
            return "semantic-review-stored-bundle.png"
        case .semanticReviewMissingArtifacts:
            return "semantic-review-missing-artifacts.png"
        case .semanticReviewPixelColor:
            return "semantic-review-pixel-color.png"
        case .semanticReviewMaterializedActions:
            return "semantic-review-materialized-actions.png"
        case .semanticReviewDraftPreview:
            return "semantic-review-draft-preview.png"
        case .semanticReviewRunDetail:
            return "semantic-review-run-detail.png"
        case .semanticReviewRunTarget:
            return "semantic-review-run-target.png"
        }
    }

    var defaultHeight: Double {
        switch self {
        case .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .semanticReviewRunDetail:
            return 1_560
        case .semanticReviewRunTarget:
            return 1_220
        case .branchEvidence:
            return 1_120
        case .editorPreviewAffordances:
            return 1_020
        case .templateBaselinePreviewRefs:
            return 980
        case .semanticReviewTimeline:
            return 1_560
        case .semanticReviewStoredBundle:
            return 1_180
        case .semanticReviewMissingArtifacts:
            return 1_220
        case .semanticReviewPixelColor:
            return 1_040
        case .semanticReviewMaterializedActions:
            return 1_560
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
        case .editorPreviewAffordances, .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunTarget:
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
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .editorPreviewAffordances, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunTarget:
            return nil
        }
    }

    var pendingDependencySourceID: UUID? {
        switch self {
        case .dragLinkAuthoring:
            return Self.fixedUUID("00000000-0000-0000-0000-00000000c202")
        case .idle, .taskReorderAuthoring, .running, .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence, .editorPreviewAffordances,
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget:
            return nil
        case .templateBaselinePreviewRefs:
            return nil
        }
    }

    var pendingDependencyTrigger: AutomationDependencyTriggerDraft {
        switch self {
        case .dragLinkAuthoring:
            return .onConditionMatched
        case .idle, .taskReorderAuthoring, .running, .failedRunDetail, .failedRunPreviewUnavailable, .visualDiagnostics, .branchEvidence, .editorPreviewAffordances,
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget:
            return .onSuccess
        case .templateBaselinePreviewRefs:
            return .onSuccess
        }
    }

    var shouldAutoloadRunEvidence: Bool {
        switch self {
        case .failedRunDetail, .failedRunPreviewUnavailable:
            return true
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .visualDiagnostics, .branchEvidence, .editorPreviewAffordances,
             .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget:
            return false
        }
    }

    var macroPackageFixtureDirectoryName: String {
        switch self {
        case .failedRunPreviewUnavailable:
            return "fixture-macros-preview-unavailable"
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running, .failedRunDetail, .visualDiagnostics,
             .branchEvidence, .templateBaselinePreviewRefs, .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview,
             .semanticReviewRunDetail, .semanticReviewRunTarget, .editorPreviewAffordances:
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
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget, .editorPreviewAffordances:
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
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget, .editorPreviewAffordances:
            return nil
        }
    }

    var initialArtifactActionFeedbacks: [String: AutomationConditionEvidenceArtifactActionFeedback] {
        switch self {
        case .visualDiagnostics:
            return ["regionSampleImage": .succeeded(.reveal)]
        case .idle, .dragLinkAuthoring, .taskReorderAuthoring, .running,
             .failedRunDetail, .failedRunPreviewUnavailable, .branchEvidence, .templateBaselinePreviewRefs,
             .semanticReviewTimeline, .semanticReviewStoredBundle, .semanticReviewMissingArtifacts, .semanticReviewPixelColor, .semanticReviewMaterializedActions, .semanticReviewDraftPreview, .semanticReviewRunDetail, .semanticReviewRunTarget, .editorPreviewAffordances:
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

private struct EditorPreviewAffordanceEvidenceView: View {
    @StateObject private var overlayState: OverlayState

    init() {
        let state = OverlayState()
        state.actions = Self.fixtureActions
        _overlayState = StateObject(wrappedValue: state)
    }

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.11)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                header

                HStack(alignment: .top, spacing: 18) {
                    previewSurface
                    evidenceRail
                }
            }
            .padding(42)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macro Editor Preview Affordances")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
            Text("Fixture evidence for the UI owner rule: wait/verify actions are labeled condition regions, while click and text-click actions keep click pulse affordances.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewSurface: some View {
        ZStack(alignment: .topLeading) {
            appSurfaceBackground
            TargetCrosshairView(state: overlayState)
                .frame(width: 860, height: 620)
                .allowsHitTesting(false)
        }
        .frame(width: 860, height: 620)
        .clipShape(.rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var appSurfaceBackground: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(red: 0.13, green: 0.15, blue: 0.16))

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.93, green: 0.32, blue: 0.28)).frame(width: 11, height: 11)
                    Circle().fill(Color(red: 0.94, green: 0.70, blue: 0.25)).frame(width: 11, height: 11)
                    Circle().fill(Color(red: 0.36, green: 0.74, blue: 0.38)).frame(width: 11, height: 11)
                    Text("Checkout window")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.54))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(Color.white.opacity(0.045))

                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        placeholderLine(width: 250, opacity: 0.32)
                        placeholderLine(width: 360, opacity: 0.20)
                        placeholderLine(width: 310, opacity: 0.20)
                        Spacer(minLength: 0)
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(red: 0.24, green: 0.47, blue: 0.70).opacity(0.52))
                                .frame(width: 150, height: 42)
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 126, height: 42)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(index == 2 ? 0.14 : 0.075))
                                .frame(width: 214, height: 56)
                        }
                    }
                    .padding(.trailing, 34)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func placeholderLine(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: 10)
    }

    private var evidenceRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            railItem(
                title: "Wait text",
                detail: "Region label only; no click pulse.",
                color: Color(red: 0.95, green: 0.63, blue: 0.21)
            )
            railItem(
                title: "Verify text",
                detail: "Condition region uses verify styling, not a coordinate click.",
                color: Color(red: 0.60, green: 0.50, blue: 0.96)
            )
            railItem(
                title: "Click text",
                detail: "Text locator shows the region and click pulse because it sends input.",
                color: Color(red: 0.37, green: 0.72, blue: 0.96)
            )
            railItem(
                title: "Click position",
                detail: "Ordinary coordinate click keeps the pulse target.",
                color: Color(red: 0.45, green: 0.82, blue: 0.48)
            )
            Spacer(minLength: 0)
            Text("Fixture screenshot. It proves the editor overlay component and projection affordance mapping, not live recording capture.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360, height: 620, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func railItem(title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static var fixtureActions: [RelativePreviewAction] {
        [
            RelativePreviewAction(
                id: AutomationProductEvidenceSnapshotScenario.fixedUUID("7f000000-0000-0000-0000-000000000001"),
                kind: .waitForText,
                affordance: .waitTextRegion,
                selectedPoint: nil,
                dragPath: [],
                observedFrame: nil,
                searchRegion: CGRect(x: 86, y: 178, width: 250, height: 54),
                fallbackPoint: nil,
                themeColor: Color(red: 0.95, green: 0.63, blue: 0.21),
                order: 1
            ),
            RelativePreviewAction(
                id: AutomationProductEvidenceSnapshotScenario.fixedUUID("7f000000-0000-0000-0000-000000000002"),
                kind: .verifyText,
                affordance: .verifyTextRegion,
                selectedPoint: nil,
                dragPath: [],
                observedFrame: nil,
                searchRegion: CGRect(x: 530, y: 180, width: 218, height: 58),
                fallbackPoint: nil,
                themeColor: Color(red: 0.60, green: 0.50, blue: 0.96),
                order: 2
            ),
            RelativePreviewAction(
                id: AutomationProductEvidenceSnapshotScenario.fixedUUID("7f000000-0000-0000-0000-000000000003"),
                kind: .click,
                affordance: .textClickTarget,
                selectedPoint: CGPoint(x: 198, y: 486),
                dragPath: [CGPoint(x: 198, y: 486)],
                observedFrame: CGRect(x: 118, y: 456, width: 160, height: 60),
                searchRegion: CGRect(x: 94, y: 438, width: 208, height: 96),
                fallbackPoint: CGPoint(x: 198, y: 486),
                themeColor: Color(red: 0.37, green: 0.72, blue: 0.96),
                order: 3
            ),
            RelativePreviewAction(
                id: AutomationProductEvidenceSnapshotScenario.fixedUUID("7f000000-0000-0000-0000-000000000004"),
                kind: .click,
                affordance: .inputPoint,
                selectedPoint: CGPoint(x: 636, y: 492),
                dragPath: [CGPoint(x: 636, y: 492)],
                observedFrame: nil,
                searchRegion: nil,
                fallbackPoint: nil,
                themeColor: Color(red: 0.45, green: 0.82, blue: 0.48),
                order: 4
            )
        ]
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
        if scenario == .editorPreviewAffordances {
            let view = EditorPreviewAffordanceEvidenceView()
                .frame(width: width, height: height)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .background(Color(red: 0.09, green: 0.10, blue: 0.11))

            try writeSwiftUISnapshot(
                view,
                outputURL: outputURL,
                width: width,
                height: height,
                scale: scale
            )
            return
        }
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
            let initialSelection = SemanticRecordingFrameRegionSelection(
                frameID: SemanticRecordingFixture.afterClickFrameID,
                surfaceID: SemanticRecordingFixture.surfaceID,
                bounds: RecordingBounds(
                    rect: RecordingRect(x: 690, y: 200, width: 286, height: 58),
                    coordinateSpace: .windowPixels
                ),
                imageSize: RecordingImageSize(width: 1_440, height: 900),
                label: "Reviewed confirmation region",
                candidateKind: .ocrWait,
                sourcePreviewRefID: SemanticRecordingFixture.sourceOCRRefID,
                observationID: SemanticRecordingFixture.ocrObservationID,
                artifactPath: "visual-index/ocr/confirmation-region.png"
            )
            let view = SemanticRecordingReviewFixtureView(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: SemanticRecordingFixture.waitEventID,
                initialDraftPatchCandidateID: candidateID,
                initialRegionSelection: initialSelection,
                initialAcceptedSuggestionID: suggestions.first?.id
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
        if scenario == .semanticReviewRunTarget {
            let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: now)
            let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
            let run = semanticReviewRunTargetFixtureRun(createdAt: now)
            let target = SemanticRecordingReviewRunTarget.make(
                run: run,
                bundle: bundle
            )
            let projection = SemanticRecordingReviewProjection(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: target.selectedEventID,
                selectedFrameID: target.selectedFrameID
            )
            let candidateID = projection.selectedFrame?.conditionCandidates.first?.id
            let view = SemanticRecordingReviewFixtureView(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: target.selectedEventID,
                selectedFrameID: target.selectedFrameID,
                initialDraftPatchCandidateID: candidateID,
                initialRunTargetPresentation: .make(target: target),
                initialRunTargetEvidence: .make(target: target)
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
        if scenario == .semanticReviewStoredBundle {
            let storedFixture = try semanticReviewStoredBundleFixture(
                createdAt: now,
                baseDirectory: outputURL.deletingLastPathComponent()
            )
            let view = SemanticRecordingReviewFixtureView(
                state: storedFixture.state,
                selectedEventID: SemanticRecordingFixture.waitEventID,
                selectedFrameID: SemanticRecordingFixture.afterClickFrameID,
                initialDraftPatchCandidateID: storedFixture.candidateID
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
        if scenario == .semanticReviewMissingArtifacts {
            let missingFixture = try semanticReviewMissingArtifactsFixture(
                createdAt: now,
                baseDirectory: outputURL.deletingLastPathComponent()
            )
            let view = SemanticRecordingReviewFixtureView(
                state: missingFixture.state,
                selectedEventID: SemanticRecordingFixture.waitEventID,
                selectedFrameID: SemanticRecordingFixture.afterClickFrameID,
                initialDraftPatchCandidateID: missingFixture.candidateID
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
        if scenario == .semanticReviewPixelColor {
            let pixelFixture = semanticReviewPixelColorFixture(createdAt: now)
            let view = SemanticRecordingReviewFixtureView(
                bundle: pixelFixture.bundle,
                selectedEventID: SemanticRecordingFixture.waitEventID,
                initialDraftPatchCandidateID: pixelFixture.candidateID,
                initialPixelColorHexes: [
                    pixelFixture.candidateID: pixelFixture.colorHex
                ]
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
        if scenario == .semanticReviewMaterializedActions {
            let materializedFixture = try semanticReviewMaterializedActionFixture(createdAt: now)
            let view = SemanticRecordingReviewFixtureView(
                bundle: materializedFixture.bundle,
                suggestions: materializedFixture.suggestions,
                selectedEventID: SemanticRecordingFixture.clickEventID,
                initialDraftPatchCandidateID: materializedFixture.candidateID,
                initialDraftPreviewActionPresentations: materializedFixture.presentations
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

    private static func semanticReviewPixelColorFixture(
        createdAt: Date
    ) -> (bundle: SemanticRecordingBundle, candidateID: String, colorHex: String) {
        let pixelSourceID = AutomationProductEvidenceSnapshotScenario.fixedUUID(
            "74000000-0000-0000-0000-000000000020"
        )
        let pixelBounds = RecordingBounds(
            rect: RecordingRect(x: 1_024, y: 246, width: 1, height: 1),
            coordinateSpace: .windowPixels
        )
        var bundle = SemanticRecordingFixture.checkoutBundle(createdAt: createdAt)
        bundle.sourcePreviews.append(RecordingSourcePreviewReference(
            id: pixelSourceID,
            kind: .pixelSample,
            recordingID: bundle.id,
            frameID: SemanticRecordingFixture.afterClickFrameID,
            eventID: SemanticRecordingFixture.waitEventID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: pixelBounds,
            imageSize: RecordingImageSize(width: 1, height: 1),
            createdAt: createdAt,
            recordingTime: 2.45,
            label: "Ready status pixel"
        ))
        return (
            bundle,
            "\(pixelSourceID.uuidString)-pixelMatched",
            "#2BC66A"
        )
    }

    private static func semanticReviewRunTargetFixtureRun(
        createdAt: Date
    ) -> AutomationTaskRun {
        AutomationTaskRun(
            workflowID: AutomationProductEvidenceSnapshotScenario.fixedUUID(
                "00000000-0000-0000-0000-00000000c101"
            ),
            taskID: AutomationProductEvidenceSnapshotScenario.fixedUUID(
                "00000000-0000-0000-0000-00000000c20a"
            ),
            macroID: AutomationProductEvidenceSnapshotScenario.fixedUUID(
                "00000000-0000-0000-0000-00000000c102"
            ),
            scheduledStartTime: createdAt.addingTimeInterval(-10),
            earliestStartTime: createdAt.addingTimeInterval(-10),
            actualStartTime: createdAt.addingTimeInterval(-9),
            completedAt: createdAt,
            status: .completed,
            outcome: .failed(report: RunReport(
                runID: AutomationProductEvidenceSnapshotScenario.fixedUUID(
                    "00000000-0000-0000-0000-00000000c409"
                ),
                startTime: createdAt.addingTimeInterval(-9),
                duration: 9,
                isSuccess: false,
                failedEventIndex: 4,
                errorMessage: "Checkout confirmation did not stabilize"
            )),
            evidenceID: AutomationProductEvidenceSnapshotScenario.fixedUUID(
                "00000000-0000-0000-0000-00000000c409"
            ),
            createdAt: createdAt.addingTimeInterval(-12)
        )
    }

    private static func semanticReviewMaterializedActionFixture(
        createdAt: Date
    ) throws -> (
        bundle: SemanticRecordingBundle,
        suggestions: [RecordingSuggestion],
        candidateID: String,
        presentations: [SemanticRecordingReviewActionPresentation]
    ) {
        let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: createdAt)
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        guard let candidate = projection.selectedFrame?.conditionCandidates.first(where: { $0.kind == .imageAppeared }) else {
            throw SnapshotError.fixturePreparationFailed("Semantic Review fixture did not expose an imageAppeared candidate.")
        }
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(candidate: candidate)
        )
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: result.patch,
            readArtifact: { path in
                Data("semantic-review-materialized-actions:\(path)".utf8)
            },
            writeAsset: { _, _ in }
        )
        let previewAction = SemanticRecordingReviewActionSemantics.previewDraft(
            result,
            materializedAssets: materialized.copiedAssets
        )
        let importAction = SemanticRecordingReviewActionSemantics.importDraft(
            result,
            materializedAssets: materialized.copiedAssets
        )
        return (
            bundle,
            suggestions,
            candidate.id,
            [
                SemanticRecordingReviewActionPresentation(previewAction),
                SemanticRecordingReviewActionPresentation(importAction)
            ]
        )
    }

    private static func semanticReviewStoredBundleFixture(
        createdAt: Date,
        baseDirectory: URL
    ) throws -> (state: SemanticRecordingReviewState, candidateID: String?) {
        let rootDirectory = baseDirectory.appendingPathComponent(
            "fixture-semantic-review-stored-bundles",
            isDirectory: true
        )
        let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: createdAt)
        let bundleDirectory = rootDirectory.appendingPathComponent(
            bundle.id.uuidString,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: bundleDirectory.path) {
            try FileManager.default.removeItem(at: bundleDirectory)
        }

        try writeSemanticReviewStoredBundleManifest(bundle, to: bundleDirectory)
        try seedSemanticReviewStoredBundleArtifacts(for: bundle, in: bundleDirectory)

        let loadedBundle = try readSemanticReviewStoredBundleManifest(from: bundleDirectory)
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: loadedBundle)
        let artifactStatuses = semanticReviewArtifactStatuses(
            for: loadedBundle,
            directory: bundleDirectory
        )
        let projection = SemanticRecordingReviewProjection(
            bundle: loadedBundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.waitEventID,
            selectedFrameID: SemanticRecordingFixture.afterClickFrameID
        )
        let candidateID = projection.selectedFrame?.conditionCandidates.first?.id
        let state = SemanticRecordingReviewState(
            sourceName: "stored checkout bundle",
            bundleDirectory: bundleDirectory,
            loadedAt: createdAt,
            bundle: loadedBundle,
            suggestions: suggestions,
            validationIssues: loadedBundle.validate(),
            artifactStatuses: artifactStatuses
        )
        return (state, candidateID)
    }

    private static func semanticReviewMissingArtifactsFixture(
        createdAt: Date,
        baseDirectory: URL
    ) throws -> (state: SemanticRecordingReviewState, candidateID: String?) {
        let rootDirectory = baseDirectory.appendingPathComponent(
            "fixture-semantic-review-missing-artifacts",
            isDirectory: true
        )
        let bundle = SemanticRecordingFixture.checkoutBundle(createdAt: createdAt)
        let bundleDirectory = rootDirectory.appendingPathComponent(
            bundle.id.uuidString,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: bundleDirectory.path) {
            try FileManager.default.removeItem(at: bundleDirectory)
        }

        try writeSemanticReviewStoredBundleManifest(bundle, to: bundleDirectory)
        try seedSemanticReviewStoredBundleFrameArtifacts(for: bundle, in: bundleDirectory)

        let loadedBundle = try readSemanticReviewStoredBundleManifest(from: bundleDirectory)
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: loadedBundle)
        let artifactStatuses = semanticReviewArtifactStatuses(
            for: loadedBundle,
            directory: bundleDirectory
        )
        let projection = SemanticRecordingReviewProjection(
            bundle: loadedBundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.waitEventID,
            selectedFrameID: SemanticRecordingFixture.afterClickFrameID
        )
        let candidateID = projection.selectedFrame?.conditionCandidates.first?.id
        let state = SemanticRecordingReviewState(
            sourceName: "stored checkout bundle with pruned artifacts",
            bundleDirectory: bundleDirectory,
            loadedAt: createdAt,
            bundle: loadedBundle,
            suggestions: suggestions,
            validationIssues: loadedBundle.validate(),
            artifactStatuses: artifactStatuses
        )
        return (state, candidateID)
    }

    private static func writeSemanticReviewStoredBundleManifest(
        _ bundle: SemanticRecordingBundle,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bundle)
        try data.write(
            to: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName),
            options: .atomic
        )
    }

    private static func readSemanticReviewStoredBundleManifest(
        from directory: URL
    ) throws -> SemanticRecordingBundle {
        let data = try Data(
            contentsOf: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SemanticRecordingBundle.self, from: data)
    }

    private static func seedSemanticReviewStoredBundleArtifacts(
        for bundle: SemanticRecordingBundle,
        in bundleDirectory: URL
    ) throws {
        try seedSemanticReviewStoredBundleFrameArtifacts(for: bundle, in: bundleDirectory)
        try writeEvidencePNG(
            to: bundleDirectory.appendingPathComponent("visual-index/templates/checkout-button.png"),
            size: CGSize(width: 180, height: 48),
            fill: NSColor(calibratedRed: 0.91, green: 0.55, blue: 0.18, alpha: 1),
            accent: NSColor.white,
            label: "Checkout"
        )
        try writeEvidencePNG(
            to: bundleDirectory.appendingPathComponent("visual-index/ocr/confirmation-region.png"),
            size: CGSize(width: 260, height: 42),
            fill: NSColor(calibratedRed: 0.21, green: 0.48, blue: 0.61, alpha: 1),
            accent: NSColor.white,
            label: "Order confirmed"
        )
        try writeEvidencePNG(
            to: bundleDirectory.appendingPathComponent("runs/run-001/condition-confirmation/watched-region.png"),
            size: CGSize(width: 260, height: 42),
            fill: NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.34, alpha: 1),
            accent: NSColor.white,
            label: "Runtime matched"
        )
        try writeEvidencePNG(
            to: bundleDirectory.appendingPathComponent("runs/run-001/condition-confirmation/diff.png"),
            size: CGSize(width: 260, height: 42),
            fill: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 1),
            accent: NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.21, alpha: 1),
            label: "Diff stable"
        )
    }

    private static func seedSemanticReviewStoredBundleFrameArtifacts(
        for bundle: SemanticRecordingBundle,
        in bundleDirectory: URL
    ) throws {
        for frame in bundle.frames {
            try writeEvidencePNG(
                to: bundleDirectory.appendingRecordingArtifactRef(frame.imageRef),
                size: CGSize(width: frame.imageSize?.width ?? 1_440, height: frame.imageSize?.height ?? 900),
                fill: NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.13, alpha: 1),
                accent: frame.id == SemanticRecordingFixture.afterClickFrameID
                    ? NSColor(calibratedRed: 0.24, green: 0.58, blue: 0.72, alpha: 1)
                    : NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.21, alpha: 1),
                label: frame.id == SemanticRecordingFixture.afterClickFrameID
                    ? "Order confirmed"
                    : "Checkout"
            )
        }
    }

    private static func semanticReviewArtifactStatuses(
        for bundle: SemanticRecordingBundle,
        directory: URL
    ) -> [String: SemanticRecordingReviewArtifactStatus] {
        Dictionary(uniqueKeysWithValues: semanticReviewArtifactRefs(in: bundle).map { ref in
            let url = directory.appendingRecordingArtifactRef(ref)
            return (
                ref.path,
                SemanticRecordingReviewArtifactStatus(
                    path: ref.path,
                    url: url,
                    exists: FileManager.default.fileExists(atPath: url.path)
                )
            )
        })
    }

    private static func semanticReviewArtifactRefs(
        in bundle: SemanticRecordingBundle
    ) -> [RecordingArtifactRef] {
        var refs: [RecordingArtifactRef] = []
        refs.append(contentsOf: bundle.videoSegments.map(\.artifactRef))
        refs.append(contentsOf: bundle.frames.map(\.imageRef))
        refs.append(contentsOf: bundle.visualObservations.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.sourcePreviews.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.runtimeSamples.map(\.artifactRef))
        refs.append(contentsOf: bundle.previewComparisons.compactMap(\.diffArtifactRef))
        refs.append(contentsOf: bundle.suppressions.compactMap(\.redactedArtifactRef))

        var seen = Set<String>()
        return refs
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }

    private static func writeEvidencePNG(
        to url: URL,
        size: CGSize,
        fill: NSColor,
        accent: NSColor,
        label: String
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let image = NSImage(size: size)
        image.lockFocus()
        fill.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        let inset = max(8, min(size.width, size.height) * 0.14)
        let badgeRect = CGRect(
            x: inset,
            y: inset,
            width: max(1, size.width - inset * 2),
            height: max(1, size.height - inset * 2)
        )
        accent.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8).fill()
        accent.setStroke()
        let outline = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        outline.lineWidth = max(2, min(size.width, size.height) * 0.025)
        outline.stroke()
        let fontSize = max(10, min(36, min(size.width, size.height) * 0.24))
        let textColor = fill.brightnessComponent > 0.62 ? NSColor.black : NSColor.white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: textColor
        ]
        NSString(string: label).draw(
            in: badgeRect.insetBy(dx: 10, dy: max(4, (badgeRect.height - fontSize) / 2.2)),
            withAttributes: attributes
        )
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.fixturePreparationFailed("Could not encode semantic review stored-bundle PNG.")
        }
        try pngData.write(to: url, options: .atomic)
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

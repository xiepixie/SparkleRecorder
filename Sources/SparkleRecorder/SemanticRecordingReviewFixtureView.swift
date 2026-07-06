import AppKit
import SwiftUI
import SparkleRecorderCore

struct SemanticRecordingReviewFixtureView: View {
    private let staticProjection: SemanticRecordingReviewProjection
    private let bundle: SemanticRecordingBundle?
    private let suggestions: [RecordingSuggestion]
    private let reviewState: SemanticRecordingReviewState?
    private let workflow: AutomationWorkflow?
    private let macros: [SavedMacro]
    private let onImportWorkflow: (AutomationWorkflow, URL?) -> Void

    @State private var selectedEventID: UUID?
    @State private var selectedFrameID: UUID?
    @State private var selectedCandidateID: String?
    @State private var regionSelection: SemanticRecordingFrameRegionSelection?
    @State private var pixelColorHexes: [String: String] = [:]
    @State private var suggestionReviewDecisions: [UUID: SuggestionReviewDecision] = [:]
    @State private var draftPatchResult: SemanticRecordingReviewDraftPatchResult?
    @State private var draftPatchErrorMessage = ""
    @State private var draftPreviewState: AutomationWorkflowDraftPreviewState?
    @State private var patchSaveMessage = ""
    @State private var artifactFeedback: SemanticRecordingReviewArtifactActionFeedback?
    @State private var dragStartPoint: CGPoint?
    @State private var dragRect: CGRect?
    @Environment(\.dismiss) private var dismiss

    init(projection: SemanticRecordingReviewProjection) {
        self.staticProjection = projection
        self.bundle = nil
        self.suggestions = []
        self.reviewState = nil
        self.workflow = nil
        self.macros = []
        self.onImportWorkflow = { _, _ in }
    }

    init(
        bundle: SemanticRecordingBundle,
        suggestions: [RecordingSuggestion] = [],
        selectedEventID: UUID? = nil,
        selectedFrameID: UUID? = nil,
        initialDraftPatchCandidateID: String? = nil
    ) {
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: selectedEventID,
            selectedFrameID: selectedFrameID
        )
        self.staticProjection = projection
        self.bundle = bundle
        self.suggestions = suggestions
        self.reviewState = nil
        self.workflow = nil
        self.macros = []
        self.onImportWorkflow = { _, _ in }
        _selectedEventID = State(initialValue: selectedEventID)
        _selectedFrameID = State(initialValue: selectedFrameID)
        _selectedCandidateID = State(initialValue: initialDraftPatchCandidateID)
        _draftPatchResult = State(initialValue: Self.initialDraftPatchResult(
            bundle: bundle,
            projection: projection,
            candidateID: initialDraftPatchCandidateID
        ))
    }

    init(
        state: SemanticRecordingReviewState,
        workflow: AutomationWorkflow? = nil,
        macros: [SavedMacro] = [],
        initialDraftPatchCandidateID: String? = nil,
        onImportWorkflow: @escaping (AutomationWorkflow, URL?) -> Void = { _, _ in }
    ) {
        let projection = SemanticRecordingReviewProjection(
            bundle: state.bundle,
            suggestions: state.suggestions
        )
        self.staticProjection = projection
        self.bundle = state.bundle
        self.suggestions = state.suggestions
        self.reviewState = state
        self.workflow = workflow
        self.macros = macros
        self.onImportWorkflow = onImportWorkflow
        _selectedCandidateID = State(initialValue: initialDraftPatchCandidateID)
        _draftPatchResult = State(initialValue: Self.initialDraftPatchResult(
            bundle: state.bundle,
            projection: projection,
            candidateID: initialDraftPatchCandidateID
        ))
    }

    private static func initialDraftPatchResult(
        bundle: SemanticRecordingBundle,
        projection: SemanticRecordingReviewProjection,
        candidateID: String?
    ) -> SemanticRecordingReviewDraftPatchResult? {
        guard let candidateID,
              let candidate = projection.selectedFrame?.conditionCandidates.first(where: { $0.id == candidateID }) else {
            return nil
        }

        return try? SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(candidate: candidate)
        )
    }

    private var projection: SemanticRecordingReviewProjection {
        guard let bundle else {
            return staticProjection
        }
        return SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: selectedEventID,
            selectedFrameID: selectedFrameID
        )
    }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 16) {
                    timeline
                        .frame(width: 360)

                    reviewFrame
                        .frame(maxWidth: .infinity)

                    inspector
                        .frame(width: 380)
                }
            }
            .padding(26)
        }
        .sheet(item: $draftPreviewState) { state in
            AutomationWorkflowDraftPreviewSheet(
                state: state,
                existingWorkflowName: workflow?.name,
                onImportWorkflow: onImportWorkflow
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Macro Review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text(projection.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(projection.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                if let reviewState {
                    Text(reviewState.sourceName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                }
            }

            Spacer()

            metric("Frames", projection.summary.frameCount)
            metric("Events", projection.summary.eventCount)
            metric("Evidence", projection.summary.observationCount + projection.summary.sourcePreviewCount)
            metric("Suggestions", projection.summary.suggestionCount)

            if reviewState != nil {
                Button("", systemImage: "xmark", action: dismiss.callAsFunction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(NSLocalizedString("Close Macro Review", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Close Macro Review", comment: ""))
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .frame(width: 78, alignment: .trailing)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Timeline")

            VStack(spacing: 8) {
                ForEach(projection.timelineRows) { row in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(timeLabel(row.recordingTime))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(row.isSelected ? Color(red: 0.34, green: 0.72, blue: 0.95) : Color.white.opacity(0.46))
                            Text(row.kind.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.42))
                            Spacer()
                            if row.suggestionCount > 0 {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.30))
                            }
                        }

                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            timelineChip("Before", row.beforeFrameID) {
                                selectTimelineFrame(row.beforeFrameID, eventID: row.id)
                            }
                            timelineChip("After", row.afterFrameID) {
                                selectTimelineFrame(row.afterFrameID, eventID: row.id)
                            }
                        }

                        Text("\(row.observationCount) overlays · \(row.sourcePreviewCount) refs")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.46))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(row.isSelected ? Color.white.opacity(0.085) : Color.white.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(row.isSelected ? Color(red: 0.34, green: 0.72, blue: 0.95).opacity(0.52) : Color.white.opacity(0.07), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectTimelineRow(row)
                    }
                }
            }
        }
    }

    private func timelineChip(
        _ title: String,
        _ id: UUID?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(shortID(id))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        .disabled(id == nil)
    }

    private var reviewFrame: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Selected Frame")
                Spacer()
                Text(projection.selectedFrame?.imageRefPath ?? "No frame selected")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
            }

            if let frame = projection.selectedFrame {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        frameBackdrop(frame)
                        if let regionSelection, regionSelection.frameID == frame.id {
                            overlayRect(
                                title: NSLocalizedString("Selected region", comment: ""),
                                bounds: regionSelection.bounds,
                                imageSize: frame.imageSize,
                                canvasSize: proxy.size,
                                color: Color(red: 0.48, green: 0.76, blue: 0.52)
                            )
                        }
                        if let dragRect {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(red: 0.48, green: 0.76, blue: 0.52), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .background(Color(red: 0.48, green: 0.76, blue: 0.52).opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                .frame(width: max(8, dragRect.width), height: max(8, dragRect.height))
                                .offset(x: dragRect.minX, y: dragRect.minY)
                        }
                        ForEach(frame.sourcePreviews) { source in
                            overlayRect(
                                title: source.title,
                                bounds: source.bounds,
                                imageSize: frame.imageSize,
                                canvasSize: proxy.size,
                                color: Color(red: 1.00, green: 0.72, blue: 0.30)
                            )
                        }
                        ForEach(frame.overlays) { overlay in
                            overlayRect(
                                title: overlay.title,
                                bounds: overlay.bounds,
                                imageSize: frame.imageSize,
                                canvasSize: proxy.size,
                                color: Color(red: 0.34, green: 0.72, blue: 0.95)
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(frameSelectionGesture(frame: frame, canvasSize: proxy.size))
                }
                .frame(minHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                frameStrip
            } else {
                Text("No review frame is available in this bundle.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.50, blue: 0.58))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func frameBackdrop(_ frame: SemanticRecordingReviewProjection.SelectedFrame) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.12, green: 0.14, blue: 0.15)
            if let image = artifactImage(path: frame.imageRefPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(frame.source.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("safe ref · \(frame.imageRefPath)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("surface · \(frame.surfaceID ?? "unknown")")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.58), Color.black.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    private func overlayRect(
        title: String,
        bounds: RecordingBounds?,
        imageSize: RecordingImageSize?,
        canvasSize: CGSize,
        color: Color
    ) -> some View {
        let rect = displayRect(for: bounds, imageSize: imageSize, canvasSize: canvasSize)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .stroke(color, lineWidth: 2)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
        .frame(width: max(42, rect.width), height: max(28, rect.height))
        .offset(x: rect.minX, y: rect.minY)
    }

    private var frameStrip: some View {
        HStack(spacing: 10) {
            ForEach(projection.frameStrip) { frame in
                VStack(alignment: .leading, spacing: 7) {
                    Text(timeLabel(frame.recordingTime))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(frame.isSelected ? Color(red: 0.34, green: 0.72, blue: 0.95) : Color.white.opacity(0.50))
                    Text(frame.source.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(frame.imageRefPath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(frame.isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(frame.isSelected ? Color(red: 0.34, green: 0.72, blue: 0.95).opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    selectFrame(frame)
                }
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            conditionCandidates
            draftPatchSection
            comparisonSection
            suggestionSection
            safetySection
        }
    }

    private var conditionCandidates: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Teach System")
            if let candidates = projection.selectedFrame?.conditionCandidates, !candidates.isEmpty {
                ForEach(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorRow(
                            title: candidate.title,
                            subtitle: candidate.kind.rawValue,
                            detail: candidate.artifactPath ?? "frame \(shortID(candidate.sourceFrameID))",
                            accent: Color(red: 0.48, green: 0.76, blue: 0.52)
                        )

                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Draft Patch", comment: ""), systemImage: "doc.badge.gearshape") {
                                createDraftPatch(for: candidate)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(bundle == nil)

                            if let reviewState, candidate.artifactPath != nil {
                                Button("", systemImage: "arrow.up.forward.app") {
                                    artifactFeedback = SemanticRecordingReviewPresenter.openArtifact(
                                        path: candidate.artifactPath,
                                        in: reviewState
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(reviewState.artifactStatus(for: candidate.artifactPath)?.exists != true)
                                .help(NSLocalizedString("Open candidate artifact", comment: ""))
                                .accessibilityLabel(NSLocalizedString("Open candidate artifact", comment: ""))
                            }
                        }

                        if candidate.kind == .pixelMatched {
                            VStack(alignment: .leading, spacing: 6) {
                                AutomationVisualColorPickerView(colorHex: pixelColorBinding(for: candidate))
                                Text(NSLocalizedString("Choose the target pixel color before creating a reviewed condition.", comment: ""))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.48))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            } else {
                emptyInspectorText("No condition candidates on this frame.")
            }
        }
    }

    @ViewBuilder
    private var draftPatchSection: some View {
        if let draftPatchResult {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Draft Patch")
                inspectorRow(
                    title: draftPatchResult.condition.type,
                    subtitle: draftPatchResult.taskKey,
                    detail: patchDetail(draftPatchResult),
                    accent: Color(red: 0.34, green: 0.72, blue: 0.95)
                )

                HStack(spacing: 8) {
                    Button(NSLocalizedString("Preview Draft", comment: ""), systemImage: "doc.text.magnifyingglass") {
                        openDraftPreview(draftPatchResult)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(NSLocalizedString("Save Patch", comment: ""), systemImage: "square.and.arrow.down") {
                        saveDraftPatch(draftPatchResult.patch)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("\(draftPatchResult.patch.ops.count) ops")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.52))

                    Spacer(minLength: 0)
                }

                if !patchSaveMessage.isEmpty {
                    Text(patchSaveMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
        } else if !draftPatchErrorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Draft Patch")
                Label(draftPatchErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.30))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let artifactFeedback {
            Label(artifactFeedbackMessage(artifactFeedback), systemImage: artifactFeedbackImage(artifactFeedback))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(artifactFeedbackTint(artifactFeedback))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Source / Runtime")
            if let comparisons = projection.selectedFrame?.comparisonRows, !comparisons.isEmpty {
                ForEach(comparisons) { comparison in
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorRow(
                            title: comparison.outcome.rawValue,
                            subtitle: "score \(percent(comparison.score)) · threshold \(percent(comparison.threshold))",
                            detail: comparison.reason ?? comparison.runtimeArtifactPath,
                            accent: Color(red: 1.00, green: 0.72, blue: 0.30)
                        )
                        artifactButtons(paths: [
                            comparison.sourceArtifactPath,
                            comparison.runtimeArtifactPath,
                            comparison.diffArtifactPath
                        ])
                    }
                }
            } else {
                emptyInspectorText("No runtime comparison for this frame.")
            }
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Suggestion Review")
            if !projection.suggestionRows.isEmpty {
                ForEach(projection.suggestionRows) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorRow(
                            title: suggestion.title,
                            subtitle: "\(suggestion.kind.rawValue) · confidence \(percent(suggestion.confidence))",
                            detail: suggestion.risk ?? suggestion.mutationPolicy,
                            accent: Color(red: 0.34, green: 0.72, blue: 0.95)
                        )

                        suggestionEvidenceSummary(suggestion)

                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Accept Patch", comment: ""), systemImage: "checkmark.circle") {
                                acceptSuggestion(suggestion)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(bundle == nil)

                            Button(NSLocalizedString("Reject", comment: ""), systemImage: "xmark.circle") {
                                rejectSuggestion(suggestion)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let decision = suggestionReviewDecisions[suggestion.id] {
                                Label(decision.title, systemImage: decision.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(decision.tint)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                emptyInspectorText("No suggestions for this fixture.")
            }
        }
    }

    private func suggestionEvidenceSummary(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(suggestion.evidence.prefix(2).enumerated()), id: \.offset) { _, evidence in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                    Text(suggestionEvidenceLabel(evidence))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .lineLimit(1)
                    if let summary = evidence.summary {
                        Text(summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Safety")
            inspectorRow(
                title: "Review-only mutation",
                subtitle: "\(projection.suppressionRows.count) suppression records",
                detail: projection.suggestionRows.first?.mutationPolicy ?? "No workflow mutation from Review without an accepted action.",
                accent: Color(red: 1.00, green: 0.50, blue: 0.58)
            )
        }
    }

    private func inspectorRow(
        title: String,
        subtitle: String,
        detail: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 8, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func artifactButtons(paths: [String?]) -> some View {
        if let reviewState {
            let availablePaths = paths
                .compactMap { $0 }
                .filter { reviewState.artifactStatus(for: $0)?.exists == true }
            if !availablePaths.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(availablePaths.prefix(3).enumerated()), id: \.offset) { _, path in
                        Button("", systemImage: "arrow.up.forward.app") {
                            artifactFeedback = SemanticRecordingReviewPresenter.openArtifact(path: path, in: reviewState)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(String(format: NSLocalizedString("Open %@", comment: ""), path))
                        .accessibilityLabel(String(format: NSLocalizedString("Open %@", comment: ""), path))

                        Button("", systemImage: "folder") {
                            artifactFeedback = SemanticRecordingReviewPresenter.revealArtifact(path: path, in: reviewState)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(String(format: NSLocalizedString("Reveal %@", comment: ""), path))
                        .accessibilityLabel(String(format: NSLocalizedString("Reveal %@", comment: ""), path))
                    }
                }
            }
        }
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.50))
    }

    private func emptyInspectorText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func displayRect(
        for bounds: RecordingBounds?,
        imageSize: RecordingImageSize?,
        canvasSize: CGSize
    ) -> CGRect {
        guard let bounds,
              let imageSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return CGRect(x: 22, y: 22, width: 180, height: 72)
        }

        let imageWidth = CGFloat(imageSize.width)
        let imageHeight = CGFloat(imageSize.height)
        let scale = min(canvasSize.width / imageWidth, canvasSize.height / imageHeight)
        let renderedWidth = imageWidth * scale
        let renderedHeight = imageHeight * scale
        let originX = (canvasSize.width - renderedWidth) / 2
        let originY = (canvasSize.height - renderedHeight) / 2
        let rect = bounds.rect
        return CGRect(
            x: originX + CGFloat(rect.x) * scale,
            y: originY + CGFloat(rect.y) * scale,
            width: CGFloat(rect.width) * scale,
            height: CGFloat(rect.height) * scale
        )
    }

    private func frameSelectionGesture(
        frame: SemanticRecordingReviewProjection.SelectedFrame,
        canvasSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard bundle != nil else {
                    return
                }
                let start = dragStartPoint ?? value.startLocation
                dragStartPoint = start
                dragRect = normalizedRect(from: start, to: value.location)
            }
            .onEnded { value in
                defer {
                    dragStartPoint = nil
                    dragRect = nil
                }
                guard bundle != nil else {
                    return
                }
                let start = dragStartPoint ?? value.startLocation
                let canvasRect = normalizedRect(from: start, to: value.location)
                guard let bounds = recordingBounds(from: canvasRect, frame: frame, canvasSize: canvasSize) else {
                    return
                }
                let candidate = selectedCandidate(in: frame) ?? frame.conditionCandidates.first
                regionSelection = SemanticRecordingFrameRegionSelection(
                    frameID: frame.id,
                    surfaceID: frame.surfaceID,
                    bounds: bounds,
                    imageSize: frame.imageSize,
                    label: NSLocalizedString("Selected frame region", comment: ""),
                    candidateKind: candidate?.kind ?? .ocrWait,
                    sourcePreviewRefID: candidate?.sourcePreviewRefID,
                    observationID: candidate?.observationID,
                    artifactPath: candidate?.artifactPath
                )
                draftPatchResult = nil
                draftPatchErrorMessage = ""
                patchSaveMessage = ""
            }
    }

    private func recordingBounds(
        from canvasRect: CGRect,
        frame: SemanticRecordingReviewProjection.SelectedFrame,
        canvasSize: CGSize
    ) -> RecordingBounds? {
        guard let imageRect = renderedImageRect(imageSize: frame.imageSize, canvasSize: canvasSize) else {
            return nil
        }
        let clipped = canvasRect.intersection(imageRect)
        guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else {
            return nil
        }
        let imageWidth = CGFloat(frame.imageSize?.width ?? 0)
        let imageHeight = CGFloat(frame.imageSize?.height ?? 0)
        guard imageRect.width > 0, imageRect.height > 0, imageWidth > 0, imageHeight > 0 else {
            return nil
        }
        let scaleX = imageWidth / imageRect.width
        let scaleY = imageHeight / imageRect.height
        return RecordingBounds(
            rect: RecordingRect(
                x: Double((clipped.minX - imageRect.minX) * scaleX),
                y: Double((clipped.minY - imageRect.minY) * scaleY),
                width: Double(clipped.width * scaleX),
                height: Double(clipped.height * scaleY)
            ),
            coordinateSpace: .windowPixels
        )
    }

    private func renderedImageRect(
        imageSize: RecordingImageSize?,
        canvasSize: CGSize
    ) -> CGRect? {
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return nil
        }

        let imageWidth = CGFloat(imageSize.width)
        let imageHeight = CGFloat(imageSize.height)
        let scale = min(canvasSize.width / imageWidth, canvasSize.height / imageHeight)
        let renderedWidth = imageWidth * scale
        let renderedHeight = imageHeight * scale
        return CGRect(
            x: (canvasSize.width - renderedWidth) / 2,
            y: (canvasSize.height - renderedHeight) / 2,
            width: renderedWidth,
            height: renderedHeight
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func selectTimelineRow(_ row: SemanticRecordingReviewProjection.TimelineRow) {
        selectedEventID = row.id
        selectedFrameID = row.primaryFrameID ?? row.afterFrameID ?? row.beforeFrameID
        selectedCandidateID = nil
        regionSelection = nil
        draftPatchResult = nil
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func selectTimelineFrame(_ frameID: UUID?, eventID: UUID) {
        guard let frameID else {
            return
        }
        selectedEventID = eventID
        selectedFrameID = frameID
        selectedCandidateID = nil
        regionSelection = nil
        draftPatchResult = nil
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func selectFrame(_ frame: SemanticRecordingReviewProjection.FrameStripItem) {
        selectedFrameID = frame.id
        selectedCandidateID = nil
        regionSelection = nil
        draftPatchResult = nil
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func selectedCandidate(
        in frame: SemanticRecordingReviewProjection.SelectedFrame
    ) -> SemanticRecordingReviewProjection.ConditionCandidateRow? {
        guard let selectedCandidateID else {
            return nil
        }
        return frame.conditionCandidates.first { $0.id == selectedCandidateID }
    }

    private func createDraftPatch(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) {
        guard let bundle else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString("Open a live bundle before creating a draft patch.", comment: "")
            return
        }

        selectedCandidateID = candidate.id
        let effectiveSelection = regionSelection?.frameID == candidate.sourceFrameID ? regionSelection : nil
        do {
            draftPatchResult = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
                bundle: bundle,
                request: SemanticRecordingReviewDraftPatchRequest(
                    candidate: candidate,
                    regionSelection: effectiveSelection,
                    pixelColorHex: pixelColorHex(for: candidate)
                )
            )
            draftPatchErrorMessage = ""
            patchSaveMessage = ""
        } catch {
            draftPatchResult = nil
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func acceptSuggestion(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) {
        guard let bundle else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString("Open a live bundle before accepting a suggestion.", comment: "")
            return
        }
        guard let match = suggestionPatchCandidate(suggestion, bundle: bundle) else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString("No patchable evidence was found for this suggestion.", comment: "")
            return
        }

        selectedEventID = match.eventID
        selectedFrameID = match.frameID
        selectedCandidateID = match.candidate.id
        let effectiveSelection = regionSelection?.frameID == match.candidate.sourceFrameID ? regionSelection : nil
        do {
            draftPatchResult = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
                bundle: bundle,
                request: SemanticRecordingReviewDraftPatchRequest(
                    candidate: match.candidate,
                    regionSelection: effectiveSelection,
                    pixelColorHex: pixelColorHex(for: match.candidate)
                )
            )
            draftPatchErrorMessage = ""
            patchSaveMessage = ""
            suggestionReviewDecisions[suggestion.id] = .accepted
        } catch {
            draftPatchResult = nil
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func rejectSuggestion(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) {
        suggestionReviewDecisions[suggestion.id] = .rejected
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func suggestionPatchCandidate(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow,
        bundle: SemanticRecordingBundle
    ) -> (
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        frameID: UUID,
        eventID: UUID?
    )? {
        for evidence in suggestion.evidence {
            let reviewProjection = SemanticRecordingReviewProjection(
                bundle: bundle,
                suggestions: suggestions,
                selectedEventID: evidence.eventIDs.first,
                selectedFrameID: evidence.frameID
            )
            guard let frame = reviewProjection.selectedFrame else {
                continue
            }
            let candidate = frame.conditionCandidates.first { candidate in
                candidateMatches(candidate, evidence: evidence)
            } ?? frame.conditionCandidates.first
            if let candidate {
                return (candidate, frame.id, evidence.eventIDs.first)
            }
        }
        return nil
    }

    private func candidateMatches(
        _ candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        evidence: SemanticRecordingReviewProjection.EvidenceRow
    ) -> Bool {
        if let artifactPath = evidence.artifactPath, candidate.artifactPath == artifactPath {
            return true
        }
        if let observationID = candidate.observationID, evidence.observationIDs.contains(observationID) {
            return true
        }
        return evidence.frameID == candidate.sourceFrameID
    }

    private func pixelColorBinding(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) -> Binding<String> {
        Binding(
            get: {
                pixelColorHexes[candidate.id] ?? ""
            },
            set: { newValue in
                pixelColorHexes[candidate.id] = newValue
                if selectedCandidateID == candidate.id {
                    draftPatchResult = nil
                    draftPatchErrorMessage = ""
                    patchSaveMessage = ""
                }
            }
        )
    }

    private func pixelColorHex(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) -> String? {
        guard candidate.kind == .pixelMatched else {
            return nil
        }
        let value = pixelColorHexes[candidate.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func saveDraftPatch(_ patch: AutomationWorkflowDraftPatchDocument) {
        let defaultName = "macro-review-\(shortID(projection.recordingID))-patch.json"
        SemanticRecordingReviewPresenter.savePatch(patch, defaultName: defaultName) { result in
            switch result {
            case .success(let url):
                patchSaveMessage = String(format: NSLocalizedString("Saved %@", comment: ""), url.lastPathComponent)
            case .failure(let error):
                patchSaveMessage = String(describing: error)
            }
        }
    }

    private func openDraftPreview(_ result: SemanticRecordingReviewDraftPatchResult) {
        do {
            draftPreviewState = try SemanticRecordingReviewPresenter.previewState(
                applying: result.patch,
                to: workflow,
                macros: macros,
                sourceName: "Macro Review \(shortID(projection.recordingID))",
                sourceDirectory: reviewState?.bundleDirectory
            )
            draftPatchErrorMessage = ""
        } catch {
            draftPreviewState = nil
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func patchDetail(_ result: SemanticRecordingReviewDraftPatchResult) -> String {
        var parts = [result.appliesToExistingTask ? "setCondition" : "addTask"]
        if let region = result.region {
            parts.append("region \(region.key)")
        }
        if let imageAsset = result.imageAsset {
            parts.append("image \(imageAsset.key)")
        }
        if let baselineAsset = result.baselineAsset {
            parts.append("baseline \(baselineAsset.key)")
        }
        return parts.joined(separator: " · ")
    }

    private func artifactImage(path: String?) -> NSImage? {
        guard let status = reviewState?.artifactStatus(for: path),
              status.exists else {
            return nil
        }
        return NSImage(contentsOf: status.url)
    }

    private func artifactFeedbackMessage(
        _ feedback: SemanticRecordingReviewArtifactActionFeedback
    ) -> String {
        switch feedback {
        case .succeeded(.open, let path):
            return String(format: NSLocalizedString("Opened %@", comment: ""), path)
        case .succeeded(.reveal, let path):
            return String(format: NSLocalizedString("Revealed %@", comment: ""), path)
        case .failed(_, let message):
            return message
        }
    }

    private func artifactFeedbackImage(
        _ feedback: SemanticRecordingReviewArtifactActionFeedback
    ) -> String {
        switch feedback {
        case .succeeded(.open, _):
            return "arrow.up.forward.app"
        case .succeeded(.reveal, _):
            return "folder"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func artifactFeedbackTint(
        _ feedback: SemanticRecordingReviewArtifactActionFeedback
    ) -> Color {
        switch feedback {
        case .succeeded:
            return Color(red: 0.48, green: 0.76, blue: 0.52)
        case .failed:
            return Color(red: 1.00, green: 0.72, blue: 0.30)
        }
    }

    private func timeLabel(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func shortID(_ id: UUID?) -> String {
        guard let id else { return "not set" }
        return String(id.uuidString.suffix(8))
    }

    private func suggestionEvidenceLabel(_ evidence: SemanticRecordingReviewProjection.EvidenceRow) -> String {
        var parts: [String] = []
        if let frameID = evidence.frameID {
            parts.append("frame \(shortID(frameID))")
        }
        if let artifactPath = evidence.artifactPath {
            parts.append(artifactPath)
        } else if let observationID = evidence.observationIDs.first {
            parts.append("obs \(shortID(observationID))")
        }
        return parts.isEmpty ? NSLocalizedString("evidence", comment: "") : parts.joined(separator: " · ")
    }
}

private enum SuggestionReviewDecision {
    case accepted
    case rejected

    var title: String {
        switch self {
        case .accepted:
            return NSLocalizedString("Accepted", comment: "")
        case .rejected:
            return NSLocalizedString("Rejected", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .accepted:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .accepted:
            return Color(red: 0.48, green: 0.76, blue: 0.52)
        case .rejected:
            return Color(red: 1.00, green: 0.50, blue: 0.58)
        }
    }
}

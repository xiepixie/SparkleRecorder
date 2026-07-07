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
    private let runTargetPresentation: SemanticRecordingReviewRunTargetPresentation?
    private let runTargetEvidence: SemanticRecordingReviewRunTargetEvidence?

    @State private var selectedEventID: UUID?
    @State private var selectedFrameID: UUID?
    @State private var selectedCandidateID: String?
    @State private var regionSelection: SemanticRecordingFrameRegionSelection?
    @State private var pixelColorHexes: [String: String] = [:]
    @State private var suggestionReviewDecisions: [UUID: SuggestionReviewDecision] = [:]
    @State private var draftPatchResult: SemanticRecordingReviewDraftPatchResult?
    @State private var draftPatchSourceSuggestionID: UUID?
    @State private var draftPatchErrorMessage = ""
    @State private var draftPreviewState: AutomationWorkflowDraftPreviewState?
    @State private var draftPreviewActionPresentations: [SemanticRecordingReviewActionPresentation] = []
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
        self.runTargetPresentation = nil
        self.runTargetEvidence = nil
    }

    init(
        bundle: SemanticRecordingBundle,
        suggestions: [RecordingSuggestion] = [],
        selectedEventID: UUID? = nil,
        selectedFrameID: UUID? = nil,
        initialDraftPatchCandidateID: String? = nil,
        initialRegionSelection: SemanticRecordingFrameRegionSelection? = nil,
        initialPixelColorHexes: [String: String] = [:],
        initialAcceptedSuggestionID: UUID? = nil,
        initialRejectedSuggestionID: UUID? = nil,
        initialDraftPreviewActionPresentations: [SemanticRecordingReviewActionPresentation] = [],
        initialRunTargetPresentation: SemanticRecordingReviewRunTargetPresentation? = nil,
        initialRunTargetEvidence: SemanticRecordingReviewRunTargetEvidence? = nil
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
        self.runTargetPresentation = initialRunTargetPresentation
        self.runTargetEvidence = initialRunTargetEvidence
        _selectedEventID = State(initialValue: selectedEventID)
        _selectedFrameID = State(initialValue: selectedFrameID)
        _selectedCandidateID = State(initialValue: initialDraftPatchCandidateID)
        _regionSelection = State(initialValue: initialRegionSelection)
        _pixelColorHexes = State(initialValue: initialPixelColorHexes)
        _draftPatchResult = State(initialValue: Self.initialDraftPatchResult(
            bundle: bundle,
            projection: projection,
            candidateID: initialDraftPatchCandidateID,
            regionSelection: initialRegionSelection,
            pixelColorHexes: initialPixelColorHexes
        ))
        _draftPatchSourceSuggestionID = State(initialValue: initialAcceptedSuggestionID)
        _suggestionReviewDecisions = State(initialValue: Self.initialSuggestionReviewDecisions(
            acceptedID: initialAcceptedSuggestionID,
            rejectedID: initialRejectedSuggestionID
        ))
        _draftPreviewActionPresentations = State(initialValue: initialDraftPreviewActionPresentations)
    }

    init(
        state: SemanticRecordingReviewState,
        workflow: AutomationWorkflow? = nil,
        macros: [SavedMacro] = [],
        selectedEventID: UUID? = nil,
        selectedFrameID: UUID? = nil,
        initialDraftPatchCandidateID: String? = nil,
        initialRunTargetPresentation: SemanticRecordingReviewRunTargetPresentation? = nil,
        initialRunTargetEvidence: SemanticRecordingReviewRunTargetEvidence? = nil,
        onImportWorkflow: @escaping (AutomationWorkflow, URL?) -> Void = { _, _ in }
    ) {
        let projection = SemanticRecordingReviewProjection(
            bundle: state.bundle,
            suggestions: state.suggestions,
            selectedEventID: selectedEventID,
            selectedFrameID: selectedFrameID
        )
        self.staticProjection = projection
        self.bundle = state.bundle
        self.suggestions = state.suggestions
        self.reviewState = state
        self.workflow = workflow
        self.macros = macros
        self.onImportWorkflow = onImportWorkflow
        self.runTargetPresentation = initialRunTargetPresentation
        self.runTargetEvidence = initialRunTargetEvidence
        _selectedEventID = State(initialValue: selectedEventID)
        _selectedFrameID = State(initialValue: selectedFrameID)
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
        candidateID: String?,
        regionSelection: SemanticRecordingFrameRegionSelection? = nil,
        pixelColorHexes: [String: String] = [:]
    ) -> SemanticRecordingReviewDraftPatchResult? {
        guard let candidateID,
              let candidate = projection.selectedFrame?.conditionCandidates.first(where: { $0.id == candidateID }) else {
            return nil
        }

        return try? SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                regionSelection: regionSelection,
                pixelColorHex: candidate.kind == .pixelMatched
                    ? pixelColorHexes[candidate.id]
                    : nil
            )
        )
    }

    private static func initialSuggestionReviewDecisions(
        acceptedID: UUID?,
        rejectedID: UUID?
    ) -> [UUID: SuggestionReviewDecision] {
        var decisions: [UUID: SuggestionReviewDecision] = [:]
        if let acceptedID {
            decisions[acceptedID] = .accepted
        }
        if let rejectedID {
            decisions[rejectedID] = .rejected
        }
        return decisions
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

    private var repeatUntilBodyResolution: SemanticRecordingReviewRepeatUntilBodyResolution? {
        guard let bundle else {
            return nil
        }
        return SemanticRecordingReviewRepeatUntilBodyResolver.resolve(
            recordingID: bundle.id,
            macros: macros
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.08, green: 0.09, blue: 0.10)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 16) {
                    timeline
                        .frame(width: 360)
                        .clipped()

                    reviewFrame
                        .frame(width: 440)
                        .clipped()
                        .zIndex(0)

                    inspector
                        .frame(width: 380)
                        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
                        .clipped()
                        .zIndex(1)
                }
                .frame(width: 1_228, alignment: .topLeading)
                .clipped()
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(frameSelectionGesture(frame: frame, canvasSize: proxy.size))
                }
                .frame(width: 440, height: 480)
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
        .frame(width: 440, alignment: .topLeading)
        .clipped()
    }

    private func frameBackdrop(_ frame: SemanticRecordingReviewProjection.SelectedFrame) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.12, green: 0.14, blue: 0.15)
            if let image = artifactImage(path: frame.imageRefPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(frame.source.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(frame.isRedacted ? "redacted ref" : "safe ref") · \(frame.imageRefPath)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                if frame.isRedacted {
                    Text("source ref · \(frame.sourceImageRefPath)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
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
        .clipped()
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
                    Text("\(frame.isRedacted ? "redacted" : "ref") · \(frame.imageRefPath)")
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
        .frame(width: 440, alignment: .leading)
        .clipped()
    }

    private var inspector: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                runTargetSection
                bundleHealthSection
                conditionCandidates
                regionSelectionSection
                draftPatchSection
                comparisonSection
                suggestionSection
                safetySection
            }
            .frame(width: 380, alignment: .topLeading)
        }
        .frame(width: 380, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var runTargetSection: some View {
        if let runTargetEvidence {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Run Target")
                inspectorRow(
                    title: runTargetEvidence.title,
                    subtitle: NSLocalizedString("Opened from Run Detail", comment: ""),
                    detail: runTargetEvidence.detail,
                    accent: Color(red: 0.34, green: 0.72, blue: 0.95)
                )

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(runTargetEvidence.rows) { row in
                        bundleHealthInfoRow(
                            title: row.label,
                            value: row.value,
                            systemImage: runTargetEvidenceRowIcon(row.kind),
                            tint: Color(red: 0.34, green: 0.72, blue: 0.95)
                        )
                    }
                }
            }
        } else if let runTargetPresentation {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Run Target")
                inspectorRow(
                    title: runTargetPresentation.title,
                    subtitle: NSLocalizedString("Opened from Run Detail", comment: ""),
                    detail: runTargetPresentation.detail,
                    accent: Color(red: 0.34, green: 0.72, blue: 0.95)
                )

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(runTargetPresentation.badges.enumerated()), id: \.offset) { _, badge in
                        bundleHealthInfoRow(
                            title: badge.title,
                            value: badge.value,
                            systemImage: "scope",
                            tint: Color(red: 0.34, green: 0.72, blue: 0.95)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bundleHealthSection: some View {
        if let reviewState {
            let counts = artifactAvailabilityCounts(reviewState)
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Bundle Health")
                inspectorRow(
                    title: reviewState.validationIssues.isEmpty
                        ? NSLocalizedString("Bundle ready", comment: "")
                        : String(
                            format: NSLocalizedString("%d validation issues", comment: ""),
                            reviewState.validationIssues.count
                        ),
                    subtitle: reviewState.sourceName,
                    detail: bundleHealthDetail(reviewState),
                    accent: reviewState.validationIssues.isEmpty
                        ? Color(red: 0.48, green: 0.76, blue: 0.52)
                        : Color(red: 1.00, green: 0.72, blue: 0.30)
                )

                HStack(spacing: 8) {
                    bundleHealthMetric(
                        NSLocalizedString("Available", comment: ""),
                        "\(counts.available)/\(counts.total)",
                        tint: Color(red: 0.48, green: 0.76, blue: 0.52)
                    )
                    bundleHealthMetric(
                        NSLocalizedString("Missing", comment: ""),
                        "\(counts.missing)",
                        tint: counts.missing == 0
                            ? Color.white.opacity(0.40)
                            : Color(red: 1.00, green: 0.72, blue: 0.30)
                    )
                    bundleHealthMetric(
                        NSLocalizedString("Suppressed", comment: ""),
                        "\(projection.suppressionRows.count)",
                        tint: projection.suppressionRows.isEmpty
                            ? Color.white.opacity(0.40)
                            : Color(red: 1.00, green: 0.50, blue: 0.58)
                    )
                }

                if !reviewState.validationIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(reviewState.validationIssues.prefix(2).enumerated()), id: \.offset) { _, issue in
                            bundleHealthInfoRow(
                                title: NSLocalizedString("Validation", comment: ""),
                                value: validationIssueLabel(issue),
                                systemImage: "exclamationmark.triangle",
                                tint: Color(red: 1.00, green: 0.72, blue: 0.30)
                            )
                        }
                    }
                }

                if !projection.suppressionRows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(projection.suppressionRows.prefix(2)) { suppression in
                            bundleHealthInfoRow(
                                title: suppression.reason.rawValue,
                                value: suppressionDetail(suppression),
                                systemImage: "hand.raised",
                                tint: Color(red: 1.00, green: 0.50, blue: 0.58)
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var regionSelectionSection: some View {
        if let frame = projection.selectedFrame,
           let regionSelection,
           regionSelection.frameID == frame.id {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Selected Region")
                inspectorRow(
                    title: regionSelection.label ?? NSLocalizedString("Reviewed frame selection", comment: ""),
                    subtitle: regionSelection.candidateKind.rawValue,
                    detail: regionSelectionDetail(regionSelection),
                    accent: Color(red: 0.48, green: 0.76, blue: 0.52)
                )

                HStack(spacing: 8) {
                    Button(NSLocalizedString("Draft Selection", comment: ""), systemImage: "selection.pin.in.out") {
                        if let candidate = selectedCandidate(in: frame) ?? frame.conditionCandidates.first {
                            createDraftPatch(for: candidate)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(bundle == nil || frame.conditionCandidates.isEmpty)

                    Button("", systemImage: "xmark.circle") {
                        clearSelectedRegion()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(NSLocalizedString("Clear selected frame region", comment: ""))
                    .accessibilityLabel(NSLocalizedString("Clear selected frame region", comment: ""))

                    Spacer(minLength: 0)
                }

                Text(NSLocalizedString("Drafts from this region stay review-only until Draft Preview import.", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                        artifactAvailabilityLine(path: candidate.artifactPath)
                        conditionCandidateReviewActionContract(candidate)

                        HStack(spacing: 8) {
                            let repeatUntilResolution = repeatUntilBodyResolution
                            Button(NSLocalizedString("Draft Patch", comment: ""), systemImage: "doc.badge.gearshape") {
                                createDraftPatch(for: candidate)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(bundle == nil)

                            Button(NSLocalizedString("Repeat Until", comment: ""), systemImage: "repeat") {
                                createRepeatUntilDraftPatch(for: candidate)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(bundle == nil || repeatUntilResolution?.isResolved != true)
                            .help(NSLocalizedString(
                                repeatUntilResolution?.message
                                    ?? "Open a linked semantic recording before creating a Repeat-Until loop.",
                                comment: ""
                            ))

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

                draftPatchActionContract(draftPatchResult)

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
                        comparisonArtifactStrip(comparison)
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

                        suggestionReviewActionContract(suggestion)

                        if let decision = suggestionReviewDecisions[suggestion.id] {
                            suggestionActionSemanticsSummary(suggestion, decision: decision)
                        }

                        suggestionEvidenceSummary(suggestion)

                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Accept", comment: ""), systemImage: "checkmark.circle") {
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

                                Text(decision.detail)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.46))
                                    .lineLimit(1)

                                Button("", systemImage: "arrow.uturn.backward.circle") {
                                    clearSuggestionDecision(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(NSLocalizedString("Undo suggestion review decision", comment: ""))
                                .accessibilityLabel(NSLocalizedString("Undo suggestion review decision", comment: ""))
                            }

                            Spacer(minLength: 0)
                        }

                        if let decision = suggestionReviewDecisions[suggestion.id] {
                            suggestionDecisionExplanation(suggestion, decision: decision)
                        }
                    }
                }
            } else {
                emptyInspectorText("No suggestions for this fixture.")
            }
        }
    }

    private func suggestionActionSemanticsSummary(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow,
        decision: SuggestionReviewDecision
    ) -> some View {
        let semantics = decision.actionSemantics(for: suggestion)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: semantics.mutatesWorkflow ? "square.and.arrow.down" : decision.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(decision.tint)
            Text(semantics.actionName.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.60))
                .lineLimit(1)
            Text(mutationBoundaryLabel(semantics.mutationBoundary))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.46))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(decision.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(decision.tint.opacity(0.20), lineWidth: 1)
        )
    }

    private func suggestionReviewActionContract(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> some View {
        let accept = SemanticRecordingReviewActionSemantics.acceptSuggestion(suggestion)
        let reject = SemanticRecordingReviewActionSemantics.rejectSuggestion(suggestion)
        let clear = SemanticRecordingReviewActionSemantics.clearDecision(suggestion)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.34, green: 0.72, blue: 0.95))
                Text(NSLocalizedString("Review Actions", comment: ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text(reviewActionEvidenceLabel(accept.evidence))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            reviewActionContractRow(accept)
            reviewActionContractRow(reject)
            reviewActionContractRow(clear)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func conditionCandidateReviewActionContract(
        _ candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) -> some View {
        let selection = regionSelection?.frameID == candidate.sourceFrameID
            ? regionSelection
            : nil
        let semantics = SemanticRecordingReviewActionSemantics.draftCandidate(
            candidate,
            regionSelection: selection
        )
        let presentation = SemanticRecordingReviewActionPresentation(semantics)
        let rows = presentation.rows.filter { row in
            switch row.kind {
            case .artifact, .bounds, .frame, .sourcePreview, .summary:
                return true
            case .action,
                 .draftCondition,
                 .draftTask,
                 .events,
                 .materializedArtifact,
                 .materializedDigest,
                 .mutationBoundary,
                 .mutationEffect,
                 .observations,
                 .suggestion,
                 .visualAsset,
                 .visualRegion:
                return false
            }
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.34, green: 0.72, blue: 0.95))
                Text(NSLocalizedString("Review Action", comment: ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text(reviewActionEvidenceLabel(semantics.evidence))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            reviewActionContractRow(semantics)

            ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(width: 78, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func draftPatchActionContract(
        _ result: SemanticRecordingReviewDraftPatchResult
    ) -> some View {
        let preview = SemanticRecordingReviewActionSemantics.previewDraft(result)
        let importAction = SemanticRecordingReviewActionSemantics.importDraft(result)
        let presentations = draftPreviewActionPresentations.isEmpty
            ? [
                SemanticRecordingReviewActionPresentation(preview),
                SemanticRecordingReviewActionPresentation(importAction)
            ]
            : draftPreviewActionPresentations

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.34, green: 0.72, blue: 0.95))
                Text(NSLocalizedString("Review Actions", comment: ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text(result.actionEvidence.draftTaskKey ?? result.taskKey)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ForEach(Array(presentations.enumerated()), id: \.offset) { _, presentation in
                reviewActionPresentationRows(presentation)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func reviewActionContractRow(
        _ semantics: SemanticRecordingReviewActionSemantics
    ) -> some View {
        let presentation = SemanticRecordingReviewActionPresentation(semantics)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: reviewActionSystemImage(semantics))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(reviewActionTint(semantics))
                Text(semantics.actionName.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text(mutationBoundaryLabel(semantics.mutationBoundary))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(reviewActionTint(semantics).opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            reviewActionEffectLine(
                presentation,
                tint: reviewActionTint(semantics)
            )
        }
    }

    private func reviewActionPresentationRows(
        _ semantics: SemanticRecordingReviewActionSemantics
    ) -> some View {
        reviewActionPresentationRows(SemanticRecordingReviewActionPresentation(semantics))
    }

    @ViewBuilder
    private func reviewActionEffectLine(
        _ presentation: SemanticRecordingReviewActionPresentation,
        tint: Color
    ) -> some View {
        if let row = presentation.rows.first(where: { $0.kind == .mutationEffect }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NSLocalizedString(row.label, comment: ""))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.64))
                    .frame(width: 44, alignment: .leading)
                Text(NSLocalizedString(row.value, comment: ""))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
        }
    }

    private func reviewActionPresentationRows(
        _ presentation: SemanticRecordingReviewActionPresentation
    ) -> some View {
        let rows = presentation.reviewVisibleRows

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: reviewActionSystemImage(presentation.actionName))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(reviewActionTint(presentation.actionName))
                Text(presentation.actionName.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text(reviewActionBoundaryValue(presentation))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(reviewActionTint(presentation.actionName).opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            ForEach(Array(rows.prefix(6).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(width: 78, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
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

    private func suggestionDecisionExplanation(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow,
        decision: SuggestionReviewDecision
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(suggestionDecisionExplanationRows(suggestion, decision: decision).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: row.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(row.tint)
                    Text(row.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.50))
                        .frame(width: 72, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(decision.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(decision.tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func suggestionDecisionExplanationRows(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow,
        decision: SuggestionReviewDecision
    ) -> [(title: String, value: String, systemImage: String, tint: Color)] {
        let semantics = decision.actionSemantics(for: suggestion)
        let evidenceValue = suggestion.evidence.first
            .map(suggestionDecisionEvidenceLabel)
            ?? NSLocalizedString("No evidence ref recorded.", comment: "")

        switch decision {
        case .accepted:
            return [
                (
                    NSLocalizedString("Action", comment: ""),
                    "\(semantics.actionName.rawValue) · \(mutationBoundaryLabel(semantics.mutationBoundary))",
                    "checkmark.circle",
                    Color(red: 0.48, green: 0.76, blue: 0.52)
                ),
                (
                    NSLocalizedString("Evidence", comment: ""),
                    evidenceValue,
                    "link",
                    Color(red: 0.34, green: 0.72, blue: 0.95)
                ),
                (
                    NSLocalizedString("Patch", comment: ""),
                    acceptedSuggestionPatchExplanation(suggestion),
                    "doc.badge.gearshape",
                    Color(red: 0.48, green: 0.76, blue: 0.52)
                )
            ]
        case .rejected:
            return [
                (
                    NSLocalizedString("Action", comment: ""),
                    "\(semantics.actionName.rawValue) · \(mutationBoundaryLabel(semantics.mutationBoundary))",
                    "xmark.circle",
                    Color(red: 1.00, green: 0.50, blue: 0.58)
                ),
                (
                    NSLocalizedString("Decision", comment: ""),
                    NSLocalizedString("No workflow change recorded for this suggestion.", comment: ""),
                    "xmark.circle",
                    Color(red: 1.00, green: 0.50, blue: 0.58)
                ),
                (
                    NSLocalizedString("Evidence", comment: ""),
                    evidenceValue,
                    "link",
                    Color.white.opacity(0.48)
                )
            ]
        }
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

    private func bundleHealthMetric(
        _ title: String,
        _ value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func bundleHealthInfoRow(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.50))
                .frame(width: 78, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func runTargetEvidenceRowIcon(
        _ kind: SemanticRecordingReviewRunTargetEvidence.Row.Kind
    ) -> String {
        switch kind {
        case .provenance:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .boundary:
            return "lock.shield"
        case .effect:
            return "checkmark.seal"
        case .selectedEvent:
            return "recordingtape"
        case .selectedFrame:
            return "photo"
        case .requestedEventIndex, .matchedEventIndex:
            return "number"
        case .target:
            return "scope"
        case .evidence:
            return "doc.text.magnifyingglass"
        case .summary:
            return "text.alignleft"
        }
    }

    private func artifactAvailabilityCounts(
        _ state: SemanticRecordingReviewState
    ) -> (total: Int, available: Int, missing: Int) {
        let total = state.artifactStatuses.count
        let available = state.artifactStatuses.values.filter(\.exists).count
        return (total, available, max(0, total - available))
    }

    private func bundleHealthDetail(_ state: SemanticRecordingReviewState) -> String {
        if state.validationIssues.isEmpty {
            return NSLocalizedString(
                "Manifest references validate. Review edits still require Draft Preview before import.",
                comment: ""
            )
        }
        return NSLocalizedString(
            "Review can still inspect available evidence, but fix bundle references before treating suggestions as product-ready.",
            comment: ""
        )
    }

    private func validationIssueLabel(_ issue: SemanticRecordingBundleIssue) -> String {
        String(describing: issue)
            .replacingOccurrences(of: "SemanticRecordingBundleIssue.", with: "")
    }

    private func suppressionDetail(
        _ suppression: SemanticRecordingReviewProjection.SuppressionRow
    ) -> String {
        var parts: [String] = []
        if let recordingTime = suppression.recordingTime {
            parts.append(timeLabel(recordingTime))
        }
        if let frameID = suppression.frameID {
            parts.append("frame \(shortID(frameID))")
        }
        if suppression.count > 1 {
            parts.append("\(suppression.count)x")
        }
        if let detail = suppression.detail {
            parts.append(detail)
        }
        return parts.isEmpty
            ? NSLocalizedString("Sensitive context was recorded and kept as review evidence.", comment: "")
            : parts.joined(separator: " · ")
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

    private func comparisonArtifactStrip(
        _ comparison: SemanticRecordingReviewProjection.ComparisonRow
    ) -> some View {
        VStack(spacing: 8) {
            comparisonArtifactTile(
                title: NSLocalizedString("Source", comment: ""),
                path: comparison.sourceArtifactPath,
                systemImage: "record.circle"
            )
            comparisonArtifactTile(
                title: NSLocalizedString("Runtime", comment: ""),
                path: comparison.runtimeArtifactPath,
                systemImage: "play.circle"
            )
            comparisonArtifactTile(
                title: NSLocalizedString("Diff", comment: ""),
                path: comparison.diffArtifactPath,
                systemImage: "square.split.2x1"
            )
        }
    }

    private func comparisonArtifactTile(
        title: String,
        path: String?,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.48))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.18))
                if let image = artifactImage(path: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: comparisonArtifactPlaceholderImage(path: path))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
            }
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )

            Text(comparisonArtifactStatus(path: path))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(comparisonArtifactStatusTint(path: path))
                .lineLimit(1)

            Text(path.map(compactPath) ?? NSLocalizedString("No artifact ref", comment: ""))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)

            if let detail = comparisonArtifactStatusDetail(path: path) {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(comparisonArtifactStatusTint(path: path).opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func artifactAvailabilityLine(path: String?) -> some View {
        if path != nil || reviewState != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: comparisonArtifactPlaceholderImage(path: path))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(comparisonArtifactStatusTint(path: path))
                Text(comparisonArtifactStatus(path: path))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(comparisonArtifactStatusTint(path: path))
                    .lineLimit(1)
                Text(path.map(compactPath) ?? NSLocalizedString("No artifact ref", comment: ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .lineLimit(1)
                if let detail = comparisonArtifactStatusDetail(path: path) {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(comparisonArtifactStatusTint(path: path).opacity(0.20), lineWidth: 1)
            )
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
                selectedCandidateID = candidate?.id
                draftPatchResult = nil
                draftPatchSourceSuggestionID = nil
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
        draftPatchSourceSuggestionID = nil
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
        draftPatchSourceSuggestionID = nil
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func selectFrame(_ frame: SemanticRecordingReviewProjection.FrameStripItem) {
        selectedFrameID = frame.id
        selectedCandidateID = nil
        regionSelection = nil
        draftPatchResult = nil
        draftPatchSourceSuggestionID = nil
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

    private func clearSelectedRegion() {
        regionSelection = nil
        draftPatchResult = nil
        draftPatchSourceSuggestionID = nil
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
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
            draftPreviewActionPresentations = []
            draftPatchSourceSuggestionID = nil
            draftPatchErrorMessage = ""
            patchSaveMessage = ""
        } catch {
            draftPatchResult = nil
            draftPreviewActionPresentations = []
            draftPatchSourceSuggestionID = nil
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func createRepeatUntilDraftPatch(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) {
        guard let bundle else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString("Open a live bundle before creating a Repeat-Until loop.", comment: "")
            return
        }

        let bodyResolution = SemanticRecordingReviewRepeatUntilBodyResolver.resolve(
            recordingID: bundle.id,
            macros: macros
        )
        guard bodyResolution.isResolved else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString(bodyResolution.message, comment: "")
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
                    repeatUntil: SemanticRecordingReviewRepeatUntilDraft(
                        bodyTasks: bodyResolution.bodyTasks,
                        onFailure: AutomationWorkflowDraftLoopFailurePolicy.requireManualApproval
                    ),
                    pixelColorHex: pixelColorHex(for: candidate)
                )
            )
            draftPreviewActionPresentations = []
            draftPatchSourceSuggestionID = nil
            draftPatchErrorMessage = ""
            patchSaveMessage = ""
        } catch {
            draftPatchResult = nil
            draftPreviewActionPresentations = []
            draftPatchSourceSuggestionID = nil
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
        guard let match = SemanticRecordingReviewSuggestionPatchResolver.makeRequest(
            suggestion: suggestion,
            bundle: bundle,
            regionSelection: regionSelection
        ) else {
            draftPatchResult = nil
            draftPatchErrorMessage = NSLocalizedString("No patchable evidence was found for this suggestion.", comment: "")
            return
        }

        selectedEventID = match.eventID
        selectedFrameID = match.frameID
        selectedCandidateID = match.candidate.id
        var request = match.request
        request.pixelColorHex = pixelColorHex(for: match.candidate)
        do {
            draftPatchResult = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
                bundle: bundle,
                request: request
            )
            draftPreviewActionPresentations = []
            draftPatchErrorMessage = ""
            patchSaveMessage = ""
            draftPatchSourceSuggestionID = suggestion.id
            suggestionReviewDecisions[suggestion.id] = .accepted
        } catch {
            draftPatchResult = nil
            draftPreviewActionPresentations = []
            draftPatchSourceSuggestionID = nil
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func rejectSuggestion(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) {
        suggestionReviewDecisions[suggestion.id] = .rejected
        if draftPatchSourceSuggestionID == suggestion.id {
            draftPatchResult = nil
            draftPatchSourceSuggestionID = nil
        }
        draftPatchErrorMessage = ""
        patchSaveMessage = ""
    }

    private func clearSuggestionDecision(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) {
        suggestionReviewDecisions.removeValue(forKey: suggestion.id)
        if draftPatchSourceSuggestionID == suggestion.id {
            draftPatchResult = nil
            draftPatchSourceSuggestionID = nil
        }
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
                    draftPatchSourceSuggestionID = nil
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
            let previewResult = try SemanticRecordingReviewPresenter.previewResult(
                applying: result,
                to: workflow,
                macros: macros,
                sourceName: "Macro Review \(shortID(projection.recordingID))",
                sourceDirectory: reviewState?.bundleDirectory
            )
            draftPreviewState = previewResult.previewState
            draftPreviewActionPresentations = [
                SemanticRecordingReviewActionPresentation(previewResult.previewAction),
                SemanticRecordingReviewActionPresentation(previewResult.importAction)
            ]
            draftPatchErrorMessage = ""
        } catch {
            draftPreviewState = nil
            draftPreviewActionPresentations = []
            draftPatchErrorMessage = String(describing: error)
        }
    }

    private func patchDetail(_ result: SemanticRecordingReviewDraftPatchResult) -> String {
        var parts = [
            result.createsRepeatUntilLoop
                ? "addRepeatUntil"
                : result.appliesToExistingTask ? "setCondition" : "addTask"
        ]
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

    private func regionSelectionDetail(
        _ selection: SemanticRecordingFrameRegionSelection
    ) -> String {
        let rect = selection.bounds.rect
        let bounds = String(
            format: "%.0f, %.0f  %.0fx%.0f %@",
            rect.x,
            rect.y,
            rect.width,
            rect.height,
            selection.bounds.coordinateSpace.rawValue
        )
        var parts = [
            bounds,
            "frame \(shortID(selection.frameID))"
        ]
        if let surfaceID = selection.surfaceID {
            parts.append("surface \(surfaceID)")
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

    private func comparisonArtifactStatus(path: String?) -> String {
        guard let path else {
            return NSLocalizedString("No ref", comment: "")
        }
        guard let reviewState else {
            return NSLocalizedString("Safe ref", comment: "")
        }
        guard let status = reviewState.artifactStatus(for: path) else {
            return NSLocalizedString("Untracked", comment: "")
        }
        return status.exists
            ? NSLocalizedString("Available", comment: "")
            : NSLocalizedString("Missing file", comment: "")
    }

    private func comparisonArtifactStatusDetail(path: String?) -> String? {
        guard path != nil else {
            return NSLocalizedString("No artifact reference was recorded for this evidence slot.", comment: "")
        }
        guard let reviewState else {
            return NSLocalizedString("Open a stored or live bundle to verify file availability.", comment: "")
        }
        guard let status = reviewState.artifactStatus(for: path) else {
            return NSLocalizedString("This ref is not in the loaded bundle artifact index.", comment: "")
        }
        return status.exists
            ? NSLocalizedString("Open/Reveal is available from this bundle.", comment: "")
            : NSLocalizedString("Open/Reveal is unavailable; the file may have been pruned, not written yet, or omitted by sidecars.", comment: "")
    }

    private func comparisonArtifactStatusTint(path: String?) -> Color {
        guard let path else {
            return Color.white.opacity(0.30)
        }
        guard let reviewState,
              let status = reviewState.artifactStatus(for: path) else {
            return Color.white.opacity(0.42)
        }
        return status.exists
            ? Color(red: 0.48, green: 0.76, blue: 0.52)
            : Color(red: 1.00, green: 0.72, blue: 0.30)
    }

    private func comparisonArtifactPlaceholderImage(path: String?) -> String {
        guard let path else {
            return "minus.circle"
        }
        guard let reviewState,
              let status = reviewState.artifactStatus(for: path) else {
            return "link"
        }
        return status.exists ? "photo" : "exclamationmark.triangle"
    }

    private func compactPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 2 else {
            return path
        }
        return parts.suffix(2).joined(separator: "/")
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

    private func suggestionDecisionEvidenceLabel(
        _ evidence: SemanticRecordingReviewProjection.EvidenceRow
    ) -> String {
        var parts: [String] = []
        if let frameID = evidence.frameID {
            parts.append("frame \(shortID(frameID))")
        }
        if let artifactPath = evidence.artifactPath {
            parts.append(compactPath(artifactPath))
        } else if let observationID = evidence.observationIDs.first {
            parts.append("obs \(shortID(observationID))")
        }
        if let summary = evidence.summary {
            parts.append(summary)
        }
        return parts.isEmpty ? NSLocalizedString("Evidence refs kept with this review decision.", comment: "") : parts.joined(separator: " · ")
    }

    private func reviewActionEvidenceLabel(
        _ evidence: SemanticRecordingReviewActionSemantics.EvidenceAlignment
    ) -> String {
        var parts: [String] = []
        if let suggestionID = evidence.suggestionID {
            parts.append("suggestion \(shortID(suggestionID))")
        }
        if let frameID = evidence.frameID {
            parts.append("frame \(shortID(frameID))")
        }
        if let artifactPath = evidence.artifactPath {
            parts.append(compactPath(artifactPath))
        } else if let observationID = evidence.observationIDs.first {
            parts.append("obs \(shortID(observationID))")
        }
        return parts.isEmpty
            ? NSLocalizedString("No evidence ref", comment: "")
            : parts.joined(separator: " · ")
    }

    private func reviewActionSystemImage(
        _ semantics: SemanticRecordingReviewActionSemantics
    ) -> String {
        reviewActionSystemImage(semantics.actionName)
    }

    private func reviewActionSystemImage(
        _ actionName: SemanticRecordingReviewActionSemantics.ActionName
    ) -> String {
        switch actionName {
        case .acceptSuggestion:
            return "checkmark.circle"
        case .rejectSuggestion:
            return "xmark.circle"
        case .clearDecision:
            return "arrow.uturn.backward.circle"
        case .draftCandidate, .draftSelection:
            return "doc.badge.gearshape"
        case .materializeAsset:
            return "archivebox"
        case .previewDraft:
            return "doc.text.magnifyingglass"
        case .importDraft:
            return "square.and.arrow.down"
        }
    }

    private func reviewActionTint(
        _ semantics: SemanticRecordingReviewActionSemantics
    ) -> Color {
        reviewActionTint(semantics.actionName)
    }

    private func reviewActionTint(
        _ actionName: SemanticRecordingReviewActionSemantics.ActionName
    ) -> Color {
        switch actionName {
        case .acceptSuggestion, .importDraft:
            return Color(red: 0.48, green: 0.76, blue: 0.52)
        case .rejectSuggestion:
            return Color(red: 1.00, green: 0.50, blue: 0.58)
        case .clearDecision:
            return Color.white.opacity(0.58)
        case .draftCandidate, .draftSelection:
            return Color(red: 0.34, green: 0.72, blue: 0.95)
        case .materializeAsset:
            return Color(red: 0.54, green: 0.72, blue: 0.98)
        case .previewDraft:
            return Color(red: 1.00, green: 0.72, blue: 0.30)
        }
    }

    private func reviewActionBoundaryValue(
        _ presentation: SemanticRecordingReviewActionPresentation
    ) -> String {
        presentation.rows.first { $0.kind == .mutationBoundary }?.value ?? ""
    }

    private func mutationBoundaryLabel(
        _ boundary: SemanticRecordingReviewActionSemantics.MutationBoundary
    ) -> String {
        switch boundary {
        case .reviewLocal:
            return NSLocalizedString("Review local", comment: "")
        case .packageAssetOnly:
            return NSLocalizedString("Package asset only", comment: "")
        case .draftPatchOnly:
            return NSLocalizedString("Draft patch only", comment: "")
        case .draftPreviewRequired:
            return NSLocalizedString("Draft Preview required", comment: "")
        case .confirmedImport:
            return NSLocalizedString("Confirmed import", comment: "")
        }
    }

    private func acceptedSuggestionPatchExplanation(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> String {
        guard draftPatchSourceSuggestionID == suggestion.id,
              let draftPatchResult else {
            return NSLocalizedString("Patch can be regenerated from the cited evidence.", comment: "")
        }

        let operation = draftPatchResult.appliesToExistingTask ? "setCondition" : "addTask"
        return "\(operation) \(draftPatchResult.condition.type) · \(draftPatchResult.patch.ops.count) ops · Draft Preview import required"
    }
}

private enum SuggestionReviewDecision {
    case accepted
    case rejected

    func actionSemantics(
        for suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> SemanticRecordingReviewActionSemantics {
        switch self {
        case .accepted:
            return .acceptSuggestion(suggestion)
        case .rejected:
            return .rejectSuggestion(suggestion)
        }
    }

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

    var detail: String {
        switch self {
        case .accepted:
            return NSLocalizedString("Patch staged", comment: "")
        case .rejected:
            return NSLocalizedString("No workflow change", comment: "")
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

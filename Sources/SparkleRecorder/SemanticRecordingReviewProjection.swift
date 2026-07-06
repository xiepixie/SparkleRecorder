import Foundation

public struct SemanticRecordingReviewRunTarget: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case failedRecordedEventIndex(Int)
        case nearestRecordedEventIndex(requested: Int, matched: Int)
        case conditionCandidate
        case firstRecordedEvent
        case defaultTimeline
    }

    public var selectedEventID: UUID?
    public var selectedFrameID: UUID?
    public var reason: Reason

    public init(
        selectedEventID: UUID?,
        selectedFrameID: UUID?,
        reason: Reason
    ) {
        self.selectedEventID = selectedEventID
        self.selectedFrameID = selectedFrameID
        self.reason = reason
    }

    public static func make(
        run: AutomationTaskRun,
        bundle: SemanticRecordingBundle
    ) -> SemanticRecordingReviewRunTarget {
        let sortedEvents = bundle.timelineEvents.sorted(by: timelineSort)
        let sortedFrames = bundle.frames.sorted(by: frameSort)

        if let failedEventIndex = run.failedEventIndex {
            if let exactEvent = sortedEvents.first(where: { $0.recordedEventIndex == failedEventIndex }) {
                return SemanticRecordingReviewRunTarget(
                    selectedEventID: exactEvent.id,
                    selectedFrameID: frameID(for: exactEvent, bundle: bundle, sortedFrames: sortedFrames),
                    reason: .failedRecordedEventIndex(failedEventIndex)
                )
            }

            if let nearest = nearestRecordedEvent(
                to: failedEventIndex,
                in: sortedEvents
            ), let matchedIndex = nearest.recordedEventIndex {
                return SemanticRecordingReviewRunTarget(
                    selectedEventID: nearest.id,
                    selectedFrameID: frameID(for: nearest, bundle: bundle, sortedFrames: sortedFrames),
                    reason: .nearestRecordedEventIndex(
                        requested: failedEventIndex,
                        matched: matchedIndex
                    )
                )
            }
        }

        if run.prefersConditionReviewTarget,
           let conditionEvent = bundle.semanticEvents
            .sorted(by: semanticEventSort)
            .first(where: { $0.kind == .conditionCandidate || $0.kind == .wait }),
           let timelineEventID = conditionEvent.timelineEventID,
           sortedEvents.contains(where: { $0.id == timelineEventID }) {
            return SemanticRecordingReviewRunTarget(
                selectedEventID: timelineEventID,
                selectedFrameID: conditionEvent.frameID ?? conditionEvent.evidenceFrameIDs.first,
                reason: .conditionCandidate
            )
        }

        if let recordedEvent = sortedEvents.first(where: { $0.kind == .recordedEvent }) {
            return SemanticRecordingReviewRunTarget(
                selectedEventID: recordedEvent.id,
                selectedFrameID: frameID(for: recordedEvent, bundle: bundle, sortedFrames: sortedFrames),
                reason: .firstRecordedEvent
            )
        }

        let fallbackEvent = sortedEvents.first
        return SemanticRecordingReviewRunTarget(
            selectedEventID: fallbackEvent?.id,
            selectedFrameID: fallbackEvent
                .flatMap { frameID(for: $0, bundle: bundle, sortedFrames: sortedFrames) }
                ?? sortedFrames.first?.id,
            reason: .defaultTimeline
        )
    }

    private static func nearestRecordedEvent(
        to recordedEventIndex: Int,
        in events: [RecordingTimelineEvent]
    ) -> RecordingTimelineEvent? {
        events
            .filter { $0.recordedEventIndex != nil }
            .min { left, right in
                let leftDistance = abs((left.recordedEventIndex ?? recordedEventIndex) - recordedEventIndex)
                let rightDistance = abs((right.recordedEventIndex ?? recordedEventIndex) - recordedEventIndex)
                if leftDistance == rightDistance {
                    return timelineSort(left, right)
                }
                return leftDistance < rightDistance
            }
    }

    private static func frameID(
        for event: RecordingTimelineEvent,
        bundle: SemanticRecordingBundle,
        sortedFrames: [RecordingFrameReference]
    ) -> UUID? {
        event.frameID ??
            bundle.semanticEvents
                .sorted(by: semanticEventSort)
                .first { $0.timelineEventID == event.id }
                .flatMap { $0.frameID ?? $0.evidenceFrameIDs.first } ??
            nearestFrame(to: event.recordingTime, in: sortedFrames)?.id
    }

    private static func nearestFrame(
        to recordingTime: TimeInterval,
        in frames: [RecordingFrameReference]
    ) -> RecordingFrameReference? {
        frames.min { left, right in
            let leftDistance = abs(left.recordingTime - recordingTime)
            let rightDistance = abs(right.recordingTime - recordingTime)
            if leftDistance == rightDistance {
                return frameSort(left, right)
            }
            return leftDistance < rightDistance
        }
    }

    private static func timelineSort(
        _ left: RecordingTimelineEvent,
        _ right: RecordingTimelineEvent
    ) -> Bool {
        if left.recordingTime == right.recordingTime {
            return left.id.uuidString < right.id.uuidString
        }
        return left.recordingTime < right.recordingTime
    }

    private static func frameSort(
        _ left: RecordingFrameReference,
        _ right: RecordingFrameReference
    ) -> Bool {
        if left.recordingTime == right.recordingTime {
            return left.id.uuidString < right.id.uuidString
        }
        return left.recordingTime < right.recordingTime
    }

    private static func semanticEventSort(
        _ left: RecordingSemanticEvent,
        _ right: RecordingSemanticEvent
    ) -> Bool {
        if left.recordingTime == right.recordingTime {
            return left.id.uuidString < right.id.uuidString
        }
        return left.recordingTime < right.recordingTime
    }
}

private extension AutomationTaskRun {
    var failedEventIndex: Int? {
        guard case .failed(let report) = outcome else {
            return nil
        }
        return report?.failedEventIndex
    }

    var prefersConditionReviewTarget: Bool {
        switch outcome {
        case .timedOut, .conditionNotMatched:
            return true
        case .succeeded, .failed, .cancelled, .resourceConflict, .permissionDenied,
             .conditionMatched, .missingMacro, .rejected, nil:
            return false
        }
    }
}

public struct SemanticRecordingReviewProjection: Equatable, Sendable {
    public var recordingID: UUID
    public var title: String
    public var subtitle: String
    public var hasVideo: Bool
    public var summary: Summary
    public var frameStrip: [FrameStripItem]
    public var timelineRows: [TimelineRow]
    public var selectedEvent: TimelineRow?
    public var selectedFrame: SelectedFrame?
    public var suggestionRows: [SuggestionRow]
    public var suppressionRows: [SuppressionRow]

    public init(
        bundle: SemanticRecordingBundle,
        suggestions: [RecordingSuggestion] = [],
        selectedEventID: UUID? = nil,
        selectedFrameID: UUID? = nil
    ) {
        let sortedFrames = bundle.frames.sorted { left, right in
            if left.recordingTime == right.recordingTime {
                return left.id.uuidString < right.id.uuidString
            }
            return left.recordingTime < right.recordingTime
        }
        let framesByID = Dictionary(uniqueKeysWithValues: bundle.frames.map { ($0.id, $0) })
        let observationsByFrameID = Dictionary(grouping: bundle.visualObservations.compactMap { observation -> (UUID, RecordingVisualObservation)? in
            guard let frameID = observation.frameID else { return nil }
            return (frameID, observation)
        }, by: \.0).mapValues { $0.map(\.1) }
        let sourcePreviewsByFrameID = Dictionary(grouping: bundle.sourcePreviews.compactMap { source -> (UUID, RecordingSourcePreviewReference)? in
            guard let frameID = source.frameID else { return nil }
            return (frameID, source)
        }, by: \.0).mapValues { $0.map(\.1) }
        let runtimeSamplesByID = Dictionary(uniqueKeysWithValues: bundle.runtimeSamples.map { ($0.id, $0) })
        let comparisonsBySourceID = Dictionary(grouping: bundle.previewComparisons, by: \.sourcePreviewRefID)
        let semanticEventsByTimelineID = Dictionary(grouping: bundle.semanticEvents.compactMap { event -> (UUID, RecordingSemanticEvent)? in
            guard let timelineEventID = event.timelineEventID else { return nil }
            return (timelineEventID, event)
        }, by: \.0).mapValues { $0.map(\.1) }

        let provisionalTimelineRows = bundle.timelineEvents.sorted { left, right in
            if left.recordingTime == right.recordingTime {
                return left.id.uuidString < right.id.uuidString
            }
            return left.recordingTime < right.recordingTime
        }.map { event in
            let primaryFrame = event.frameID.flatMap { framesByID[$0] } ??
                Self.nearestFrame(to: event.recordingTime, in: sortedFrames)
            let beforeFrame = Self.frameBeforeOrAt(event.recordingTime, in: sortedFrames) ?? primaryFrame
            let afterFrame = Self.frameAfterOrAt(event.recordingTime, in: sortedFrames) ?? primaryFrame
            let semanticEvents = semanticEventsByTimelineID[event.id] ?? []
            let evidenceFrameIDs = Self.uniqueIDs(
                [
                    primaryFrame?.id,
                    beforeFrame?.id,
                    afterFrame?.id
                ] + bundle.frames(relatedToEventID: event.id).map(\.id) +
                    semanticEvents.flatMap(\.evidenceFrameIDs)
            )
            let observationCount = evidenceFrameIDs.reduce(0) { count, frameID in
                count + (observationsByFrameID[frameID]?.count ?? 0)
            }
            let sourcePreviewCount = evidenceFrameIDs.reduce(0) { count, frameID in
                count + (sourcePreviewsByFrameID[frameID]?.count ?? 0)
            }
            let suggestionCount = suggestions.filter { suggestion in
                suggestion.evidence.contains { evidence in
                    evidence.eventIDs.contains(event.id) ||
                        evidenceFrameIDs.contains { evidence.frameID == $0 }
                }
            }.count

            return TimelineRow(
                id: event.id,
                recordingTime: event.recordingTime,
                kind: event.kind,
                title: event.summary ?? Self.title(for: event.kind),
                surfaceID: event.surfaceID,
                primaryFrameID: primaryFrame?.id,
                beforeFrameID: beforeFrame?.id,
                afterFrameID: afterFrame?.id,
                evidenceFrameIDs: evidenceFrameIDs,
                observationCount: observationCount,
                sourcePreviewCount: sourcePreviewCount,
                suggestionCount: suggestionCount,
                semanticEventTitles: semanticEvents.map(\.title),
                isSelected: false
            )
        }

        let effectiveSelectedEventID = selectedEventID ??
            provisionalTimelineRows.first { $0.kind == .recordedEvent }?.id ??
            provisionalTimelineRows.first?.id
        let selectedTimelineRow = provisionalTimelineRows.first { $0.id == effectiveSelectedEventID }
        let effectiveSelectedFrameID = selectedFrameID ??
            selectedTimelineRow?.primaryFrameID ??
            selectedTimelineRow?.afterFrameID ??
            sortedFrames.first?.id

        self.recordingID = bundle.id
        self.title = bundle.semanticEvents.first { $0.kind == .summary }?.title ??
            bundle.captureTarget?.windowTitle ??
            bundle.captureTarget?.appName ??
            "Recording Review"
        self.subtitle = Self.subtitle(for: bundle)
        self.hasVideo = !bundle.videoSegments.isEmpty
        self.summary = Summary(
            frameCount: bundle.frames.count,
            eventCount: bundle.timelineEvents.count,
            observationCount: bundle.visualObservations.count,
            sourcePreviewCount: bundle.sourcePreviews.count,
            runtimeSampleCount: bundle.runtimeSamples.count,
            comparisonCount: bundle.previewComparisons.count,
            suggestionCount: suggestions.count,
            suppressionCount: bundle.suppressions.count
        )
        self.timelineRows = provisionalTimelineRows.map { row in
            var row = row
            row.isSelected = row.id == effectiveSelectedEventID
            return row
        }
        self.frameStrip = sortedFrames.map { frame in
            FrameStripItem(
                id: frame.id,
                recordingTime: frame.recordingTime,
                source: frame.source,
                imageRefPath: frame.imageRef.path,
                surfaceID: frame.surfaceID,
                relatedEventIDs: frame.relatedEventIDs,
                observationCount: observationsByFrameID[frame.id]?.count ?? 0,
                sourcePreviewCount: sourcePreviewsByFrameID[frame.id]?.count ?? 0,
                isSelected: frame.id == effectiveSelectedFrameID
            )
        }
        self.selectedEvent = self.timelineRows.first { $0.id == effectiveSelectedEventID }
        if let effectiveSelectedFrameID,
           let frame = framesByID[effectiveSelectedFrameID] {
            let frameObservations = (observationsByFrameID[effectiveSelectedFrameID] ?? [])
                .sorted { Self.sortKey(for: $0) < Self.sortKey(for: $1) }
            let frameSourcePreviews = (sourcePreviewsByFrameID[effectiveSelectedFrameID] ?? [])
                .sorted { Self.sortKey(for: $0) < Self.sortKey(for: $1) }
            let comparisonRows = frameSourcePreviews.flatMap { source in
                (comparisonsBySourceID[source.id] ?? []).compactMap { comparison -> ComparisonRow? in
                    guard let runtimeSample = runtimeSamplesByID[comparison.runtimeSampleRefID] else {
                        return nil
                    }
                    return ComparisonRow(
                        id: comparison.id,
                        sourcePreviewRefID: source.id,
                        sourceLabel: source.label ?? Self.title(for: source.kind),
                        sourceArtifactPath: source.artifactRef?.path,
                        runtimeSampleRefID: runtimeSample.id,
                        runtimeArtifactPath: runtimeSample.artifactRef.path,
                        diffArtifactPath: comparison.diffArtifactRef?.path,
                        outcome: comparison.outcome,
                        score: comparison.score,
                        threshold: comparison.threshold,
                        reason: comparison.reason,
                        matcherLabel: "\(comparison.matcher.kind) \(comparison.matcher.version)"
                    )
                }
            }
            self.selectedFrame = SelectedFrame(
                id: frame.id,
                recordingTime: frame.recordingTime,
                source: frame.source,
                imageRefPath: frame.imageRef.path,
                imageSize: frame.imageSize,
                surfaceID: frame.surfaceID,
                relatedEventIDs: frame.relatedEventIDs,
                overlays: frameObservations.map(Self.overlayRow),
                sourcePreviews: frameSourcePreviews.map(Self.sourcePreviewRow),
                comparisonRows: comparisonRows,
                conditionCandidates: Self.conditionCandidates(
                    frame: frame,
                    sourcePreviews: frameSourcePreviews,
                    observations: frameObservations
                )
            )
        } else {
            self.selectedFrame = nil
        }
        self.suggestionRows = suggestions.map { suggestion in
            SuggestionRow(
                id: suggestion.id,
                kind: suggestion.kind,
                title: suggestion.title,
                summary: suggestion.summary,
                confidence: suggestion.confidence,
                risk: suggestion.risk,
                evidence: suggestion.evidence.map(Self.evidenceRow),
                mutationPolicy: "Review required; no workflow mutation until accepted."
            )
        }
        self.suppressionRows = bundle.suppressions.map { suppression in
            SuppressionRow(
                id: suppression.id,
                reason: suppression.reason,
                recordingTime: suppression.recordingTime,
                frameID: suppression.frameID,
                eventID: suppression.eventID,
                detail: suppression.detail,
                count: suppression.count
            )
        }
    }

    public struct Summary: Equatable, Sendable {
        public var frameCount: Int
        public var eventCount: Int
        public var observationCount: Int
        public var sourcePreviewCount: Int
        public var runtimeSampleCount: Int
        public var comparisonCount: Int
        public var suggestionCount: Int
        public var suppressionCount: Int
    }

    public struct FrameStripItem: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var recordingTime: TimeInterval
        public var source: RecordingFrameCaptureSource
        public var imageRefPath: String
        public var surfaceID: String?
        public var relatedEventIDs: [UUID]
        public var observationCount: Int
        public var sourcePreviewCount: Int
        public var isSelected: Bool
    }

    public struct TimelineRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var recordingTime: TimeInterval
        public var kind: RecordingTimelineEventKind
        public var title: String
        public var surfaceID: String?
        public var primaryFrameID: UUID?
        public var beforeFrameID: UUID?
        public var afterFrameID: UUID?
        public var evidenceFrameIDs: [UUID]
        public var observationCount: Int
        public var sourcePreviewCount: Int
        public var suggestionCount: Int
        public var semanticEventTitles: [String]
        public var isSelected: Bool
    }

    public struct SelectedFrame: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var recordingTime: TimeInterval
        public var source: RecordingFrameCaptureSource
        public var imageRefPath: String
        public var imageSize: RecordingImageSize?
        public var surfaceID: String?
        public var relatedEventIDs: [UUID]
        public var overlays: [OverlayRow]
        public var sourcePreviews: [SourcePreviewRow]
        public var comparisonRows: [ComparisonRow]
        public var conditionCandidates: [ConditionCandidateRow]
    }

    public struct OverlayRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var kind: RecordingVisualObservationKind
        public var title: String
        public var detail: String?
        public var bounds: RecordingBounds?
        public var confidence: Double?
        public var score: Double?
        public var provider: String
        public var artifactPath: String?
    }

    public struct SourcePreviewRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var kind: RecordingVisualReferenceKind
        public var title: String
        public var artifactPath: String?
        public var bounds: RecordingBounds?
        public var imageSize: RecordingImageSize?
        public var contentDigest: String?
    }

    public struct ComparisonRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var sourcePreviewRefID: UUID
        public var sourceLabel: String
        public var sourceArtifactPath: String?
        public var runtimeSampleRefID: UUID
        public var runtimeArtifactPath: String
        public var diffArtifactPath: String?
        public var outcome: RecordingPreviewComparisonOutcome
        public var score: Double?
        public var threshold: Double?
        public var reason: String?
        public var matcherLabel: String
    }

    public enum ConditionCandidateKind: String, Equatable, Sendable {
        case ocrWait
        case imageAppeared
        case imageDisappeared
        case regionChanged
        case pixelMatched
    }

    public struct ConditionCandidateRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: ConditionCandidateKind
        public var title: String
        public var summary: String
        public var sourceFrameID: UUID
        public var sourcePreviewRefID: UUID?
        public var observationID: UUID?
        public var bounds: RecordingBounds?
        public var artifactPath: String?
    }

    public struct SuggestionRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var kind: RecordingSuggestionKind
        public var title: String
        public var summary: String
        public var confidence: Double
        public var risk: String?
        public var evidence: [EvidenceRow]
        public var mutationPolicy: String
    }

    public struct EvidenceRow: Equatable, Sendable {
        public var frameID: UUID?
        public var eventIDs: [UUID]
        public var observationIDs: [UUID]
        public var artifactPath: String?
        public var bounds: RecordingBounds?
        public var summary: String?
    }

    public struct SuppressionRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var reason: RecordingSuppressionReason
        public var recordingTime: TimeInterval?
        public var frameID: UUID?
        public var eventID: UUID?
        public var detail: String?
        public var count: Int
    }

    private static func overlayRow(_ observation: RecordingVisualObservation) -> OverlayRow {
        OverlayRow(
            id: observation.id,
            kind: observation.kind,
            title: observation.text ?? title(for: observation.kind),
            detail: observation.labels.joined(separator: ", "),
            bounds: observation.bounds,
            confidence: observation.confidence,
            score: observation.score,
            provider: observation.provider,
            artifactPath: observation.artifactRef?.path
        )
    }

    private static func sourcePreviewRow(_ source: RecordingSourcePreviewReference) -> SourcePreviewRow {
        SourcePreviewRow(
            id: source.id,
            kind: source.kind,
            title: source.label ?? title(for: source.kind),
            artifactPath: source.artifactRef?.path,
            bounds: source.bounds,
            imageSize: source.imageSize,
            contentDigest: source.contentDigest?.value
        )
    }

    private static func evidenceRow(_ evidence: RecordingEvidenceReference) -> EvidenceRow {
        EvidenceRow(
            frameID: evidence.frameID,
            eventIDs: evidence.eventIDs,
            observationIDs: evidence.observationIDs,
            artifactPath: evidence.artifactRef?.path,
            bounds: evidence.bounds,
            summary: evidence.summary
        )
    }

    private static func conditionCandidates(
        frame: RecordingFrameReference,
        sourcePreviews: [RecordingSourcePreviewReference],
        observations: [RecordingVisualObservation]
    ) -> [ConditionCandidateRow] {
        var rows: [ConditionCandidateRow] = []
        for source in sourcePreviews {
            switch source.kind {
            case .ocrRegion:
                rows.append(ConditionCandidateRow(
                    id: "\(source.id.uuidString)-ocrWait",
                    kind: .ocrWait,
                    title: "Create OCR wait",
                    summary: "Use this recorded region as a reviewed text wait condition.",
                    sourceFrameID: frame.id,
                    sourcePreviewRefID: source.id,
                    observationID: nil,
                    bounds: source.bounds,
                    artifactPath: source.artifactRef?.path
                ))
            case .imageTemplate:
                rows.append(ConditionCandidateRow(
                    id: "\(source.id.uuidString)-imageAppeared",
                    kind: .imageAppeared,
                    title: "Wait for image",
                    summary: "Use this crop as an image-appeared condition candidate.",
                    sourceFrameID: frame.id,
                    sourcePreviewRefID: source.id,
                    observationID: nil,
                    bounds: source.bounds,
                    artifactPath: source.artifactRef?.path
                ))
                rows.append(ConditionCandidateRow(
                    id: "\(source.id.uuidString)-imageDisappeared",
                    kind: .imageDisappeared,
                    title: "Wait for image to disappear",
                    summary: "Use this crop as an image-disappeared condition candidate.",
                    sourceFrameID: frame.id,
                    sourcePreviewRefID: source.id,
                    observationID: nil,
                    bounds: source.bounds,
                    artifactPath: source.artifactRef?.path
                ))
            case .regionBaseline:
                rows.append(ConditionCandidateRow(
                    id: "\(source.id.uuidString)-regionChanged",
                    kind: .regionChanged,
                    title: "Wait for region change",
                    summary: "Use this region as the baseline for a reviewed change condition.",
                    sourceFrameID: frame.id,
                    sourcePreviewRefID: source.id,
                    observationID: nil,
                    bounds: source.bounds,
                    artifactPath: source.artifactRef?.path
                ))
            case .pixelSample:
                rows.append(ConditionCandidateRow(
                    id: "\(source.id.uuidString)-pixelMatched",
                    kind: .pixelMatched,
                    title: "Wait for pixel color",
                    summary: "Use this sampled point as a pixel condition candidate.",
                    sourceFrameID: frame.id,
                    sourcePreviewRefID: source.id,
                    observationID: nil,
                    bounds: source.bounds,
                    artifactPath: source.artifactRef?.path
                ))
            }
        }
        for observation in observations where observation.kind == .pixelSample {
            rows.append(ConditionCandidateRow(
                id: "\(observation.id.uuidString)-pixelMatched",
                kind: .pixelMatched,
                title: "Wait for pixel color",
                summary: "Use this observed pixel sample as a reviewed condition candidate.",
                sourceFrameID: frame.id,
                sourcePreviewRefID: observation.sourcePreviewRefID,
                observationID: observation.id,
                bounds: observation.bounds,
                artifactPath: observation.artifactRef?.path
            ))
        }
        return rows
    }

    private static func nearestFrame(
        to recordingTime: TimeInterval,
        in frames: [RecordingFrameReference]
    ) -> RecordingFrameReference? {
        frames.min { left, right in
            abs(left.recordingTime - recordingTime) < abs(right.recordingTime - recordingTime)
        }
    }

    private static func frameBeforeOrAt(
        _ recordingTime: TimeInterval,
        in frames: [RecordingFrameReference]
    ) -> RecordingFrameReference? {
        frames.last { $0.recordingTime <= recordingTime }
    }

    private static func frameAfterOrAt(
        _ recordingTime: TimeInterval,
        in frames: [RecordingFrameReference]
    ) -> RecordingFrameReference? {
        frames.first { $0.recordingTime >= recordingTime }
    }

    private static func uniqueIDs(_ ids: [UUID?]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in ids.compactMap({ $0 }) where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private static func subtitle(for bundle: SemanticRecordingBundle) -> String {
        let target = bundle.captureTarget?.windowTitle ??
            bundle.captureTarget?.appName ??
            bundle.captureTarget?.surfaceID ??
            "Unknown surface"
        let mode = bundle.capturePolicy.mode.rawValue
        return "\(target) - \(mode)"
    }

    private static func title(for kind: RecordingTimelineEventKind) -> String {
        switch kind {
        case .rawInput:
            return "Raw input"
        case .recordedEvent:
            return "Recorded event"
        case .focusChange:
            return "Focus change"
        case .windowSnapshot:
            return "Window snapshot"
        case .keyframe:
            return "Keyframe"
        case .visualObservation:
            return "Visual observation"
        case .waitStart:
            return "Wait started"
        case .waitEnd:
            return "Wait ended"
        case .userMarker:
            return "User marker"
        case .suppression:
            return "Suppression"
        case .note:
            return "Note"
        }
    }

    private static func title(for kind: RecordingVisualObservationKind) -> String {
        switch kind {
        case .ocrText:
            return "OCR text"
        case .axElement:
            return "AX element"
        case .windowSnapshot:
            return "Window snapshot"
        case .pixelSample:
            return "Pixel sample"
        case .imageTemplateCandidate:
            return "Image template candidate"
        case .regionBaseline:
            return "Region baseline"
        case .regionDiff:
            return "Region diff"
        case .patternCandidate:
            return "Pattern candidate"
        }
    }

    private static func title(for kind: RecordingVisualReferenceKind) -> String {
        switch kind {
        case .ocrRegion:
            return "OCR region"
        case .imageTemplate:
            return "Image template"
        case .regionBaseline:
            return "Region baseline"
        case .pixelSample:
            return "Pixel sample"
        }
    }

    private static func sortKey(for observation: RecordingVisualObservation) -> String {
        "\(observation.recordingTime)-\(observation.kind.rawValue)-\(observation.id.uuidString)"
    }

    private static func sortKey(for source: RecordingSourcePreviewReference) -> String {
        "\(source.recordingTime ?? 0)-\(source.kind.rawValue)-\(source.id.uuidString)"
    }
}

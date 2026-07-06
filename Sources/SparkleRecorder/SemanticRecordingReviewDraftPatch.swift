import CoreGraphics
import Foundation

public enum SemanticRecordingReviewDraftPatchError: Error, Equatable, Sendable {
    case missingSourceFrame(UUID)
    case missingRegionBounds(String)
    case invalidRegionBounds(String)
    case missingConditionText(String)
    case missingArtifact(String)
    case missingPixelColor(String)
}

public struct SemanticRecordingFrameRegionSelection: Equatable, Sendable {
    public var frameID: UUID
    public var surfaceID: String?
    public var bounds: RecordingBounds
    public var imageSize: RecordingImageSize?
    public var label: String?
    public var candidateKind: SemanticRecordingReviewProjection.ConditionCandidateKind
    public var sourcePreviewRefID: UUID?
    public var observationID: UUID?
    public var artifactPath: String?

    public init(
        frameID: UUID,
        surfaceID: String? = nil,
        bounds: RecordingBounds,
        imageSize: RecordingImageSize? = nil,
        label: String? = nil,
        candidateKind: SemanticRecordingReviewProjection.ConditionCandidateKind,
        sourcePreviewRefID: UUID? = nil,
        observationID: UUID? = nil,
        artifactPath: String? = nil
    ) {
        self.frameID = frameID
        self.surfaceID = surfaceID
        self.bounds = bounds
        self.imageSize = imageSize
        self.label = label?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.candidateKind = candidateKind
        self.sourcePreviewRefID = sourcePreviewRefID
        self.observationID = observationID
        self.artifactPath = artifactPath?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
    }

    public init(
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        frame: RecordingFrameReference,
        label: String? = nil
    ) throws {
        guard let bounds = candidate.bounds ?? frame.fullFrameBounds else {
            throw SemanticRecordingReviewDraftPatchError.missingRegionBounds(candidate.id)
        }
        self.init(
            frameID: candidate.sourceFrameID,
            surfaceID: frame.surfaceID,
            bounds: bounds,
            imageSize: frame.imageSize,
            label: label ?? candidate.title,
            candidateKind: candidate.kind,
            sourcePreviewRefID: candidate.sourcePreviewRefID,
            observationID: candidate.observationID,
            artifactPath: candidate.artifactPath
        )
    }

    public func visualRegion(key: String) throws -> AutomationWorkflowDraftVisualRegion {
        let rect = bounds.rect.draftRectValue
        guard rect.width > 0, rect.height > 0 else {
            throw SemanticRecordingReviewDraftPatchError.invalidRegionBounds(key)
        }
        return AutomationWorkflowDraftVisualRegion(
            key: key,
            label: label,
            bounds: rect,
            space: bounds.coordinateSpace.draftSearchRegionSpace
        )
    }
}

public struct SemanticRecordingReviewDraftPatchRequest: Equatable, Sendable {
    public var candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    public var targetTaskKey: String?
    public var newTaskKey: String?
    public var taskName: String?
    public var regionSelection: SemanticRecordingFrameRegionSelection?
    public var text: String?
    public var threshold: Double?
    public var timeoutSeconds: TimeInterval
    public var pollingSeconds: TimeInterval
    public var requireVisible: Bool?
    public var pixelColorHex: String?

    public init(
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        targetTaskKey: String? = nil,
        newTaskKey: String? = nil,
        taskName: String? = nil,
        regionSelection: SemanticRecordingFrameRegionSelection? = nil,
        text: String? = nil,
        threshold: Double? = nil,
        timeoutSeconds: TimeInterval = 15,
        pollingSeconds: TimeInterval = 0.25,
        requireVisible: Bool? = nil,
        pixelColorHex: String? = nil
    ) {
        self.candidate = candidate
        self.targetTaskKey = targetTaskKey?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.newTaskKey = newTaskKey?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.taskName = taskName?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.regionSelection = regionSelection
        self.text = text?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.threshold = threshold.map { min(max($0, 0), 1) }
        self.timeoutSeconds = max(0, timeoutSeconds)
        self.pollingSeconds = max(0, pollingSeconds)
        self.requireVisible = requireVisible
        self.pixelColorHex = pixelColorHex?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
    }
}

public struct SemanticRecordingReviewDraftPatchResult: Equatable, Sendable {
    public var patch: AutomationWorkflowDraftPatchDocument
    public var taskKey: String
    public var condition: AutomationWorkflowDraftCondition
    public var region: AutomationWorkflowDraftVisualRegion?
    public var imageAsset: AutomationWorkflowDraftVisualImageAsset?
    public var baselineAsset: AutomationWorkflowDraftVisualImageAsset?
    public var appliesToExistingTask: Bool

    public init(
        patch: AutomationWorkflowDraftPatchDocument,
        taskKey: String,
        condition: AutomationWorkflowDraftCondition,
        region: AutomationWorkflowDraftVisualRegion? = nil,
        imageAsset: AutomationWorkflowDraftVisualImageAsset? = nil,
        baselineAsset: AutomationWorkflowDraftVisualImageAsset? = nil,
        appliesToExistingTask: Bool
    ) {
        self.patch = patch
        self.taskKey = taskKey
        self.condition = condition
        self.region = region
        self.imageAsset = imageAsset
        self.baselineAsset = baselineAsset
        self.appliesToExistingTask = appliesToExistingTask
    }
}

public enum SemanticRecordingReviewDraftPatchBuilder {
    public static func makePatch(
        bundle: SemanticRecordingBundle,
        request: SemanticRecordingReviewDraftPatchRequest
    ) throws -> SemanticRecordingReviewDraftPatchResult {
        let candidate = request.candidate
        guard let frame = bundle.frames.first(where: { $0.id == candidate.sourceFrameID }) else {
            throw SemanticRecordingReviewDraftPatchError.missingSourceFrame(candidate.sourceFrameID)
        }

        let sourcePreview = candidate.sourcePreviewRefID.flatMap { id in
            bundle.sourcePreviews.first { $0.id == id }
        }
        let observation = bestObservation(for: candidate, sourcePreview: sourcePreview, in: bundle)
        let selection = try request.regionSelection ?? SemanticRecordingFrameRegionSelection(
            candidate: candidate,
            frame: frame,
            label: displayLabel(candidate: candidate, sourcePreview: sourcePreview, observation: observation)
        )
        let keySeed = keySeed(
            bundle: bundle,
            candidate: candidate,
            sourcePreview: sourcePreview,
            observation: observation
        )
        let regionKey = "sr_\(shortID(bundle.id))_\(keySeed)_region"
        let region = try selection.visualRegion(key: regionKey)
        let taskKey = request.targetTaskKey ??
            request.newTaskKey ??
            "wait_\(keySeed)"

        let condition: AutomationWorkflowDraftCondition
        var imageAsset: AutomationWorkflowDraftVisualImageAsset?
        var baselineAsset: AutomationWorkflowDraftVisualImageAsset?

        switch candidate.kind {
        case .ocrWait:
            let text = request.text ??
                observation?.text?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch ??
                sourcePreview?.label?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
            guard let text else {
                throw SemanticRecordingReviewDraftPatchError.missingConditionText(candidate.id)
            }
            condition = AutomationWorkflowDraftCondition(
                type: "ocrText",
                text: text,
                matchMode: .contains,
                regionRef: region.key,
                requireVisible: request.requireVisible ?? true
            )

        case .imageAppeared, .imageDisappeared:
            let artifactPath = artifactPath(candidate: candidate, sourcePreview: sourcePreview, observation: observation)
            guard let artifactPath else {
                throw SemanticRecordingReviewDraftPatchError.missingArtifact(candidate.id)
            }
            let imageKey = "sr_\(shortID(bundle.id))_\(keySeed)_template"
            imageAsset = AutomationWorkflowDraftVisualImageAsset(
                key: imageKey,
                label: sourcePreview?.label ?? observation?.labels.first ?? candidate.title,
                path: artifactPath,
                sha256: sourcePreview?.contentDigest?.value
            )
            condition = AutomationWorkflowDraftCondition(
                type: candidate.kind.rawValue,
                regionRef: region.key,
                requireVisible: request.requireVisible ?? (candidate.kind == .imageAppeared),
                imageRef: imageKey,
                threshold: request.threshold ?? observation?.score ?? 0.90
            )

        case .regionChanged:
            let artifactPath = artifactPath(candidate: candidate, sourcePreview: sourcePreview, observation: observation)
            guard let artifactPath else {
                throw SemanticRecordingReviewDraftPatchError.missingArtifact(candidate.id)
            }
            let baselineKey = "sr_\(shortID(bundle.id))_\(keySeed)_baseline"
            baselineAsset = AutomationWorkflowDraftVisualImageAsset(
                key: baselineKey,
                label: sourcePreview?.label ?? observation?.labels.first ?? candidate.title,
                path: artifactPath,
                sha256: sourcePreview?.contentDigest?.value
            )
            condition = AutomationWorkflowDraftCondition(
                type: "regionChanged",
                regionRef: region.key,
                baselineRef: baselineKey,
                threshold: request.threshold ?? observation?.score ?? 0.90
            )

        case .pixelMatched:
            let colorHex = request.pixelColorHex ??
                observation?.metadata["colorHex"]?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch ??
                observation?.metadata["color"]?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
            guard let colorHex else {
                throw SemanticRecordingReviewDraftPatchError.missingPixelColor(candidate.id)
            }
            condition = AutomationWorkflowDraftCondition(
                type: "pixelMatched",
                regionRef: region.key,
                requireVisible: request.requireVisible ?? true,
                colorHex: colorHex,
                threshold: request.threshold ?? observation?.score ?? 0.95
            )
        }

        var operations = [
            AutomationWorkflowDraftPatchOperation(
                op: "upsertVisualRegion",
                visualRegion: region
            )
        ]
        if let imageAsset {
            operations.append(AutomationWorkflowDraftPatchOperation(
                op: "upsertVisualImage",
                visualImage: imageAsset
            ))
        }
        if let baselineAsset {
            operations.append(AutomationWorkflowDraftPatchOperation(
                op: "upsertVisualBaseline",
                visualBaseline: baselineAsset
            ))
        }

        let appliesToExistingTask = request.targetTaskKey != nil
        operations.append(taskOperation(
            taskKey: taskKey,
            taskName: request.taskName ?? taskName(for: condition, candidate: candidate),
            condition: condition,
            request: request,
            appliesToExistingTask: appliesToExistingTask
        ))

        return SemanticRecordingReviewDraftPatchResult(
            patch: AutomationWorkflowDraftPatchDocument(ops: operations),
            taskKey: taskKey,
            condition: condition,
            region: region,
            imageAsset: imageAsset,
            baselineAsset: baselineAsset,
            appliesToExistingTask: appliesToExistingTask
        )
    }

    private static func taskOperation(
        taskKey: String,
        taskName: String,
        condition: AutomationWorkflowDraftCondition,
        request: SemanticRecordingReviewDraftPatchRequest,
        appliesToExistingTask: Bool
    ) -> AutomationWorkflowDraftPatchOperation {
        if appliesToExistingTask {
            return AutomationWorkflowDraftPatchOperation(
                op: "setCondition",
                key: taskKey,
                condition: condition,
                timeoutSeconds: request.timeoutSeconds,
                pollingSeconds: request.pollingSeconds
            )
        }

        return AutomationWorkflowDraftPatchOperation(
            op: "addTask",
            key: taskKey,
            task: AutomationWorkflowDraftTask(
                key: taskKey,
                type: "condition",
                name: taskName,
                condition: condition,
                timeoutSeconds: request.timeoutSeconds,
                pollingSeconds: request.pollingSeconds
            )
        )
    }

    private static func bestObservation(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        sourcePreview: RecordingSourcePreviewReference?,
        in bundle: SemanticRecordingBundle
    ) -> RecordingVisualObservation? {
        if let observationID = candidate.observationID,
           let observation = bundle.visualObservations.first(where: { $0.id == observationID }) {
            return observation
        }
        if let sourcePreviewID = sourcePreview?.id ?? candidate.sourcePreviewRefID {
            return bundle.visualObservations
                .filter { $0.sourcePreviewRefID == sourcePreviewID }
                .sorted { ($0.confidence ?? $0.score ?? 0) > ($1.confidence ?? $1.score ?? 0) }
                .first
        }
        return bundle.visualObservations
            .filter { $0.frameID == candidate.sourceFrameID }
            .sorted { ($0.confidence ?? $0.score ?? 0) > ($1.confidence ?? $1.score ?? 0) }
            .first
    }

    private static func artifactPath(
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        sourcePreview: RecordingSourcePreviewReference?,
        observation: RecordingVisualObservation?
    ) -> String? {
        candidate.artifactPath?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch ??
            sourcePreview?.artifactRef?.path ??
            observation?.artifactRef?.path
    }

    private static func displayLabel(
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        sourcePreview: RecordingSourcePreviewReference?,
        observation: RecordingVisualObservation?
    ) -> String {
        observation?.text?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch ??
            sourcePreview?.label?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch ??
            observation?.labels.first ??
            candidate.title
    }

    private static func keySeed(
        bundle: SemanticRecordingBundle,
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        sourcePreview: RecordingSourcePreviewReference?,
        observation: RecordingVisualObservation?
    ) -> String {
        let label = displayLabel(candidate: candidate, sourcePreview: sourcePreview, observation: observation)
        let base = safeKey(label, fallback: candidate.kind.rawValue)
        let evidenceID = candidate.sourcePreviewRefID ?? candidate.observationID ?? candidate.sourceFrameID
        return "\(base)_\(shortID(evidenceID))"
    }

    private static func taskName(
        for condition: AutomationWorkflowDraftCondition,
        candidate: SemanticRecordingReviewProjection.ConditionCandidateRow
    ) -> String {
        switch candidate.kind {
        case .ocrWait:
            if let text = condition.text, !text.isEmpty {
                return "Wait for \(text)"
            }
            return "Wait for text"
        case .imageAppeared:
            return "Wait for image"
        case .imageDisappeared:
            return "Wait for image to disappear"
        case .regionChanged:
            return "Wait for region change"
        case .pixelMatched:
            return "Wait for pixel color"
        }
    }

    private static func safeKey(_ value: String, fallback: String) -> String {
        var result = ""
        var lastWasSeparator = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("_")
                lastWasSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.suffix(8)).lowercased()
    }
}

private extension RecordingFrameReference {
    var fullFrameBounds: RecordingBounds? {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }
        return RecordingBounds(
            rect: RecordingRect(
                x: 0,
                y: 0,
                width: Double(imageSize.width),
                height: Double(imageSize.height)
            ),
            coordinateSpace: .framePixels
        )
    }
}

private extension RecordingRect {
    var draftRectValue: RectValue {
        RectValue(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

private extension RecordingCoordinateSpace {
    var draftSearchRegionSpace: AutomationOCRSearchRegionSpace {
        switch self {
        case .screenPixels, .displayPixels, .framePixels:
            return .displayAbsolute
        case .windowPixels:
            return .windowLocal
        case .contentPixels:
            return .contentLocal
        case .normalizedFrame:
            return .displayNormalized
        }
    }
}

private extension String {
    var trimmedForSemanticReviewPatch: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmptyForSemanticReviewPatch: String? {
        isEmpty ? nil : self
    }
}

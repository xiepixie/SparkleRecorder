import CoreGraphics
import CryptoKit
import Foundation

public struct SemanticRecordingReviewActionSemantics: Codable, Equatable, Sendable {
    public enum ActionName: String, Codable, Equatable, Sendable {
        case draftCandidate = "review.draftCandidate"
        case draftSelection = "review.draftSelection"
        case acceptSuggestion = "review.acceptSuggestion"
        case rejectSuggestion = "review.rejectSuggestion"
        case clearDecision = "review.clearDecision"
        case previewDraft = "review.previewDraft"
        case importDraft = "review.importDraft"
    }

    public enum MutationBoundary: String, Codable, Equatable, Sendable {
        case reviewLocal = "reviewLocal"
        case draftPatchOnly = "draftPatchOnly"
        case draftPreviewRequired = "draftPreviewRequired"
        case confirmedImport = "confirmedImport"
    }

    public struct EvidenceAlignment: Codable, Equatable, Sendable {
        public var suggestionID: UUID?
        public var frameID: UUID?
        public var eventIDs: [UUID]
        public var observationIDs: [UUID]
        public var sourcePreviewRefID: UUID?
        public var artifactPath: String?
        public var bounds: RecordingBounds?
        public var summary: String?

        public init(
            suggestionID: UUID? = nil,
            frameID: UUID? = nil,
            eventIDs: [UUID] = [],
            observationIDs: [UUID] = [],
            sourcePreviewRefID: UUID? = nil,
            artifactPath: String? = nil,
            bounds: RecordingBounds? = nil,
            summary: String? = nil
        ) {
            self.suggestionID = suggestionID
            self.frameID = frameID
            self.eventIDs = eventIDs
            self.observationIDs = observationIDs
            self.sourcePreviewRefID = sourcePreviewRefID
            self.artifactPath = artifactPath
            self.bounds = bounds
            self.summary = summary
        }
    }

    public var actionName: ActionName
    public var title: String
    public var mutationBoundary: MutationBoundary
    public var createsDraftPatch: Bool
    public var mutatesWorkflow: Bool
    public var evidence: EvidenceAlignment

    public init(
        actionName: ActionName,
        title: String,
        mutationBoundary: MutationBoundary,
        createsDraftPatch: Bool,
        mutatesWorkflow: Bool,
        evidence: EvidenceAlignment
    ) {
        self.actionName = actionName
        self.title = title
        self.mutationBoundary = mutationBoundary
        self.createsDraftPatch = createsDraftPatch
        self.mutatesWorkflow = mutatesWorkflow
        self.evidence = evidence
    }

    public static func acceptSuggestion(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> SemanticRecordingReviewActionSemantics {
        acceptSuggestion(
            evidence: evidenceAlignment(suggestion)
        )
    }

    public static func acceptSuggestion(
        _ suggestion: RecordingSuggestion
    ) -> SemanticRecordingReviewActionSemantics {
        acceptSuggestion(
            evidence: evidenceAlignment(suggestion)
        )
    }

    private static func acceptSuggestion(
        evidence: EvidenceAlignment
    ) -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .acceptSuggestion,
            title: "Accept suggestion",
            mutationBoundary: .draftPreviewRequired,
            createsDraftPatch: true,
            mutatesWorkflow: false,
            evidence: evidence
        )
    }

    public static func rejectSuggestion(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> SemanticRecordingReviewActionSemantics {
        rejectSuggestion(
            evidence: evidenceAlignment(suggestion)
        )
    }

    public static func rejectSuggestion(
        _ suggestion: RecordingSuggestion
    ) -> SemanticRecordingReviewActionSemantics {
        rejectSuggestion(
            evidence: evidenceAlignment(suggestion)
        )
    }

    private static func rejectSuggestion(
        evidence: EvidenceAlignment
    ) -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .rejectSuggestion,
            title: "Reject suggestion",
            mutationBoundary: .reviewLocal,
            createsDraftPatch: false,
            mutatesWorkflow: false,
            evidence: evidence
        )
    }

    public static func clearDecision(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> SemanticRecordingReviewActionSemantics {
        clearDecision(
            evidence: evidenceAlignment(suggestion)
        )
    }

    public static func clearDecision(
        _ suggestion: RecordingSuggestion
    ) -> SemanticRecordingReviewActionSemantics {
        clearDecision(
            evidence: evidenceAlignment(suggestion)
        )
    }

    private static func clearDecision(
        evidence: EvidenceAlignment
    ) -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .clearDecision,
            title: "Clear review decision",
            mutationBoundary: .reviewLocal,
            createsDraftPatch: false,
            mutatesWorkflow: false,
            evidence: evidence
        )
    }

    public static func draftCandidate(
        _ candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        regionSelection: SemanticRecordingFrameRegionSelection? = nil
    ) -> SemanticRecordingReviewActionSemantics {
        let selectedRegion = regionSelection?.frameID == candidate.sourceFrameID ? regionSelection : nil
        return SemanticRecordingReviewActionSemantics(
            actionName: selectedRegion == nil ? .draftCandidate : .draftSelection,
            title: selectedRegion == nil ? "Draft candidate" : "Draft selected region",
            mutationBoundary: .draftPreviewRequired,
            createsDraftPatch: true,
            mutatesWorkflow: false,
            evidence: evidenceAlignment(candidate, regionSelection: regionSelection)
        )
    }

    public static func previewDraft(
        _ result: SemanticRecordingReviewDraftPatchResult
    ) -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .previewDraft,
            title: "Preview draft",
            mutationBoundary: .draftPreviewRequired,
            createsDraftPatch: false,
            mutatesWorkflow: false,
            evidence: result.actionEvidence
        )
    }

    public static func previewDraft() -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .previewDraft,
            title: "Preview draft",
            mutationBoundary: .draftPreviewRequired,
            createsDraftPatch: false,
            mutatesWorkflow: false,
            evidence: EvidenceAlignment()
        )
    }

    public static func importDraft(
        _ result: SemanticRecordingReviewDraftPatchResult
    ) -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .importDraft,
            title: "Import reviewed draft",
            mutationBoundary: .confirmedImport,
            createsDraftPatch: false,
            mutatesWorkflow: true,
            evidence: result.actionEvidence
        )
    }

    public static func importDraft() -> SemanticRecordingReviewActionSemantics {
        SemanticRecordingReviewActionSemantics(
            actionName: .importDraft,
            title: "Import reviewed draft",
            mutationBoundary: .confirmedImport,
            createsDraftPatch: false,
            mutatesWorkflow: true,
            evidence: EvidenceAlignment()
        )
    }

    private static func evidenceAlignment(
        _ suggestion: SemanticRecordingReviewProjection.SuggestionRow
    ) -> EvidenceAlignment {
        let primaryEvidence = suggestion.evidence.first
        return EvidenceAlignment(
            suggestionID: suggestion.id,
            frameID: primaryEvidence?.frameID,
            eventIDs: primaryEvidence?.eventIDs ?? [],
            observationIDs: primaryEvidence?.observationIDs ?? [],
            artifactPath: primaryEvidence?.artifactPath,
            bounds: primaryEvidence?.bounds,
            summary: primaryEvidence?.summary ?? suggestion.summary
        )
    }

    private static func evidenceAlignment(
        _ suggestion: RecordingSuggestion
    ) -> EvidenceAlignment {
        let primaryEvidence = suggestion.evidence.first
        return EvidenceAlignment(
            suggestionID: suggestion.id,
            frameID: primaryEvidence?.frameID,
            eventIDs: primaryEvidence?.eventIDs ?? [],
            observationIDs: primaryEvidence?.observationIDs ?? [],
            artifactPath: primaryEvidence?.artifactRef?.path,
            bounds: primaryEvidence?.bounds,
            summary: primaryEvidence?.summary ?? suggestion.summary
        )
    }

    public static func evidenceAlignment(
        _ candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        regionSelection: SemanticRecordingFrameRegionSelection? = nil
    ) -> EvidenceAlignment {
        let selectedRegion = regionSelection?.frameID == candidate.sourceFrameID ? regionSelection : nil
        return EvidenceAlignment(
            frameID: candidate.sourceFrameID,
            observationIDs: candidate.observationID.map { [$0] } ?? [],
            sourcePreviewRefID: selectedRegion?.sourcePreviewRefID ?? candidate.sourcePreviewRefID,
            artifactPath: selectedRegion?.artifactPath ?? candidate.artifactPath,
            bounds: selectedRegion?.bounds ?? candidate.bounds,
            summary: selectedRegion?.label ?? candidate.summary
        )
    }

    public static func evidenceAlignment(
        _ candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        frame: RecordingFrameReference,
        regionSelection: SemanticRecordingFrameRegionSelection? = nil
    ) -> EvidenceAlignment {
        var evidence = evidenceAlignment(candidate, regionSelection: regionSelection)
        evidence.eventIDs = frame.relatedEventIDs
        return evidence
    }
}

public enum SemanticRecordingReviewDraftPatchError: Error, Equatable, Sendable {
    case missingSourceFrame(UUID)
    case missingRegionBounds(String)
    case invalidRegionBounds(String)
    case missingConditionText(String)
    case missingArtifact(String)
    case missingPixelColor(String)
}

public enum SemanticRecordingReviewAssetMaterializationError: Error, Equatable, Sendable {
    case missingSourceArtifact(String)
    case unsafeDestinationPath(String)
}

public enum SemanticRecordingReviewMaterializedAssetKind: String, Codable, Equatable, Sendable {
    case image
    case baseline

    public var directoryName: String {
        switch self {
        case .image:
            return "images"
        case .baseline:
            return "baselines"
        }
    }
}

public struct SemanticRecordingReviewMaterializedAsset: Codable, Equatable, Sendable {
    public var kind: SemanticRecordingReviewMaterializedAssetKind
    public var key: String
    public var sourcePath: String
    public var destinationPath: String
    public var sha256: String

    public init(
        kind: SemanticRecordingReviewMaterializedAssetKind,
        key: String,
        sourcePath: String,
        destinationPath: String,
        sha256: String
    ) {
        self.kind = kind
        self.key = key
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.sha256 = sha256
    }
}

public struct SemanticRecordingReviewAssetExtraction: Equatable, Sendable {
    public var kind: SemanticRecordingReviewMaterializedAssetKind
    public var assetKey: String
    public var sourceFrameID: UUID
    public var sourceSurfaceID: String?
    public var sourceFrameImagePath: String
    public var bounds: RecordingBounds
    public var imageSize: RecordingImageSize?

    public init(
        kind: SemanticRecordingReviewMaterializedAssetKind,
        assetKey: String,
        sourceFrameID: UUID,
        sourceSurfaceID: String? = nil,
        sourceFrameImagePath: String,
        bounds: RecordingBounds,
        imageSize: RecordingImageSize? = nil
    ) {
        self.kind = kind
        self.assetKey = assetKey
        self.sourceFrameID = sourceFrameID
        self.sourceSurfaceID = sourceSurfaceID?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch
        self.sourceFrameImagePath = sourceFrameImagePath
        self.bounds = bounds
        self.imageSize = imageSize
    }
}

public struct SemanticRecordingReviewAssetMaterializationResult: Equatable, Sendable {
    public var patch: AutomationWorkflowDraftPatchDocument
    public var copiedAssets: [SemanticRecordingReviewMaterializedAsset]

    public init(
        patch: AutomationWorkflowDraftPatchDocument,
        copiedAssets: [SemanticRecordingReviewMaterializedAsset]
    ) {
        self.patch = patch
        self.copiedAssets = copiedAssets
    }
}

public enum SemanticRecordingReviewAssetMaterializer {
    public static func materialize(
        patch: AutomationWorkflowDraftPatchDocument,
        assetExtractions: [SemanticRecordingReviewAssetExtraction] = [],
        readArtifact: (_ sourcePath: String) throws -> Data,
        prepareAssetData: (_ data: Data, _ extraction: SemanticRecordingReviewAssetExtraction?) throws -> Data = { data, _ in data },
        writeAsset: (_ data: Data, _ destinationPath: String) throws -> Void
    ) throws -> SemanticRecordingReviewAssetMaterializationResult {
        var patch = patch
        var copiedAssets: [SemanticRecordingReviewMaterializedAsset] = []
        let extractionsByKindAndKey = assetExtractions.reduce(
            into: [String: SemanticRecordingReviewAssetExtraction]()
        ) { partial, extraction in
            partial[extractionKey(kind: extraction.kind, assetKey: extraction.assetKey)] = extraction
        }

        for index in patch.ops.indices {
            switch patch.ops[index].op {
            case "upsertVisualImage":
                guard let asset = patch.ops[index].visualImage else {
                    continue
                }
                let extraction = extractionsByKindAndKey[extractionKey(kind: .image, assetKey: asset.key)]
                let materialized = try materialize(
                    asset: asset,
                    kind: .image,
                    extraction: extraction,
                    readArtifact: readArtifact,
                    prepareAssetData: prepareAssetData,
                    writeAsset: writeAsset
                )
                patch.ops[index].visualImage?.path = materialized.destinationPath
                patch.ops[index].visualImage?.sha256 = materialized.sha256
                copiedAssets.append(materialized)

            case "upsertVisualBaseline":
                guard let asset = patch.ops[index].visualBaseline else {
                    continue
                }
                let extraction = extractionsByKindAndKey[extractionKey(kind: .baseline, assetKey: asset.key)]
                let materialized = try materialize(
                    asset: asset,
                    kind: .baseline,
                    extraction: extraction,
                    readArtifact: readArtifact,
                    prepareAssetData: prepareAssetData,
                    writeAsset: writeAsset
                )
                patch.ops[index].visualBaseline?.path = materialized.destinationPath
                patch.ops[index].visualBaseline?.sha256 = materialized.sha256
                copiedAssets.append(materialized)

            default:
                continue
            }
        }

        return SemanticRecordingReviewAssetMaterializationResult(
            patch: patch,
            copiedAssets: copiedAssets
        )
    }

    private static func materialize(
        asset: AutomationWorkflowDraftVisualImageAsset,
        kind: SemanticRecordingReviewMaterializedAssetKind,
        extraction: SemanticRecordingReviewAssetExtraction?,
        readArtifact: (_ sourcePath: String) throws -> Data,
        prepareAssetData: (_ data: Data, _ extraction: SemanticRecordingReviewAssetExtraction?) throws -> Data,
        writeAsset: (_ data: Data, _ destinationPath: String) throws -> Void
    ) throws -> SemanticRecordingReviewMaterializedAsset {
        guard let rawSourcePath = extraction?.sourceFrameImagePath ??
                asset.path?.trimmedForSemanticReviewPatch.nilIfEmptyForSemanticReviewPatch,
              let sourcePath = try? RecordingArtifactRef.normalized(rawSourcePath) else {
            throw SemanticRecordingReviewAssetMaterializationError.missingSourceArtifact(asset.key)
        }

        let destinationPath = destinationPath(
            for: asset,
            sourcePath: sourcePath,
            kind: kind,
            usesCropExtraction: extraction != nil
        )
        guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(destinationPath) == destinationPath else {
            throw SemanticRecordingReviewAssetMaterializationError.unsafeDestinationPath(destinationPath)
        }

        let data = try prepareAssetData(readArtifact(sourcePath), extraction)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        try writeAsset(data, destinationPath)

        return SemanticRecordingReviewMaterializedAsset(
            kind: kind,
            key: asset.key,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            sha256: digest
        )
    }

    private static func destinationPath(
        for asset: AutomationWorkflowDraftVisualImageAsset,
        sourcePath: String,
        kind: SemanticRecordingReviewMaterializedAssetKind,
        usesCropExtraction: Bool
    ) -> String {
        let fileExtension = usesCropExtraction ? "png" : safeFileExtension(from: sourcePath)
        return "assets/\(kind.directoryName)/\(safeFileStem(for: asset.key)).\(fileExtension)"
    }

    private static func extractionKey(
        kind: SemanticRecordingReviewMaterializedAssetKind,
        assetKey: String
    ) -> String {
        "\(kind.rawValue):\(assetKey)"
    }

    private static func safeFileExtension(from path: String) -> String {
        let rawExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        let cleaned = rawExtension.filter { character in
            character.isLetter || character.isNumber
        }
        guard !cleaned.isEmpty, cleaned.count <= 8 else {
            return "png"
        }
        return cleaned
    }

    private static func safeFileStem(for value: String) -> String {
        let stem = value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .reduce(into: "") { partial, character in
                if partial.last == "_" && character == "_" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return stem.isEmpty ? "semantic_review_asset" : stem
    }
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
    public var assetExtractions: [SemanticRecordingReviewAssetExtraction]
    public var actionEvidence: SemanticRecordingReviewActionSemantics.EvidenceAlignment
    public var appliesToExistingTask: Bool

    public init(
        patch: AutomationWorkflowDraftPatchDocument,
        taskKey: String,
        condition: AutomationWorkflowDraftCondition,
        region: AutomationWorkflowDraftVisualRegion? = nil,
        imageAsset: AutomationWorkflowDraftVisualImageAsset? = nil,
        baselineAsset: AutomationWorkflowDraftVisualImageAsset? = nil,
        assetExtractions: [SemanticRecordingReviewAssetExtraction] = [],
        actionEvidence: SemanticRecordingReviewActionSemantics.EvidenceAlignment = .init(),
        appliesToExistingTask: Bool
    ) {
        self.patch = patch
        self.taskKey = taskKey
        self.condition = condition
        self.region = region
        self.imageAsset = imageAsset
        self.baselineAsset = baselineAsset
        self.assetExtractions = assetExtractions
        self.actionEvidence = actionEvidence
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
        let usesManualRegionSelection = request.regionSelection != nil
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
        var assetExtractions: [SemanticRecordingReviewAssetExtraction] = []

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
                sha256: sourcePreview?.contentDigest?.value,
                sourceFrameID: frame.id,
                sourceSurfaceID: selection.surfaceID ?? frame.surfaceID,
                sourceArtifactPath: frame.imageRef.path,
                sourceBounds: region.bounds,
                sourceBoundsSpace: region.space
            )
            if usesManualRegionSelection {
                assetExtractions.append(assetExtraction(
                    kind: .image,
                    assetKey: imageKey,
                    frame: frame,
                    selection: selection
                ))
            }
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
                sha256: sourcePreview?.contentDigest?.value,
                sourceFrameID: frame.id,
                sourceSurfaceID: selection.surfaceID ?? frame.surfaceID,
                sourceArtifactPath: frame.imageRef.path,
                sourceBounds: region.bounds,
                sourceBoundsSpace: region.space
            )
            if usesManualRegionSelection {
                assetExtractions.append(assetExtraction(
                    kind: .baseline,
                    assetKey: baselineKey,
                    frame: frame,
                    selection: selection
                ))
            }
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
            assetExtractions: assetExtractions,
            actionEvidence: SemanticRecordingReviewActionSemantics.evidenceAlignment(
                candidate,
                frame: frame,
                regionSelection: request.regionSelection
            ),
            appliesToExistingTask: appliesToExistingTask
        )
    }

    private static func assetExtraction(
        kind: SemanticRecordingReviewMaterializedAssetKind,
        assetKey: String,
        frame: RecordingFrameReference,
        selection: SemanticRecordingFrameRegionSelection
    ) -> SemanticRecordingReviewAssetExtraction {
        SemanticRecordingReviewAssetExtraction(
            kind: kind,
            assetKey: assetKey,
            sourceFrameID: frame.id,
            sourceSurfaceID: selection.surfaceID ?? frame.surfaceID,
            sourceFrameImagePath: frame.imageRef.path,
            bounds: selection.bounds,
            imageSize: frame.imageSize
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

import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Action Semantics Tests")
struct SemanticRecordingReviewActionSemanticsTests {
    @Test("Review action semantics align with shared suggestion evidence refs")
    func reviewActionSemanticsAlignWithSharedSuggestionEvidenceRefs() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )

        let sharedSuggestion = try #require(suggestions.first)
        let reviewSuggestion = try #require(projection.suggestionRows.first)
        let accept = SemanticRecordingReviewActionSemantics
            .acceptSuggestion(reviewSuggestion)
        let reject = SemanticRecordingReviewActionSemantics
            .rejectSuggestion(reviewSuggestion)

        #expect(accept.actionName.rawValue == "review.acceptSuggestion")
        #expect(accept.mutationBoundary == .draftPreviewRequired)
        #expect(accept.createsDraftPatch)
        #expect(!accept.mutatesWorkflow)
        #expect(accept.evidence.suggestionID == sharedSuggestion.id)
        #expect(accept.evidence.frameID == sharedSuggestion.evidence.first?.frameID)
        #expect(accept.evidence.eventIDs == sharedSuggestion.evidence.first?.eventIDs)
        #expect(accept.evidence.observationIDs == sharedSuggestion.evidence.first?.observationIDs)
        #expect(accept.evidence.artifactPath == sharedSuggestion.evidence.first?.artifactRef?.path)

        #expect(reject.actionName.rawValue == "review.rejectSuggestion")
        #expect(reject.mutationBoundary == .reviewLocal)
        #expect(!reject.createsDraftPatch)
        #expect(!reject.mutatesWorkflow)
        #expect(reject.evidence.artifactPath == "visual-index/ocr/confirmation-region.png")

        let candidate = try #require(projection.selectedFrame?.conditionCandidates.first)
        let selection = SemanticRecordingFrameRegionSelection(
            frameID: SemanticRecordingFixture.afterClickFrameID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: RecordingBounds(
                rect: RecordingRect(x: 44, y: 55, width: 120, height: 34),
                coordinateSpace: .windowPixels
            ),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            label: "S4 reviewed region",
            candidateKind: .ocrWait,
            sourcePreviewRefID: candidate.sourcePreviewRefID,
            observationID: candidate.observationID,
            artifactPath: candidate.artifactPath
        )
        let draftSelection = SemanticRecordingReviewActionSemantics
            .draftCandidate(candidate, regionSelection: selection)

        #expect(draftSelection.actionName.rawValue == "review.draftSelection")
        #expect(draftSelection.mutationBoundary == .draftPreviewRequired)
        #expect(draftSelection.createsDraftPatch)
        #expect(!draftSelection.mutatesWorkflow)
        #expect(draftSelection.evidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(draftSelection.evidence.sourcePreviewRefID == SemanticRecordingFixture.sourceOCRRefID)
        #expect(draftSelection.evidence.bounds == selection.bounds)
        #expect(draftSelection.evidence.summary == "S4 reviewed region")
    }

    @Test("Review action semantics can be generated from raw S4 suggestions")
    func reviewActionSemanticsCanBeGeneratedFromRawS4Suggestions() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestion = try #require(
            SemanticRecordingFixture.checkoutSuggestions(bundle: bundle).first
        )

        let accept = SemanticRecordingReviewActionSemantics.acceptSuggestion(suggestion)
        let reject = SemanticRecordingReviewActionSemantics.rejectSuggestion(suggestion)
        let clear = SemanticRecordingReviewActionSemantics.clearDecision(suggestion)

        #expect(accept.actionName == .acceptSuggestion)
        #expect(accept.mutationBoundary == .draftPreviewRequired)
        #expect(accept.createsDraftPatch)
        #expect(!accept.mutatesWorkflow)
        #expect(accept.evidence.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(accept.evidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(accept.evidence.eventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(accept.evidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(accept.evidence.artifactPath == "visual-index/ocr/confirmation-region.png")

        #expect(reject.actionName == .rejectSuggestion)
        #expect(reject.mutationBoundary == .reviewLocal)
        #expect(!reject.createsDraftPatch)
        #expect(!reject.mutatesWorkflow)
        #expect(reject.evidence == accept.evidence)

        #expect(clear.actionName == .clearDecision)
        #expect(clear.mutationBoundary == .reviewLocal)
        #expect(!clear.createsDraftPatch)
        #expect(!clear.mutatesWorkflow)
        #expect(clear.evidence == accept.evidence)
    }

    @Test("Suggestion patch resolver carries suggestion id into draft request")
    func suggestionPatchResolverCarriesSuggestionIDIntoDraftRequest() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )
        let reviewSuggestion = try #require(projection.suggestionRows.first)

        let match = try #require(
            SemanticRecordingReviewSuggestionPatchResolver.makeRequest(
                suggestion: reviewSuggestion,
                bundle: bundle
            )
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: match.request
        )
        let preview = SemanticRecordingReviewActionSemantics.previewDraft(result)

        #expect(match.candidate.kind == .ocrWait)
        #expect(match.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(match.eventID == SemanticRecordingFixture.clickEventID)
        #expect(match.request.sourceSuggestionID == SemanticRecordingFixture.suggestionID)
        #expect(result.actionEvidence.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(result.actionEvidence.frameID == SemanticRecordingFixture.afterClickFrameID)
        #expect(result.actionEvidence.eventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(result.actionEvidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(result.actionEvidence.artifactPath == "visual-index/ocr/confirmation-region.png")
        #expect(result.actionEvidence.draftTaskKey == result.taskKey)
        #expect(result.actionEvidence.draftConditionType == result.condition.type)
        #expect(result.actionEvidence.visualRegionKey == result.region?.key)
        #expect(result.actionEvidence.visualAssetKind == nil)
        #expect(result.actionEvidence.visualAssetKey == nil)
        #expect(preview.evidence == result.actionEvidence)
    }

    @Test("Suggestion patch resolver keeps reviewed selection bounds")
    func suggestionPatchResolverKeepsReviewedSelectionBounds() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            suggestions: suggestions,
            selectedEventID: SemanticRecordingFixture.waitEventID
        )
        let reviewSuggestion = try #require(projection.suggestionRows.first)
        let selection = SemanticRecordingFrameRegionSelection(
            frameID: SemanticRecordingFixture.afterClickFrameID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: RecordingBounds(
                rect: RecordingRect(x: 720, y: 226, width: 180, height: 34),
                coordinateSpace: .windowPixels
            ),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            label: "Reviewed confirmation crop",
            candidateKind: .ocrWait,
            sourcePreviewRefID: SemanticRecordingFixture.sourceOCRRefID,
            observationID: SemanticRecordingFixture.ocrObservationID,
            artifactPath: "visual-index/ocr/confirmation-region.png"
        )

        let match = try #require(
            SemanticRecordingReviewSuggestionPatchResolver.makeRequest(
                suggestion: reviewSuggestion,
                bundle: bundle,
                regionSelection: selection
            )
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: match.request
        )

        #expect(match.request.sourceSuggestionID == SemanticRecordingFixture.suggestionID)
        #expect(match.request.regionSelection == selection)
        #expect(result.actionEvidence.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(result.actionEvidence.eventIDs == [
            SemanticRecordingFixture.clickEventID,
            SemanticRecordingFixture.waitEventID
        ])
        #expect(result.actionEvidence.observationIDs == [SemanticRecordingFixture.ocrObservationID])
        #expect(result.actionEvidence.sourcePreviewRefID == SemanticRecordingFixture.sourceOCRRefID)
        #expect(result.actionEvidence.artifactPath == "visual-index/ocr/confirmation-region.png")
        #expect(result.actionEvidence.draftTaskKey == result.taskKey)
        #expect(result.actionEvidence.draftConditionType == result.condition.type)
        #expect(result.actionEvidence.visualRegionKey == result.region?.key)
        #expect(result.actionEvidence.bounds == selection.bounds)
        #expect(result.actionEvidence.summary == "Reviewed confirmation crop")
    }

    @Test("Preview and import draft actions preserve staged patch evidence")
    func previewAndImportDraftActionsPreserveStagedPatchEvidence() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                newTaskKey: "wait_checkout_button",
                sourceSuggestionID: SemanticRecordingFixture.suggestionID
            )
        )

        let preview = SemanticRecordingReviewActionSemantics.previewDraft(result)
        let importAction = SemanticRecordingReviewActionSemantics.importDraft(result)

        #expect(result.actionEvidence.frameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(result.actionEvidence.suggestionID == SemanticRecordingFixture.suggestionID)
        #expect(result.actionEvidence.eventIDs == [SemanticRecordingFixture.clickEventID])
        #expect(result.actionEvidence.sourcePreviewRefID == SemanticRecordingFixture.sourceTemplateRefID)
        #expect(result.actionEvidence.observationIDs.isEmpty)
        #expect(result.actionEvidence.artifactPath == "visual-index/templates/checkout-button.png")
        #expect(result.actionEvidence.draftTaskKey == "wait_checkout_button")
        #expect(result.actionEvidence.draftConditionType == "imageAppeared")
        #expect(result.actionEvidence.visualRegionKey == result.region?.key)
        #expect(result.actionEvidence.visualAssetKind == .image)
        #expect(result.actionEvidence.visualAssetKey == result.imageAsset?.key)
        #expect(result.actionEvidence.bounds == RecordingBounds(
            rect: RecordingRect(x: 880, y: 620, width: 180, height: 48),
            coordinateSpace: .windowPixels
        ))

        #expect(preview.actionName == .previewDraft)
        #expect(preview.mutationBoundary == .draftPreviewRequired)
        #expect(!preview.createsDraftPatch)
        #expect(!preview.mutatesWorkflow)
        #expect(preview.evidence == result.actionEvidence)

        #expect(importAction.actionName == .importDraft)
        #expect(importAction.mutationBoundary == .confirmedImport)
        #expect(!importAction.createsDraftPatch)
        #expect(importAction.mutatesWorkflow)
        #expect(importAction.evidence == result.actionEvidence)
    }

    @Test("Preview and import draft actions cite materialized assets")
    func previewAndImportDraftActionsCiteMaterializedAssets() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(candidate: candidate)
        )
        let templateData = Data("template-data".utf8)
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: result.patch,
            readArtifact: { sourcePath in
                #expect(sourcePath == "visual-index/templates/checkout-button.png")
                return templateData
            },
            writeAsset: { _, _ in }
        )

        let preview = SemanticRecordingReviewActionSemantics.previewDraft(
            result,
            materializedAssets: materialized.copiedAssets
        )
        let importAction = SemanticRecordingReviewActionSemantics.importDraft(
            result,
            materializedAssets: materialized.copiedAssets
        )
        let expectedPath = "assets/images/sr_00000001_checkout_button_0000000f_template.png"
        let expectedDigest = "20dc26ad587152ac3f284bd839b19944cb945d680f3220334697b5aa0f455f13"

        #expect(preview.evidence.artifactPath == "visual-index/templates/checkout-button.png")
        #expect(preview.evidence.draftTaskKey == result.taskKey)
        #expect(preview.evidence.draftConditionType == result.condition.type)
        #expect(preview.evidence.visualRegionKey == result.region?.key)
        #expect(preview.evidence.visualAssetKind == .image)
        #expect(preview.evidence.visualAssetKey == result.imageAsset?.key)
        #expect(preview.evidence.materializedArtifactPath == expectedPath)
        #expect(preview.evidence.materializedSHA256 == expectedDigest)
        #expect(importAction.evidence.artifactPath == preview.evidence.artifactPath)
        #expect(importAction.evidence.materializedArtifactPath == expectedPath)
        #expect(importAction.evidence.materializedSHA256 == expectedDigest)
    }

    @Test("Materialized draft actions align by visual asset key before source path")
    func materializedDraftActionsAlignByVisualAssetKeyBeforeSourcePath() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.clickEventID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first { $0.kind == .imageAppeared }
        )
        let selection = SemanticRecordingFrameRegionSelection(
            frameID: SemanticRecordingFixture.beforeClickFrameID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: RecordingBounds(
                rect: RecordingRect(x: 20, y: 30, width: 80, height: 50),
                coordinateSpace: .framePixels
            ),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            label: "Reviewed crop",
            candidateKind: .imageAppeared,
            sourcePreviewRefID: candidate.sourcePreviewRefID,
            observationID: candidate.observationID,
            artifactPath: candidate.artifactPath
        )
        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                regionSelection: selection
            )
        )
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: result.patch,
            assetExtractions: result.assetExtractions,
            readArtifact: { sourcePath in
                #expect(sourcePath == "frames/000014-before-click.png")
                return Data("frame-image".utf8)
            },
            prepareAssetData: { _, _ in Data("reviewed-crop".utf8) },
            writeAsset: { _, _ in }
        )
        let unrelatedExactPathAsset = SemanticRecordingReviewMaterializedAsset(
            kind: .baseline,
            key: "unrelated_baseline",
            sourcePath: "visual-index/templates/checkout-button.png",
            destinationPath: "assets/baselines/unrelated_baseline.png",
            sha256: "wrong-digest"
        )

        let preview = SemanticRecordingReviewActionSemantics.previewDraft(
            result,
            materializedAssets: [unrelatedExactPathAsset] + materialized.copiedAssets
        )
        let expectedPath = "assets/images/sr_00000001_checkout_button_0000000f_template.png"
        let expectedDigest = "4d46c6635bf07c73339741bc5331e52b53bd56fb3cbc5217f4a516ff232c7424"

        #expect(result.actionEvidence.artifactPath == "visual-index/templates/checkout-button.png")
        #expect(result.actionEvidence.visualAssetKind == .image)
        #expect(result.actionEvidence.visualAssetKey == result.imageAsset?.key)
        #expect(preview.evidence.materializedArtifactPath == expectedPath)
        #expect(preview.evidence.materializedSHA256 == expectedDigest)
        #expect(preview.evidence.materializedSHA256 != unrelatedExactPathAsset.sha256)
    }

    @Test("Review action semantics are Codable for S4 JSON payloads")
    func reviewActionSemanticsAreCodableForS4JSONPayloads() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let suggestion = try #require(
            SemanticRecordingFixture.checkoutSuggestions(bundle: bundle).first
        )
        let action = SemanticRecordingReviewActionSemantics.acceptSuggestion(suggestion)

        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingReviewActionSemantics.self,
            from: data
        )

        #expect(decoded == action)
        #expect(decoded.actionName.rawValue == "review.acceptSuggestion")
        #expect(decoded.mutationBoundary.rawValue == "draftPreviewRequired")
        #expect(decoded.evidence.suggestionID == suggestion.id)
        #expect(decoded.evidence.artifactPath == suggestion.evidence.first?.artifactRef?.path)
    }
}

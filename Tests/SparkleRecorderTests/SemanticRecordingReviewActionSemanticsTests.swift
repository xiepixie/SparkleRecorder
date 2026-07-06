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
                newTaskKey: "wait_checkout_button"
            )
        )

        let preview = SemanticRecordingReviewActionSemantics.previewDraft(result)
        let importAction = SemanticRecordingReviewActionSemantics.importDraft(result)

        #expect(result.actionEvidence.frameID == SemanticRecordingFixture.beforeClickFrameID)
        #expect(result.actionEvidence.sourcePreviewRefID == SemanticRecordingFixture.sourceTemplateRefID)
        #expect(result.actionEvidence.observationIDs.isEmpty)
        #expect(result.actionEvidence.artifactPath == "visual-index/templates/checkout-button.png")
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

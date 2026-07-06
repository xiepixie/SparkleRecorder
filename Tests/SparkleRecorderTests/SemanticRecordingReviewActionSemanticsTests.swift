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
}

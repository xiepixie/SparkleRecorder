import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Label Presentation Tests")
struct SemanticRecordingReviewLabelPresentationTests {
    @Test("Timeline event labels do not expose raw enum values")
    func timelineEventLabelsDoNotExposeRawValues() {
        let values: [RecordingTimelineEventKind] = [
            .rawInput, .recordedEvent, .focusChange, .windowSnapshot, .keyframe,
            .visualObservation, .waitStart, .waitEnd, .userMarker, .suppression, .note
        ]

        for value in values {
            let label = SemanticRecordingReviewLabelPresentation.timelineEventKind(value)
            #expect(!label.isEmpty)
            #expect(label != value.rawValue)
        }
    }

    @Test("Frame source labels do not expose raw enum values")
    func frameSourceLabelsDoNotExposeRawValues() {
        let values: [RecordingFrameCaptureSource] = [
            .recordingStart, .recordingStop, .focusChange, .mouseDown, .mouseUp,
            .dragEnd, .textInput, .scrollSettled, .longWaitBefore, .longWaitAfter,
            .userMarker, .frameDifference, .manual, .other
        ]

        for value in values {
            let label = SemanticRecordingReviewLabelPresentation.frameCaptureSource(value)
            #expect(!label.isEmpty)
            #expect(label != value.rawValue)
        }
    }

    @Test("Review semantic labels do not expose machine identifiers")
    func reviewSemanticLabelsDoNotExposeMachineIdentifiers() {
        let candidateKinds: [SemanticRecordingReviewProjection.ConditionCandidateKind] = [
            .ocrWait, .imageAppeared, .imageDisappeared, .regionChanged, .pixelMatched
        ]
        for value in candidateKinds {
            #expect(SemanticRecordingReviewLabelPresentation.conditionCandidateKind(value) != value.rawValue)
        }

        let outcomes: [RecordingPreviewComparisonOutcome] = [
            .matched, .changed, .unchanged, .missingSource, .missingSample,
            .unreadable, .rejected, .unavailable
        ]
        for value in outcomes {
            #expect(SemanticRecordingReviewLabelPresentation.comparisonOutcome(value) != value.rawValue)
        }

        let suggestions: [RecordingSuggestionKind] = [
            .waitCleanup, .locatorReplacement, .conditionCandidate,
            .visualAssetExtraction, .fragileClick, .draftGeneration
        ]
        for value in suggestions {
            #expect(SemanticRecordingReviewLabelPresentation.suggestionKind(value) != value.rawValue)
        }
    }

    @Test("Review action labels hide stable machine action names")
    func reviewActionLabelsHideMachineActionNames() {
        let actions: [SemanticRecordingReviewActionSemantics.ActionName] = [
            .draftCandidate, .draftSelection, .acceptSuggestion, .rejectSuggestion,
            .clearDecision, .materializeAsset, .previewDraft, .importDraft
        ]

        for action in actions {
            let label = SemanticRecordingReviewLabelPresentation.actionName(action)
            #expect(!label.isEmpty)
            #expect(label != action.rawValue)
            #expect(!label.hasPrefix("review."))
        }
    }

    @Test("Coordinate labels hide serialized coordinate-space names")
    func coordinateLabelsHideSerializedNames() {
        let spaces: [RecordingCoordinateSpace] = [
            .screenPixels, .displayPixels, .windowPixels,
            .contentPixels, .framePixels, .normalizedFrame
        ]

        for space in spaces {
            #expect(SemanticRecordingReviewLabelPresentation.coordinateSpace(space) != space.rawValue)
        }
    }
}

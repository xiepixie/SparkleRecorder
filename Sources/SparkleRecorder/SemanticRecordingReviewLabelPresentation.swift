import Foundation
import SparkleRecorderCore

enum SemanticRecordingReviewLabelPresentation {
    static func timelineEventKind(_ kind: RecordingTimelineEventKind) -> String {
        switch kind {
        case .rawInput:
            return String(localized: "Raw input", table: "EditorUX")
        case .recordedEvent:
            return String(localized: "Recorded event", table: "EditorUX")
        case .focusChange:
            return String(localized: "Focus change", table: "EditorUX")
        case .windowSnapshot:
            return String(localized: "Window snapshot", table: "EditorUX")
        case .keyframe:
            return String(localized: "Keyframe", table: "EditorUX")
        case .visualObservation:
            return String(localized: "Visual observation", table: "EditorUX")
        case .waitStart:
            return String(localized: "Wait started", table: "EditorUX")
        case .waitEnd:
            return String(localized: "Wait ended", table: "EditorUX")
        case .userMarker:
            return String(localized: "User marker", table: "EditorUX")
        case .suppression:
            return String(localized: "Privacy protection", table: "EditorUX")
        case .note:
            return String(localized: "Note", table: "EditorUX")
        }
    }

    static func frameCaptureSource(_ source: RecordingFrameCaptureSource) -> String {
        switch source {
        case .recordingStart:
            return String(localized: "Recording started", table: "EditorUX")
        case .recordingStop:
            return String(localized: "Recording stopped", table: "EditorUX")
        case .focusChange:
            return String(localized: "Focus change", table: "EditorUX")
        case .mouseDown:
            return String(localized: "Mouse down", table: "EditorUX")
        case .mouseUp:
            return String(localized: "Mouse up", table: "EditorUX")
        case .dragEnd:
            return String(localized: "Drag ended", table: "EditorUX")
        case .textInput:
            return String(localized: "Text input", table: "EditorUX")
        case .scrollSettled:
            return String(localized: "Scroll settled", table: "EditorUX")
        case .longWaitBefore:
            return String(localized: "Before long wait", table: "EditorUX")
        case .longWaitAfter:
            return String(localized: "After long wait", table: "EditorUX")
        case .userMarker:
            return String(localized: "User marker", table: "EditorUX")
        case .frameDifference:
            return String(localized: "Frame changed", table: "EditorUX")
        case .manual:
            return String(localized: "Manual capture", table: "EditorUX")
        case .other:
            return String(localized: "Other", table: "Common")
        }
    }

    static func conditionCandidateKind(
        _ kind: SemanticRecordingReviewProjection.ConditionCandidateKind
    ) -> String {
        switch kind {
        case .ocrWait:
            return String(localized: "Wait for text", table: "EditorUX")
        case .imageAppeared:
            return String(localized: "Image appeared", table: "Common")
        case .imageDisappeared:
            return String(localized: "Image disappeared", table: "Common")
        case .regionChanged:
            return String(localized: "Region changed", table: "EditorUX")
        case .pixelMatched:
            return String(localized: "Pixel matched", table: "Common")
        }
    }

    static func comparisonOutcome(_ outcome: RecordingPreviewComparisonOutcome) -> String {
        switch outcome {
        case .matched:
            return String(localized: "Matched", table: "EditorUX")
        case .changed:
            return String(localized: "Changed", table: "EditorUX")
        case .unchanged:
            return String(localized: "Unchanged", table: "EditorUX")
        case .missingSource:
            return String(localized: "Reference missing", table: "EditorUX")
        case .missingSample:
            return String(localized: "Runtime sample missing", table: "EditorUX")
        case .unreadable:
            return String(localized: "Unreadable", table: "EditorUX")
        case .rejected:
            return String(localized: "Rejected", table: "Common")
        case .unavailable:
            return String(localized: "Unavailable", table: "EditorUX")
        }
    }

    static func suggestionKind(_ kind: RecordingSuggestionKind) -> String {
        switch kind {
        case .waitCleanup:
            return String(localized: "Improve wait step", table: "EditorUX")
        case .locatorReplacement:
            return String(localized: "Replace locator", table: "EditorUX")
        case .conditionCandidate:
            return String(localized: "Condition suggestion", table: "EditorUX")
        case .visualAssetExtraction:
            return String(localized: "Extract visual asset", table: "EditorUX")
        case .fragileClick:
            return String(localized: "Fragile click", table: "EditorUX")
        case .draftGeneration:
            return String(localized: "Generate draft", table: "EditorUX")
        }
    }

    static func actionName(_ action: SemanticRecordingReviewActionSemantics.ActionName) -> String {
        switch action {
        case .draftCandidate:
            return String(localized: "Create draft from candidate", table: "EditorUX")
        case .draftSelection:
            return String(localized: "Create draft from selection", table: "EditorUX")
        case .acceptSuggestion:
            return String(localized: "Accept suggestion", table: "EditorUX")
        case .rejectSuggestion:
            return String(localized: "Reject suggestion", table: "EditorUX")
        case .clearDecision:
            return String(localized: "Clear review decision", table: "EditorUX")
        case .materializeAsset:
            return String(localized: "Prepare visual asset", table: "EditorUX")
        case .previewDraft:
            return String(localized: "Preview draft", table: "EditorUX")
        case .importDraft:
            return String(localized: "Import draft", table: "EditorUX")
        }
    }

    static func coordinateSpace(_ space: RecordingCoordinateSpace) -> String {
        switch space {
        case .screenPixels:
            return String(localized: "Screen coordinates", table: "EditorUX")
        case .displayPixels:
            return String(localized: "Display coordinates", table: "EditorUX")
        case .windowPixels:
            return String(localized: "Window coordinates", table: "EditorUX")
        case .contentPixels:
            return String(localized: "Content coordinates", table: "Common")
        case .framePixels:
            return String(localized: "Frame coordinates", table: "EditorUX")
        case .normalizedFrame:
            return String(localized: "Normalized frame coordinates", table: "EditorUX")
        }
    }
}

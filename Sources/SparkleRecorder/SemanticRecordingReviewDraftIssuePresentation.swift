import Foundation
import SparkleRecorderCore

enum SemanticRecordingReviewDraftIssuePresentation {
    static func message(for error: Error) -> String {
        if let editError = error as? AutomationWorkflowDraftEditError {
            return AutomationWorkflowDraftEditIssuePresentation.message(for: editError)
        }
        if let patchError = error as? SemanticRecordingReviewDraftPatchError {
            return message(for: patchError)
        }
        if let materializationError = error as? SemanticRecordingReviewAssetMaterializationError {
            return message(for: materializationError)
        }
        if let presenterError = error as? SemanticRecordingReviewPresenterError {
            return presenterError.localizedDescription
        }
        if error is RecordingArtifactRefError {
            return String(
                localized: "The visual evidence reference is invalid. Choose the evidence again.",
                table: "Common"
            )
        }
        return String(
            localized: "The review draft could not be prepared. Check the selected evidence and try again.",
            table: "Common"
        )
    }

    static func saveMessage(for error: Error) -> String {
        String(
            localized: "The draft patch could not be saved. Check the destination and try again.",
            table: "Common"
        )
    }

    private static func message(for error: SemanticRecordingReviewDraftPatchError) -> String {
        switch error {
        case .missingSourceFrame:
            return String(localized: "The source frame for this review item is no longer available.", table: "Common")
        case .missingRegionBounds:
            return String(localized: "This review item does not include a usable region. Select a region and try again.", table: "Common")
        case .invalidRegionBounds:
            return String(localized: "The selected review region is invalid. Select the region again.", table: "Common")
        case .missingConditionText:
            return String(localized: "This suggestion does not include the text needed to create a condition.", table: "Common")
        case .missingArtifact:
            return String(localized: "The visual evidence needed for this suggestion is unavailable.", table: "Common")
        case .missingPixelColor:
            return String(localized: "Choose a target pixel color before creating this condition.", table: "Common")
        }
    }

    private static func message(for error: SemanticRecordingReviewAssetMaterializationError) -> String {
        switch error {
        case .missingSourceArtifact:
            return String(localized: "The source visual evidence file could not be found.", table: "Common")
        case .unsafeDestinationPath:
            return String(localized: "The visual evidence could not be prepared for this draft.", table: "Common")
        }
    }
}

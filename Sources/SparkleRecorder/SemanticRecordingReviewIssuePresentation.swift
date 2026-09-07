import Foundation
import SparkleRecorderCore

enum SemanticRecordingReviewIssuePresenter {
    static func validationIssue(_ issue: SemanticRecordingBundleIssue) -> String {
        switch issue {
        case .unsupportedSchemaVersion:
            return String(
                localized: "This recording bundle uses an unsupported format.",
                table: "Common"
            )

        case .duplicateVideoSegmentID,
             .duplicateFrameID,
             .duplicateTimelineEventID,
             .duplicateSemanticEventID,
             .duplicateVisualObservationID,
             .duplicateSourcePreviewID,
             .duplicateRuntimeSampleID,
             .duplicatePreviewComparisonID,
             .duplicateSuppressionID,
             .duplicateRedactedFrameID,
             .duplicateRedactedVideoSegmentID,
             .duplicateInputEvidenceSampleIndex:
            return String(
                localized: "The recording bundle contains duplicate evidence identifiers.",
                table: "Common"
            )

        case .frameReferencesMissingVideoSegment,
             .timelineEventReferencesMissingFrame,
             .timelineEventReferencesMissingVideoSegment,
             .semanticEventReferencesMissingFrame,
             .semanticEventReferencesMissingTimelineEvent,
             .semanticEventReferencesMissingObservation,
             .visualObservationReferencesMissingFrame,
             .visualObservationReferencesMissingSourcePreview,
             .sourcePreviewReferencesMissingFrame,
             .sourcePreviewReferencesMissingTimelineEvent,
             .comparisonReferencesMissingSource,
             .comparisonReferencesMissingSample,
             .suppressionReferencesMissingFrame,
             .suppressionReferencesMissingTimelineEvent,
             .redactedFrameReferencesMissingFrame,
             .redactedFrameReferencesMissingSuppression,
             .redactedVideoReferencesMissingVideoSegment,
             .redactedVideoReferencesMissingSuppression,
             .invalidPlayableEvidenceLinkRange,
             .playableEvidenceLinkReferencesMissingSample:
            return String(
                localized: "The recording bundle contains a broken evidence reference.",
                table: "Common"
            )
        }
    }

    static func suppressionTitle(_ reason: RecordingSuppressionReason) -> String {
        switch reason {
        case .secureInput:
            return String(localized: "Secure Input", table: "Common")
        case .passwordField:
            return String(localized: "Password field", table: "Common")
        case .excludedApplication:
            return String(localized: "Excluded app", table: "Common")
        case .excludedWindow:
            return String(localized: "Excluded window", table: "Common")
        case .excludedDomain:
            return String(localized: "Excluded domain", table: "Common")
        case .privateRegion:
            return String(localized: "Private region", table: "Common")
        case .oversizedArtifact:
            return String(localized: "Artifact too large", table: "Common")
        case .userDeleted:
            return String(localized: "Deleted by user", table: "Common")
        case .unknown:
            return String(localized: "Protected context", table: "Common")
        }
    }

    static func suppressionExplanation(_ reason: RecordingSuppressionReason) -> String {
        switch reason {
        case .secureInput:
            return String(
                localized: "Keyboard and visual evidence were withheld while Secure Input was active.",
                table: "Common"
            )
        case .passwordField:
            return String(
                localized: "Typed content and visual evidence were withheld while a password field was focused.",
                table: "Common"
            )
        case .excludedApplication:
            return String(
                localized: "Visual evidence was withheld because this app is excluded by your privacy settings.",
                table: "Common"
            )
        case .excludedWindow:
            return String(
                localized: "Visual evidence was withheld because this window matches a privacy exclusion.",
                table: "Common"
            )
        case .excludedDomain:
            return String(
                localized: "Visual evidence was withheld because this domain is excluded by your privacy settings.",
                table: "Common"
            )
        case .privateRegion:
            return String(
                localized: "This region was marked private, so its visual evidence was withheld.",
                table: "Common"
            )
        case .oversizedArtifact:
            return String(
                localized: "This visual artifact exceeded the configured storage limit and was not retained.",
                table: "Common"
            )
        case .userDeleted:
            return String(
                localized: "This visual evidence was removed by the user and remains marked as deleted.",
                table: "Common"
            )
        case .unknown:
            return String(
                localized: "This context was protected, so the unavailable evidence is shown explicitly instead of being inferred.",
                table: "Common"
            )
        }
    }
}

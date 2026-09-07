import Foundation
import SparkleRecorderCore

enum SemanticRecordingCLIPresentation {
    static func readinessFollowUps(
        _ readiness: SemanticRecordingBundleReadiness
    ) -> [String] {
        let codes = readiness.issues.map(\.code)
        var followUps: [String] = []

        func add(_ followUp: String) {
            guard !followUps.contains(followUp) else { return }
            followUps.append(followUp)
        }

        if codes.contains(.missingVideoSegment) ||
            codes.contains(.frameMissingVideoSegment) ||
            codes.contains(.frameMissingVideoTime) {
            add("Rerun semantic-recording debug-smoke without --keyframes-only and inspect video/segments.json plus frames/index.jsonl.")
        }
        if codes.contains(.missingKeyframe) ||
            codes.contains(.timelineEventMissingFrame) ||
            codes.contains(.semanticEventMissingFrame) {
            add("Inspect frames/index.jsonl and timeline.jsonl; verify event-aligned keyframes are written around recorded events.")
        }
        if codes.contains(.missingTimelineEvent) ||
            codes.contains(.missingAISafeEvent) {
            add("Inspect timeline.jsonl and events.jsonl; verify the recorder emitted playable events before finish.")
        }
        if codes.contains(.missingOCRObservation) {
            add("Rerun on a safe text-bearing target with Screen Recording allowed, then inspect ocr/observations.jsonl.")
        }
        if codes.contains(.missingWindowOrAXObservation) {
            add("Grant Accessibility and target a real window with --window-id or --app-bundle-id, then inspect window/AX observations.")
        }
        if codes.contains(.redactingSuppressionMissingFrameRedaction) ||
            codes.contains(.redactingSuppressionMissingVideoRedaction) {
            add("Inspect redacted/frames/index.json and redacted/video/index.json; rerun with --synthetic-redaction on safe content if the redaction renderer needs rehearsal.")
        }
        if codes.contains(.redactingSuppressionHasNoVisualEvidence) {
            add("Inspect suppressed.jsonl, frames/index.jsonl and video/segments.json; verify the sensitive suppression overlaps captured visual evidence.")
        }
        if codes.contains(.invalidBundle) {
            add("Run recording show with the finished bundle path and inspect manifest plus sidecar reference consistency.")
        }

        return followUps
    }

    static func sidecarKindSummary(
        _ kinds: [SemanticRecordingBundleSidecarKind]
    ) -> String {
        guard !kinds.isEmpty else {
            return "none"
        }
        return kinds
            .map(\.rawValue)
            .joined(separator: ", ")
    }

    static func failedSidecarSummary(
        _ issues: [SemanticRecordingBundleSidecarLoadIssue]
    ) -> String {
        guard !issues.isEmpty else {
            return "none"
        }
        return issues
            .map { issue in
                "\(issue.kind.rawValue)=failed path=\(issue.relativePath) fallback=\(issue.fallbackToManifest)"
            }
            .joined(separator: " | ")
    }
}

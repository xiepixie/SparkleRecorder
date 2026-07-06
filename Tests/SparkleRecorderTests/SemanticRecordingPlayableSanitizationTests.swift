import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Playable Sanitization Tests")
struct SemanticRecordingPlayableSanitizationTests {
    @Test("Time range suppression removes readable key text while preserving key playback")
    func timeRangeSuppressionRemovesReadableKeyText() {
        let recordingID = uuid("7E000000-0000-0000-0000-000000000001")
        let suppressionID = uuid("7E000000-0000-0000-0000-000000000002")
        let events = [
            recordedEvent(
                .keyDown,
                time: 1.0,
                keyCode: 21,
                unicodeString: "4",
                behaviorGroupName: "Card digit"
            ),
            recordedEvent(.keyUp, time: 1.05, keyCode: 21)
        ]
        let bundle = bundle(
            id: recordingID,
            suppressions: [
                RecordingSuppressionRecord(
                    id: suppressionID,
                    reason: .passwordField,
                    timeRange: RecordingTimeRange(startTime: 0.9, duration: 0.2)
                )
            ]
        )

        let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
            for: events,
            bundle: bundle
        )
        let sanitized = plan.sanitizedEvents(from: events)
        let automaticSanitized = plan.playbackPreservingSanitizedEvents(from: events)
        let summary = plan.summary(appliedAt: Date(timeIntervalSince1970: 1_800_000_500))

        #expect(plan.recordingID == recordingID)
        #expect(plan.preservesPlaybackInput)
        #expect(plan.playbackPreservingEventSanitizations.map(\.eventIndex) == [0])
        #expect(plan.reviewRequiredEventSanitizations.isEmpty)
        #expect(plan.eventSanitizations.count == 1)
        #expect(plan.eventSanitizations.first?.eventIndex == 0)
        #expect(plan.eventSanitizations.first?.reasons == [.passwordField])
        #expect(plan.eventSanitizations.first?.sourceSuppressionIDs == [suppressionID])
        #expect(plan.eventSanitizations.first?.redactedFields == [
            .unicodeString,
            .behaviorGroupName
        ])
        #expect(plan.eventSanitizations.first?.fallback == "Replay can keep using key codes; readable text metadata is withheld.")
        #expect(sanitized[0].unicodeString == nil)
        #expect(sanitized[0].behaviorGroupName == nil)
        #expect(sanitized[0].keyCode == 21)
        #expect(sanitized[0].kind == .keyDown)
        #expect(sanitized[1] == events[1])
        #expect(automaticSanitized == sanitized)
        #expect(summary.recordingID == recordingID)
        #expect(summary.sanitizedEventCount == 1)
        #expect(summary.withheldReadableFieldCount == 2)
        #expect(summary.reviewRequiredEventCount == 0)
        #expect(summary.reviewRequiredFieldCount == 0)
    }

    @Test("Timeline event suppression redacts text anchor and requires reviewed playback mutation")
    func timelineEventSuppressionRedactsTextAnchor() throws {
        let recordingID = uuid("7F000000-0000-0000-0000-000000000001")
        let timelineEventID = uuid("7F000000-0000-0000-0000-000000000002")
        let frameID = uuid("7F000000-0000-0000-0000-000000000003")
        let suppressionID = uuid("7F000000-0000-0000-0000-000000000004")
        let events = [
            recordedEvent(
                .waitForText,
                time: 2.4,
                textAnchor: TextAnchor(
                    text: "One-time password",
                    observedFrame: RectValue(x: 10, y: 20, width: 140, height: 32)
                ),
                behaviorGroupName: "Wait for OTP"
            )
        ]
        let bundle = bundle(
            id: recordingID,
            timelineEvents: [
                RecordingTimelineEvent(
                    id: timelineEventID,
                    recordingTime: 2.41,
                    kind: .recordedEvent,
                    frameID: frameID,
                    recordedEventIndex: 0
                )
            ],
            suppressions: [
                RecordingSuppressionRecord(
                    id: suppressionID,
                    reason: .excludedDomain,
                    eventID: timelineEventID
                )
            ]
        )

        let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
            for: events,
            bundle: bundle
        )
        let sanitized = plan.sanitizedEvents(from: events)
        let automaticSanitized = plan.playbackPreservingSanitizedEvents(from: events)
        let summary = plan.summary(appliedAt: Date(timeIntervalSince1970: 1_800_000_600))

        let eventPlan = try #require(plan.eventSanitizations.first)
        #expect(plan.preservesPlaybackInput == false)
        #expect(plan.playbackPreservingEventSanitizations.isEmpty)
        #expect(plan.reviewRequiredEventSanitizations.map(\.eventIndex) == [0])
        #expect(eventPlan.timelineEventID == timelineEventID)
        #expect(eventPlan.frameID == frameID)
        #expect(eventPlan.redactedFields == [.textAnchorText, .behaviorGroupName])
        #expect(eventPlan.preservesPlaybackInput == false)
        #expect(eventPlan.fallback == "Keep the original playable macro for execution until a reviewed replacement is accepted.")
        #expect(sanitized[0].textAnchor?.text == "")
        #expect(sanitized[0].textAnchor?.observedFrame == RectValue(x: 10, y: 20, width: 140, height: 32))
        #expect(sanitized[0].behaviorGroupName == nil)
        #expect(sanitized[0].kind == .waitForText)
        #expect(automaticSanitized == events)
        #expect(summary.sanitizedEventCount == 0)
        #expect(summary.withheldReadableFieldCount == 0)
        #expect(summary.reviewRequiredEventCount == 1)
        #expect(summary.reviewRequiredFieldCount == 2)
    }

    @Test("Retention-only and unmatched suppressions do not sanitize playable text")
    func retentionOnlyAndUnmatchedSuppressionsDoNotSanitizePlayableText() {
        let events = [
            recordedEvent(.keyDown, time: 1.0, keyCode: 0, unicodeString: "a"),
            recordedEvent(
                .verifyText,
                time: 3.0,
                textAnchor: TextAnchor(
                    text: "Done",
                    observedFrame: RectValue(x: 0, y: 0, width: 10, height: 10)
                )
            )
        ]
        let bundle = bundle(
            suppressions: [
                RecordingSuppressionRecord(
                    id: uuid("7F100000-0000-0000-0000-000000000001"),
                    reason: .oversizedArtifact,
                    timeRange: RecordingTimeRange(startTime: 0.9, duration: 0.2)
                ),
                RecordingSuppressionRecord(
                    id: uuid("7F100000-0000-0000-0000-000000000002"),
                    reason: .secureInput,
                    timeRange: RecordingTimeRange(startTime: 4.0, duration: 0.2)
                )
            ]
        )

        let plan = SemanticRecordingPlayableSanitizationPlanner.plan(
            for: events,
            bundle: bundle
        )

        #expect(plan.isEmpty)
        #expect(plan.sanitizedEvents(from: events) == events)
    }

    private func bundle(
        id: UUID? = nil,
        timelineEvents: [RecordingTimelineEvent] = [],
        suppressions: [RecordingSuppressionRecord] = []
    ) -> SemanticRecordingBundle {
        SemanticRecordingBundle(
            id: id ?? uuid("7E100000-0000-0000-0000-000000000001"),
            createdAt: Date(timeIntervalSince1970: 1_800_000_400),
            capturePolicy: RecordingCapturePolicy(mode: .keyframesOnly),
            captureTarget: RecordingCaptureTarget(kind: .window),
            timelineEvents: timelineEvents,
            suppressions: suppressions
        )
    }

    private func recordedEvent(
        _ kind: RecordedEvent.Kind,
        time: TimeInterval,
        keyCode: UInt16 = 0,
        unicodeString: String? = nil,
        textAnchor: TextAnchor? = nil,
        behaviorGroupName: String? = nil
    ) -> RecordedEvent {
        RecordedEvent(
            kind: kind,
            time: time,
            x: 0,
            y: 0,
            keyCode: keyCode,
            flags: 0,
            mouseButton: 0,
            clickCount: 0,
            scrollDeltaY: 0,
            scrollDeltaX: 0,
            unicodeString: unicodeString,
            textAnchor: textAnchor,
            behaviorGroupName: behaviorGroupName
        )
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return uuid
    }
}

import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Redaction Tests")
struct SemanticRecordingRedactionTests {
    @Test("Planner uses observation bounds for localized frame masks and video ranges")
    func plannerUsesObservationBoundsForLocalizedFrameMasksAndVideoRanges() throws {
        let recordingID = uuid("7E000000-0000-0000-0000-000000000001")
        let videoID = uuid("7E000000-0000-0000-0000-000000000002")
        let frameID = uuid("7E000000-0000-0000-0000-000000000003")
        let eventID = uuid("7E000000-0000-0000-0000-000000000004")
        let observationID = uuid("7E000000-0000-0000-0000-000000000005")
        let suppressionID = uuid("7E000000-0000-0000-0000-000000000006")
        let maskBounds = RecordingBounds(
            rect: RecordingRect(x: 20, y: 40, width: 180, height: 30),
            coordinateSpace: .windowPixels
        )
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            videoSegments: [
                RecordingVideoSegment(
                    id: videoID,
                    artifactRef: try RecordingArtifactRef("video/recording.mov"),
                    startTime: 0,
                    duration: 5
                )
            ],
            frames: [
                RecordingFrameReference(
                    id: frameID,
                    recordingTime: 1.2,
                    videoSegmentID: videoID,
                    videoTime: 1.2,
                    imageRef: try RecordingArtifactRef("frames/000001-text.png"),
                    imageSize: RecordingImageSize(width: 800, height: 600),
                    source: .textInput,
                    relatedEventIDs: [eventID]
                )
            ],
            timelineEvents: [
                RecordingTimelineEvent(
                    id: eventID,
                    recordingTime: 1.2,
                    kind: .recordedEvent,
                    frameID: frameID
                )
            ],
            visualObservations: [
                RecordingVisualObservation(
                    id: observationID,
                    kind: .ocrText,
                    recordingTime: 1.2,
                    frameID: frameID,
                    bounds: maskBounds,
                    text: "secret",
                    provider: "Vision.fake"
                )
            ],
            suppressions: [
                RecordingSuppressionRecord(
                    id: suppressionID,
                    reason: .passwordField,
                    recordingTime: 1.2,
                    timeRange: RecordingTimeRange(startTime: 1.0, duration: 0.5),
                    frameID: frameID,
                    eventID: eventID
                )
            ]
        )

        let plan = SemanticRecordingRedactionPlanner.plan(for: bundle)

        #expect(!plan.isEmpty)
        #expect(plan.recordingID == recordingID)
        #expect(plan.frameRedactions.count == 1)
        let frameRedaction = try #require(plan.frameRedactions.first)
        #expect(frameRedaction.frameID == frameID)
        #expect(frameRedaction.sourceImageRef.path == "frames/000001-text.png")
        #expect(frameRedaction.redactedImageRef.path == "redacted/frames/\(frameID.uuidString.lowercased()).png")
        #expect(frameRedaction.sourceSuppressionIDs == [suppressionID])
        #expect(frameRedaction.masks == [
            SemanticRecordingRedactionMask(
                bounds: maskBounds,
                reason: .passwordField,
                sourceSuppressionID: suppressionID,
                sourceObservationID: observationID
            )
        ])

        #expect(plan.videoRangeRedactions == [
            SemanticRecordingVideoRangeRedaction(
                videoSegmentID: videoID,
                timeRange: RecordingTimeRange(startTime: 1.0, duration: 0.5),
                sourceSuppressionIDs: [suppressionID],
                reasons: [.passwordField]
            )
        ])
    }

    @Test("Planner falls back to full frame masks when no observation bounds exist")
    func plannerFallsBackToFullFrameMasksWhenNoObservationBoundsExist() throws {
        let recordingID = uuid("7E000000-0000-0000-0000-000000000101")
        let frameID = uuid("7E000000-0000-0000-0000-000000000102")
        let suppressionID = uuid("7E000000-0000-0000-0000-000000000103")
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            frames: [
                RecordingFrameReference(
                    id: frameID,
                    recordingTime: 2.0,
                    imageRef: try RecordingArtifactRef("frames/000002-secure.png"),
                    imageSize: RecordingImageSize(width: 640, height: 480),
                    source: .manual
                )
            ],
            suppressions: [
                RecordingSuppressionRecord(
                    id: suppressionID,
                    reason: .excludedWindow,
                    frameID: frameID
                )
            ]
        )

        let plan = SemanticRecordingRedactionPlanner.plan(for: bundle)

        let redaction = try #require(plan.frameRedactions.first)
        #expect(redaction.masks == [
            SemanticRecordingRedactionMask(
                bounds: RecordingBounds(
                    rect: RecordingRect(x: 0, y: 0, width: 640, height: 480),
                    coordinateSpace: .framePixels
                ),
                reason: .excludedWindow,
                sourceSuppressionID: suppressionID
            )
        ])
        #expect(plan.videoRangeRedactions.isEmpty)
    }

    @Test("Planner ignores record-only suppression reasons")
    func plannerIgnoresRecordOnlySuppressionReasons() throws {
        let recordingID = uuid("7E000000-0000-0000-0000-000000000201")
        let frameID = uuid("7E000000-0000-0000-0000-000000000202")
        let suppressionID = uuid("7E000000-0000-0000-0000-000000000203")
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            frames: [
                RecordingFrameReference(
                    id: frameID,
                    recordingTime: 2.0,
                    imageRef: try RecordingArtifactRef("frames/000003-large.png"),
                    imageSize: RecordingImageSize(width: 640, height: 480),
                    source: .manual
                )
            ],
            suppressions: [
                RecordingSuppressionRecord(
                    id: suppressionID,
                    reason: .oversizedArtifact,
                    frameID: frameID
                )
            ]
        )

        let plan = SemanticRecordingRedactionPlanner.plan(for: bundle)

        #expect(plan.isEmpty)
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return uuid
    }
}

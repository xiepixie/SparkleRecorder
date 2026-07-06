import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Bundle Readiness Tests")
struct SemanticRecordingBundleReadinessTests {
    @Test("Complete fixture with redaction sidecars is ready for OCR-backed review")
    func completeFixtureWithRedactionSidecarsIsReady() throws {
        var bundle = SemanticRecordingFixture.checkoutBundle()
        bundle.redactedFrames = [
            SemanticRecordingRenderedFrameRedaction(
                frameID: SemanticRecordingFixture.startFrameID,
                sourceImageRef: try RecordingArtifactRef("frames/000001-start.png"),
                redactedImageRef: try RecordingArtifactRef("redacted/frames/start.png"),
                renderedMaskCount: 1,
                sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID]
            )
        ]
        bundle.redactedVideos = [
            SemanticRecordingRenderedVideoRedaction(
                videoSegmentID: SemanticRecordingFixture.videoSegmentID,
                sourceVideoRef: try RecordingArtifactRef("video/recording.mov"),
                redactedVideoRef: try RecordingArtifactRef("redacted/video/recording.mov"),
                renderedRangeCount: 1,
                sourceSuppressionIDs: [SemanticRecordingFixture.suppressionID],
                reasons: [.passwordField]
            )
        ]

        let readiness = SemanticRecordingBundleReadiness.evaluate(
            bundle,
            policy: SemanticRecordingBundleReadinessPolicy(
                capturePolicy: bundle.capturePolicy,
                requiresOCRObservations: true
            )
        )

        #expect(readiness.recordingID == bundle.id)
        #expect(readiness.status == .ready)
        #expect(readiness.issues.isEmpty)
    }

    @Test("Sensitive suppression requires redacted frame and video sidecars")
    func sensitiveSuppressionRequiresRenderedRedactionSidecars() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()

        let readiness = SemanticRecordingBundleReadiness.evaluate(
            bundle,
            policy: SemanticRecordingBundleReadinessPolicy(
                capturePolicy: bundle.capturePolicy,
                requiresOCRObservations: true,
                requiresWindowOrAXObservations: true
            )
        )

        #expect(readiness.status == .notReady)
        #expect(readiness.blockingIssueCount == 2)
        #expect(readiness.degradedIssueCount == 1)
        #expect(readiness.issues.contains {
            $0.code == .redactingSuppressionMissingFrameRedaction &&
                $0.frameID == SemanticRecordingFixture.startFrameID &&
                $0.suppressionID == SemanticRecordingFixture.suppressionID
        })
        #expect(readiness.issues.contains {
            $0.code == .redactingSuppressionMissingVideoRedaction &&
                $0.videoSegmentID == SemanticRecordingFixture.videoSegmentID &&
                $0.suppressionID == SemanticRecordingFixture.suppressionID
        })
        #expect(readiness.issues.contains {
            $0.code == .missingWindowOrAXObservation &&
                $0.severity == .degraded
        })

        let encoded = try JSONEncoder().encode(readiness)
        let decoded = try JSONDecoder().decode(
            SemanticRecordingBundleReadiness.self,
            from: encoded
        )
        #expect(decoded == readiness)
    }

    @Test("Keyframes-only bundles do not require video segment linkage")
    func keyframesOnlyBundlesDoNotRequireVideoSegmentLinkage() throws {
        let frameID = try #require(UUID(uuidString: "8D000000-0000-0000-0000-000000000001"))
        let eventID = try #require(UUID(uuidString: "8D000000-0000-0000-0000-000000000002"))
        let semanticEventID = try #require(UUID(uuidString: "8D000000-0000-0000-0000-000000000003"))
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 0.5,
            imageRef: try RecordingArtifactRef("frames/000001.png"),
            source: .recordingStart,
            relatedEventIDs: [eventID]
        )
        let event = RecordingTimelineEvent(
            id: eventID,
            recordingTime: 0.5,
            kind: .recordedEvent,
            frameID: frameID
        )
        let semanticEvent = RecordingSemanticEvent(
            id: semanticEventID,
            recordingTime: 0.5,
            kind: .click,
            frameID: frameID,
            timelineEventID: eventID,
            title: "Click"
        )
        let bundle = SemanticRecordingBundle(
            capturePolicy: RecordingCapturePolicy(mode: .keyframesOnly),
            frames: [frame],
            timelineEvents: [event],
            semanticEvents: [semanticEvent]
        )

        let readiness = SemanticRecordingBundleReadiness.evaluate(bundle)

        #expect(readiness.status == .ready)
        #expect(readiness.issues.isEmpty)
    }

    @Test("Video bundles require frame-to-video alignment")
    func videoBundlesRequireFrameToVideoAlignment() throws {
        let videoID = try #require(UUID(uuidString: "8E000000-0000-0000-0000-000000000001"))
        let frameID = try #require(UUID(uuidString: "8E000000-0000-0000-0000-000000000002"))
        let eventID = try #require(UUID(uuidString: "8E000000-0000-0000-0000-000000000003"))
        let semanticEventID = try #require(UUID(uuidString: "8E000000-0000-0000-0000-000000000004"))
        let segment = RecordingVideoSegment(
            id: videoID,
            artifactRef: try RecordingArtifactRef("video/recording.mov"),
            startTime: 0,
            duration: 2
        )
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 0.5,
            imageRef: try RecordingArtifactRef("frames/000001.png"),
            source: .mouseUp,
            relatedEventIDs: [eventID]
        )
        let event = RecordingTimelineEvent(
            id: eventID,
            recordingTime: 0.5,
            kind: .recordedEvent,
            frameID: frameID,
            videoSegmentID: videoID
        )
        let semanticEvent = RecordingSemanticEvent(
            id: semanticEventID,
            recordingTime: 0.5,
            kind: .click,
            frameID: frameID,
            timelineEventID: eventID,
            title: "Click"
        )
        let bundle = SemanticRecordingBundle(
            videoSegments: [segment],
            frames: [frame],
            timelineEvents: [event],
            semanticEvents: [semanticEvent]
        )

        let readiness = SemanticRecordingBundleReadiness.evaluate(bundle)

        #expect(readiness.status == .notReady)
        #expect(readiness.issues.contains {
            $0.code == .frameMissingVideoSegment &&
                $0.frameID == frameID
        })
        #expect(readiness.issues.contains {
            $0.code == .frameMissingVideoTime &&
                $0.frameID == frameID
        })
    }
}

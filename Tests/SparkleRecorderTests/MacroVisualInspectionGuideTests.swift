import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Macro Visual Inspection Guide Tests")
struct MacroVisualInspectionGuideTests {
    @Test("Aligned click projects seek window and clamped frame search regions")
    func alignedClickProjectsNavigationHints() throws {
        let segmentID = UUID()
        let frameID = UUID()
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0, x: 600, y: 450),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 600, y: 450)
        ]
        events.indices.forEach { events[$0].surfaceId = "surface-1" }
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 100,
            sessionEndTime: 4,
            sourceEvents: [
                .init(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 2),
                .init(sourceEventIndex: 1, sourcePlaybackTime: 0.1, sessionTime: 2.1)
            ],
            clockSegments: [
                .init(
                    id: segmentID.uuidString,
                    anchors: [
                        .init(recordingTime: 1, videoTime: 0),
                        .init(recordingTime: 4, videoTime: 3)
                    ],
                    maximumError: 0
                )
            ],
            geometrySnapshots: [
                .init(
                    surfaceID: "surface-1",
                    recordingTime: 1,
                    validUntil: 4,
                    captureBounds: RectValue(x: 100, y: 200, width: 1_000, height: 500),
                    frameSize: RecordingImageSize(width: 2_000, height: 1_000)
                )
            ],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: events)
        )
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 2.05,
            videoSegmentID: segmentID,
            videoTime: 1.05,
            imageRef: try RecordingArtifactRef("frames/source.png"),
            imageSize: RecordingImageSize(width: 2_000, height: 1_000),
            source: .mouseUp,
            surfaceID: "surface-1"
        )
        let guide = try MacroVisualInspectionGuideProjector.project(
            events: events,
            sourceRevision: "source",
            provenance: provenance,
            videoSegments: [
                RecordingVideoSegment(
                    id: segmentID,
                    artifactRef: try RecordingArtifactRef("video/source.mov"),
                    startTime: 0,
                    duration: 3,
                    frameSize: RecordingImageSize(width: 2_000, height: 1_000)
                )
            ],
            frames: [frame],
            exportedVideoPaths: [segmentID: "video/\(segmentID.uuidString).mov"],
            exportedFramePaths: [frameID: "frames/\(frameID.uuidString).png"]
        )

        guard let action = guide.actions.first,
              let video = action.video,
              let focus = action.focuses.first else {
            Issue.record("Expected aligned visual navigation for the click action")
            return
        }
        #expect(action.kind == "click")
        #expect(abs((action.sessionRange?.startTime ?? -1) - 2) < 0.000_001)
        #expect(abs((action.sessionRange?.duration ?? -1) - 0.1) < 0.000_001)
        #expect(abs(video.actionVideoRange.startTime - 1) < 0.000_001)
        #expect(abs(video.actionVideoRange.duration - 0.1) < 0.000_001)
        #expect(abs(video.inspectionVideoRange.startTime - 0.75) < 0.000_001)
        #expect(abs(video.inspectionVideoRange.duration - 1.10) < 0.000_001)
        #expect(focus.role == MacroVisualInspectionFocusRole.target)
        #expect(focus.framePoint == PointValue(x: 1_000, y: 500))
        #expect(focus.primaryRegion.framePixels.rect == RecordingRect(x: 760, y: 400, width: 480, height: 200))
        #expect(focus.primaryRegion.normalizedFrame.rect == RecordingRect(x: 0.38, y: 0.4, width: 0.24, height: 0.2))
        #expect(focus.contextRegion.framePixels.rect == RecordingRect(x: 440, y: 280, width: 1_120, height: 440))
        #expect(action.frames.map { $0.frameID } == [frameID])
    }

    @Test("Action-local visual observations stay bounded while preserving the total evidence count")
    func observationSummariesAreBounded() throws {
        let frameID = UUID()
        var events = [
            RecordedEvent.make(.leftMouseDown, time: 0, x: 100, y: 120),
            RecordedEvent.make(.leftMouseUp, time: 0.1, x: 100, y: 120)
        ]
        events.indices.forEach { events[$0].surfaceId = "surface-1" }
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 1,
            sessionEndTime: 3,
            sourceEvents: [
                .init(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 1),
                .init(sourceEventIndex: 1, sourcePlaybackTime: 0.1, sessionTime: 1.1)
            ]
        )
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 1.05,
            imageRef: try RecordingArtifactRef("frames/source.png"),
            imageSize: RecordingImageSize(width: 1_000, height: 600),
            source: .mouseUp,
            surfaceID: "surface-1"
        )
        let observations = (0..<7).map { index in
            RecordingVisualObservation(
                kind: .ocrText,
                recordingTime: 1.02 + Double(index) * 0.001,
                frameID: frameID,
                text: String(repeating: "x", count: 30),
                confidence: 0.9,
                provider: "test",
                labels: ["one", "two", "three", "four"]
            )
        }
        let policy = MacroVisualInspectionPolicy(
            maximumObservationSummaries: 3,
            maximumObservationTextCharacters: 10,
            maximumObservationLabels: 2
        )
        let guide = try MacroVisualInspectionGuideProjector.project(
            events: events,
            sourceRevision: "source",
            provenance: provenance,
            videoSegments: [],
            frames: [frame],
            observations: observations,
            exportedVideoPaths: [:],
            exportedFramePaths: [frameID: "frames/\(frameID.uuidString).png"],
            policy: policy
        )

        let action = try #require(guide.actions.first)
        #expect(action.observationCount == 7)
        #expect(action.observations.count == 3)
        #expect(action.observations.allSatisfy { $0.text == "xxxxxxxxxx..." })
        #expect(action.observations.allSatisfy { $0.labels == ["one", "two"] })
        #expect(guide.policy.maximumObservationSummaries == 3)
        #expect(guide.policy.maximumObservationTextCharacters == 10)
        #expect(guide.policy.maximumObservationLabels == 2)
    }

    @Test("Search regions stay inside small frames and never invent unavailable visual mapping")
    func regionsClampAndMissingEvidenceStaysUnavailable() throws {
        var event = RecordedEvent.make(.leftMouseDown, time: 0, x: 9, y: 9)
        event.surfaceId = "surface-1"
        let events = [event]
        let provenance = RecordingReconstructionProvenance(
            sessionOriginHostTime: 1,
            sessionEndTime: 1,
            sourceEvents: [.init(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 0)],
            geometrySnapshots: [
                .init(
                    surfaceID: "surface-1",
                    recordingTime: 0,
                    validUntil: 1,
                    captureBounds: RectValue(x: 0, y: 0, width: 10, height: 10),
                    frameSize: RecordingImageSize(width: 200, height: 100)
                )
            ],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: events)
        )
        let guide = try MacroVisualInspectionGuideProjector.project(
            events: events,
            sourceRevision: "source",
            provenance: provenance,
            videoSegments: [],
            frames: [],
            exportedVideoPaths: [:],
            exportedFramePaths: [:]
        )

        guard let action = guide.actions.first,
              let focus = action.focuses.first else {
            Issue.record("Expected geometry-only focus guidance")
            return
        }
        #expect(action.video == nil)
        #expect(action.frames.isEmpty)
        #expect(action.issues.contains(MacroReconstructionProjectionIssue.videoUnavailable.rawValue))
        #expect(focus.primaryRegion.framePixels.rect == RecordingRect(x: 0, y: 0, width: 200, height: 100))
        #expect(focus.primaryRegion.normalizedFrame.rect == RecordingRect(x: 0, y: 0, width: 1, height: 1))
        #expect(focus.contextRegion.normalizedFrame.rect == RecordingRect(x: 0, y: 0, width: 1, height: 1))
    }
}

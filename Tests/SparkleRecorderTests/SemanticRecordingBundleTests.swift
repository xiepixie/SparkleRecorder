import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite("Semantic Recording Bundle Tests")
struct SemanticRecordingBundleTests {
    @Test("Checkout fixture is valid and reusable by next workstreams")
    func checkoutFixtureIsValidAndReusableByNextWorkstreams() throws {
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let queryResults = SemanticRecordingFixture.checkoutQueryResults(bundle: bundle)
        let suggestions = SemanticRecordingFixture.checkoutSuggestions(bundle: bundle)

        assertSendable(bundle)
        #expect(bundle.id == SemanticRecordingFixture.recordingID)
        #expect(bundle.validate().isEmpty)
        #expect(bundle.videoSegments.map(\.id) == [SemanticRecordingFixture.videoSegmentID])
        #expect(bundle.frames.map(\.id).contains(SemanticRecordingFixture.afterClickFrameID))
        #expect(bundle.aiSafeEvents.map(\.id).contains(SemanticRecordingFixture.conditionSemanticEventID))
        #expect(bundle.visualObservations.map(\.id).contains(SemanticRecordingFixture.ocrObservationID))
        #expect(bundle.sourcePreviews.map(\.id).contains(SemanticRecordingFixture.sourceTemplateRefID))
        #expect(bundle.runtimeSamples.map(\.id) == [SemanticRecordingFixture.runtimeSampleID])
        #expect(bundle.previewComparisons.map(\.id) == [SemanticRecordingFixture.comparisonID])
        #expect(bundle.suppressions.map(\.id) == [SemanticRecordingFixture.suppressionID])
        #expect(bundle.nearestFrame(to: 2.5, within: 0.2)?.id == SemanticRecordingFixture.afterClickFrameID)
        #expect(bundle.frames(relatedToEventID: SemanticRecordingFixture.clickEventID).map(\.id).contains(SemanticRecordingFixture.beforeClickFrameID))
        #expect(bundle.observations(frameID: SemanticRecordingFixture.afterClickFrameID).map(\.id) == [SemanticRecordingFixture.ocrObservationID])
        #expect(bundle.previewComparisons(sourcePreviewRefID: SemanticRecordingFixture.sourceOCRRefID).map(\.id) == [SemanticRecordingFixture.comparisonID])
        #expect(queryResults.first?.evidence.first?.artifactRef?.path == "frames/000016-after-click.png")
        #expect(suggestions.first?.recordingID == bundle.id)
        #expect(suggestions.first?.evidence.first?.observationIDs == [SemanticRecordingFixture.ocrObservationID])

        let encoded = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(SemanticRecordingBundle.self, from: encoded)
        #expect(decoded == bundle)
    }

    @Test("Artifact refs normalize safe relative paths and reject unsafe paths")
    func artifactRefsNormalizeAndRejectUnsafePaths() throws {
        let ref = try RecordingArtifactRef(" frames//000042.png\n")

        #expect(ref.path == "frames/000042.png")

        let encoded = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(RecordingArtifactRef.self, from: encoded)
        #expect(decoded == ref)

        for path in ["", "/tmp/frame.png", "../frame.png", "frames/../secret.png", "file:///tmp/a.png", "https://example.com/a.png", "~/frame.png", "C:\\temp\\a.png"] {
            #expect(throws: Error.self) {
                _ = try RecordingArtifactRef(path)
            }
        }

        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(
                RecordingArtifactRef.self,
                from: Data(#""../secret.png""#.utf8)
            )
        }
    }

    @Test("Bundle aligns video segments, frames, and related events")
    func bundleAlignsVideoSegmentsFramesAndEvents() throws {
        let videoID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        let eventID = UUID(uuidString: "70000000-0000-0000-0000-000000000002")!
        let firstFrameID = UUID(uuidString: "70000000-0000-0000-0000-000000000003")!
        let secondFrameID = UUID(uuidString: "70000000-0000-0000-0000-000000000004")!
        let segment = RecordingVideoSegment(
            id: videoID,
            artifactRef: try RecordingArtifactRef("video/recording.mov"),
            startTime: 0,
            duration: 8,
            target: RecordingCaptureTarget(
                kind: .window,
                surfaceID: "checkout-window",
                appBundleIdentifier: "com.example.Checkout"
            )
        )
        let firstFrame = RecordingFrameReference(
            id: firstFrameID,
            recordingTime: 1.25,
            videoSegmentID: videoID,
            videoTime: 1.25,
            imageRef: try RecordingArtifactRef("frames/000001.png"),
            source: .mouseDown,
            surfaceID: "checkout-window",
            relatedEventIDs: [eventID]
        )
        let secondFrame = RecordingFrameReference(
            id: secondFrameID,
            recordingTime: 3.0,
            videoSegmentID: videoID,
            videoTime: 3.0,
            imageRef: try RecordingArtifactRef("frames/000002.png"),
            source: .mouseUp,
            surfaceID: "checkout-window",
            relatedEventIDs: [eventID]
        )
        let bundle = SemanticRecordingBundle(
            videoSegments: [segment],
            frames: [firstFrame, secondFrame]
        )

        #expect(bundle.validate().isEmpty)
        #expect(bundle.videoSegment(containing: 2.0)?.id == videoID)
        #expect(bundle.videoSegment(containing: 9.0) == nil)
        #expect(bundle.nearestFrame(to: 2.85, within: 0.2)?.id == secondFrameID)
        #expect(bundle.nearestFrame(to: 2.85, within: 0.1) == nil)
        #expect(bundle.frames(relatedToEventID: eventID).map(\.id) == [firstFrameID, secondFrameID])
    }

    @Test("Preview refs round-trip source, runtime sample, and comparison semantics")
    func previewRefsRoundTripSourceRuntimeSampleAndComparisonSemantics() throws {
        let recordingID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
        let frameID = UUID(uuidString: "71000000-0000-0000-0000-000000000002")!
        let eventID = UUID(uuidString: "71000000-0000-0000-0000-000000000003")!
        let sourceID = UUID(uuidString: "71000000-0000-0000-0000-000000000004")!
        let runID = UUID(uuidString: "71000000-0000-0000-0000-000000000005")!
        let taskID = UUID(uuidString: "71000000-0000-0000-0000-000000000006")!
        let conditionID = UUID(uuidString: "71000000-0000-0000-0000-000000000007")!
        let sampleID = UUID(uuidString: "71000000-0000-0000-0000-000000000008")!
        let comparisonID = UUID(uuidString: "71000000-0000-0000-0000-000000000009")!
        let bounds = RecordingBounds(
            rect: RecordingRect(x: 120, y: 80, width: 220, height: 60),
            coordinateSpace: .windowPixels
        )
        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 2.4,
            imageRef: try RecordingArtifactRef("frames/000024.png"),
            imageSize: RecordingImageSize(width: 1_440, height: 900),
            source: .mouseUp,
            surfaceID: "checkout-window",
            windowBounds: bounds
        )
        let event = RecordingTimelineEvent(
            id: eventID,
            recordingTime: 2.4,
            kind: .recordedEvent,
            frameID: frameID,
            surfaceID: "checkout-window",
            summary: "Clicked checkout button"
        )
        let source = RecordingSourcePreviewReference(
            id: sourceID,
            kind: .imageTemplate,
            recordingID: recordingID,
            frameID: frameID,
            eventID: eventID,
            surfaceID: "checkout-window",
            artifactRef: try RecordingArtifactRef("visual-index/templates/checkout-button.png"),
            bounds: bounds,
            imageSize: RecordingImageSize(width: 220, height: 60),
            createdAt: Date(timeIntervalSince1970: 10),
            recordingTime: 2.4,
            contentDigest: RecordingContentDigest(algorithm: "sha256", value: "abc123"),
            label: "Checkout button"
        )
        let sample = RecordingRuntimeSampleReference(
            id: sampleID,
            kind: .watchedRegionCrop,
            runID: runID,
            taskID: taskID,
            conditionID: conditionID,
            artifactRef: try RecordingArtifactRef("runs/run-1/condition-1/watched-region.png"),
            capturedAt: Date(timeIntervalSince1970: 20),
            bounds: bounds,
            imageSize: RecordingImageSize(width: 220, height: 60)
        )
        let comparison = RecordingPreviewComparison(
            id: comparisonID,
            sourcePreviewRefID: sourceID,
            runtimeSampleRefID: sampleID,
            outcome: .matched,
            score: 0.94,
            threshold: 0.88,
            matcher: RecordingMatcherDescriptor(
                kind: "template-ncc",
                version: "0.1",
                provider: "SparkleRecorder"
            ),
            diffArtifactRef: try RecordingArtifactRef("runs/run-1/condition-1/diff.png"),
            reason: "Template matched above threshold",
            comparedAt: Date(timeIntervalSince1970: 21)
        )
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            frames: [frame],
            timelineEvents: [event],
            sourcePreviews: [source],
            runtimeSamples: [sample],
            previewComparisons: [comparison]
        )

        #expect(bundle.validate().isEmpty)

        let encoded = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(SemanticRecordingBundle.self, from: encoded)

        #expect(decoded == bundle)
        #expect(decoded.sourcePreviews.first?.artifactRef?.path == "visual-index/templates/checkout-button.png")
        #expect(decoded.runtimeSamples.first?.artifactRef.path == "runs/run-1/condition-1/watched-region.png")
        #expect(decoded.previewComparisons.first?.outcome == .matched)
        #expect(decoded.previewComparisons.first?.matcher.version == "0.1")
        #expect(decoded.previewComparisons(sourcePreviewRefID: sourceID).map(\.id) == [comparisonID])
    }

    @Test("Bundle validation reports dangling preview comparison references")
    func bundleValidationReportsDanglingPreviewComparisonReferences() throws {
        let sourceID = UUID(uuidString: "72000000-0000-0000-0000-000000000001")!
        let sampleID = UUID(uuidString: "72000000-0000-0000-0000-000000000002")!
        let comparisonID = UUID(uuidString: "72000000-0000-0000-0000-000000000003")!
        let comparison = RecordingPreviewComparison(
            id: comparisonID,
            sourcePreviewRefID: sourceID,
            runtimeSampleRefID: sampleID,
            outcome: .missingSource,
            matcher: RecordingMatcherDescriptor(kind: "template-ncc", version: "0.1"),
            reason: "Source preview was missing"
        )
        let bundle = SemanticRecordingBundle(previewComparisons: [comparison])
        let issues = bundle.validate()

        #expect(issues.contains(.comparisonReferencesMissingSource(
            comparisonID: comparisonID,
            sourcePreviewRefID: sourceID
        )))
        #expect(issues.contains(.comparisonReferencesMissingSample(
            comparisonID: comparisonID,
            runtimeSampleRefID: sampleID
        )))
    }

    @Test("Bundle validation reports duplicate IDs and unsupported schema")
    func bundleValidationReportsDuplicateIDsAndUnsupportedSchema() throws {
        #expect(!RecordingCapturePolicy(mode: .keyframesOnly).recordsVideo)
        #expect(RecordingCapturePolicy(mode: .diagnosticRich).recordsVideo)

        let frameID = UUID(uuidString: "73000000-0000-0000-0000-000000000001")!
        let firstFrame = RecordingFrameReference(
            id: frameID,
            recordingTime: 1,
            imageRef: try RecordingArtifactRef("frames/a.png"),
            source: .manual
        )
        let secondFrame = RecordingFrameReference(
            id: frameID,
            recordingTime: 2,
            imageRef: try RecordingArtifactRef("frames/b.png"),
            source: .manual
        )
        let unsupported = SemanticRecordingSchemaVersion(
            major: SemanticRecordingSchema.current.major + 1,
            minor: 0
        )
        let bundle = SemanticRecordingBundle(
            schemaVersion: unsupported,
            frames: [firstFrame, secondFrame]
        )
        let issues = bundle.validate()

        #expect(issues.contains(.duplicateFrameID(frameID)))
        #expect(issues.contains(.unsupportedSchemaVersion(unsupported)))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}

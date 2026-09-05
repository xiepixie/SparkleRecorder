import Foundation
import Testing
@testable import SparkleRecorderCore

@Suite struct RecordingReconstructionProvenanceTests {
    @Test func oldBundleHasNoInventedProvenance() throws {
        let bundle = SemanticRecordingBundle()
        let decoded = try JSONDecoder().decode(SemanticRecordingBundle.self, from: JSONEncoder().encode(bundle))
        #expect(decoded.reconstructionProvenance == nil)
    }

    @Test func sourceIdentityRejectsSameTimeCoordinateAndTextEditsAndLegacyEvidence() throws {
        let event = RecordedEvent(kind: .keyDown, time: 0, x: 1, y: 2, keyCode: 0, flags: 0,
            mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0, unicodeString: "a")
        let provenance = RecordingReconstructionProvenance(sessionOriginHostTime: 100, sessionEndTime: 2,
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: [event]))
        #expect(provenance.matchesSourceEvents([event]))
        var moved = event; moved.x = 100
        #expect(!provenance.matchesSourceEvents([moved]))
        var editedText = event; editedText.unicodeString = "b"
        #expect(!provenance.matchesSourceEvents([editedText]))
        #expect(!provenance.matchesSourceEvents([]))
        let legacy = RecordingReconstructionProvenance(sessionOriginHostTime: 100, sessionEndTime: 2)
        #expect(!legacy.matchesSourceEvents([event]))
        let decoded = try JSONDecoder().decode(RecordingReconstructionProvenance.self,
            from: JSONEncoder().encode(legacy))
        #expect(decoded.sourceEventDigest == nil)
    }

    @Test func delayedFrameAndFinalIdleArePreserved() async throws {
        let client = SemanticRecordingCaptureClient(
            startMovie: { .init(segmentID: $0.segmentID, artifactRef: $0.artifactRef, target: $0.target, startTime: $0.recordingTime) },
            finishMovie: { .init(duration: $0.recordingTime) },
            captureFrame: { request in .init(capturedHostTime: 100 + request.recordingTime + 0.2, timestampUncertainty: 0.02) }
        )
        let session = SemanticRecordingCaptureSession(configuration: .init(sessionOriginHostTime: 100), client: client)
        try await session.start()
        let event = RecordedEvent(kind: .leftMouseDown, time: 0, x: 1, y: 2, keyCode: 0, flags: 0, mouseButton: 0, clickCount: 1, scrollDeltaY: 0, scrollDeltaX: 0)
        try await session.record(event, index: 0, sessionTime: 3)
        let bundle = try await session.finish(recordingTime: 8)
        let provenance = try #require(bundle.reconstructionProvenance)
        #expect(provenance.sessionEndTime == 8)
        #expect(provenance.matchesSourceEvents([event]))
        #expect(provenance.sourceEvents.first?.sessionTime == 3)
        #expect(provenance.sourceEvents.first?.sourcePlaybackTime == 0)
        #expect(abs((bundle.frames.last?.recordingTime ?? 0) - 8.2) < 0.00001)
        #expect(bundle.frames.allSatisfy { $0.videoTime == nil })
        #expect(provenance.clockSegments.isEmpty)
    }
    @Test func incompleteCaptureIndicesCannotBindACompleteSource() async throws {
        let client = SemanticRecordingCaptureClient(
            startMovie: { .init(segmentID: $0.segmentID, artifactRef: $0.artifactRef, target: $0.target, startTime: $0.recordingTime) },
            finishMovie: { .init(duration: $0.recordingTime) }, captureFrame: { _ in .init() })
        let session = SemanticRecordingCaptureSession(configuration: .init(sessionOriginHostTime: 100), client: client)
        try await session.start()
        let event = RecordedEvent(kind: .mouseMoved, time: 0, x: 1, y: 2, keyCode: 0, flags: 0,
            mouseButton: 0, clickCount: 0, scrollDeltaY: 0, scrollDeltaX: 0)
        try await session.record(event, index: 1, sessionTime: 1)
        let bundle = try await session.finish(recordingTime: 2)
        let provenance = try #require(bundle.reconstructionProvenance)
        #expect(provenance.sourceEventDigest == nil)
        #expect(!provenance.matchesSourceEvents([event]))
    }

    @Test func provenanceSurvivesManifestAndSidecars() throws {
        let evidence = RecordingReconstructionProvenance(sessionOriginHostTime: 99, sessionEndTime: 11,
            sourceEvents: [.init(sourceEventIndex: 0, sourcePlaybackTime: 0, sessionTime: 2)],
            movieEvidence: [.init(segmentID: UUID(), fileTrackStartPTS: 0, fileTrackDuration: 8)])
        let bundle = SemanticRecordingBundle(reconstructionProvenance: evidence)
        let decoded = try JSONDecoder().decode(SemanticRecordingBundle.self, from: JSONEncoder().encode(bundle))
        #expect(decoded.reconstructionProvenance == evidence)
        #expect(decoded.applyingSidecars(.init()).reconstructionProvenance == evidence)
        #expect(decoded.reconstructionProvenance?.clockSegments.isEmpty == true)
    }

    @Test func measuredGeometryRequiresDurationAndFullFrame() {
        let sample = RecordingCaptureSampleTiming(presentationTime: 700, displayedHostTime: 102, receivedHostTime: 105,
            duration: 0.02, screenRect: .init(x: 50, y: 60, width: 100, height: 50),
            contentRect: .init(x: 0, y: 0, width: 100, height: 50), imageSize: .init(width: 200, height: 100), displayScale: 2)
        let evidence = RecordingMovieTimingEvidence(segmentID: UUID(), samples: [sample])
        let geometry = RecordingReconstructionProvenance.measuredGeometry(movieEvidence: [evidence], origin: 100, surfaceID: "window")
        #expect(geometry.first?.recordingTime == 2)
        #expect(geometry.first?.validUntil == 2.02)
        var padded = sample
        padded.contentRect = .init(x: 10, y: 0, width: 90, height: 50)
        var missingDuration = sample
        missingDuration.duration = nil
        let unavailable = RecordingReconstructionProvenance.measuredGeometry(movieEvidence: [.init(segmentID: UUID(), samples: [padded, missingDuration])], origin: 100, surfaceID: "window")
        #expect(unavailable.isEmpty)
    }

    @Test func missingFrameTimestampIsExplicitlyUnavailable() async throws {
        let client = SemanticRecordingCaptureClient(
            startMovie: { .init(segmentID: $0.segmentID, artifactRef: $0.artifactRef, target: $0.target, startTime: $0.recordingTime) },
            finishMovie: { .init(duration: $0.recordingTime) }, captureFrame: { _ in .init() })
        let session = SemanticRecordingCaptureSession(configuration: .init(sessionOriginHostTime: 100), client: client)
        try await session.start()
        let bundle = try await session.finish(recordingTime: 10)
        #expect(bundle.reconstructionProvenance?.frameTimings.allSatisfy { $0.capturedSessionTime == nil } == true)
        #expect(bundle.frames.allSatisfy { $0.videoTime == nil })
        #expect(bundle.reconstructionProvenance?.movieEvidence.first?.alignmentUnavailableReason.isEmpty == false)
    }

    @Test func writtenSamplesEstablishDelayedMovieOriginWithoutEquatingRawPTS() throws {
        let id = UUID()
        let samples = [0.0, 1.0, 2.0].map { offset in
            RecordingCaptureSampleTiming(presentationTime: 900 + offset, displayedHostTime: 103 + offset,
                receivedHostTime: 104 + offset, duration: 1, screenRect: nil, contentRect: nil,
                imageSize: .init(width: 100, height: 100), displayScale: 1, writtenVideoTime: offset)
        }
        let evidence = RecordingMovieTimingEvidence(segmentID: id, samples: samples,
            fileTrackStartPTS: 0, fileTrackDuration: 3, alignmentUnavailableReason: "")
        let clocks = RecordingReconstructionProvenance.writtenMovieClocks(movieEvidence: [evidence], origin: 100)
        let mapping = try RecordingVideoClockMapping(segments: clocks)
        #expect(mapping.videoTime(forRecordingTime: 3, segmentID: id.uuidString) == 0)
        #expect(mapping.videoTime(forRecordingTime: 4.5, segmentID: id.uuidString) == 1.5)
        #expect(mapping.videoTime(forRecordingTime: 0, segmentID: id.uuidString) == nil)
        #expect(mapping.videoTime(forRecordingTime: 6, segmentID: id.uuidString) == nil)
        #expect(try JSONDecoder().decode(RecordingMovieTimingEvidence.self,
            from: JSONEncoder().encode(evidence)) == evidence)
    }

    @Test("Incomplete or unverified writer receipts never produce movie alignment", arguments: 0...5)
    func incompleteWrittenSamples(variant: Int) {
        var samples = [0.0, 1.0].map { offset in
            RecordingCaptureSampleTiming(presentationTime: 700 + offset, displayedHostTime: 102 + offset,
                receivedHostTime: 105 + offset, duration: 1, screenRect: nil, contentRect: nil,
                imageSize: .init(width: 100, height: 100), displayScale: 1, writtenVideoTime: offset)
        }
        if variant == 0 { samples[1].writtenVideoTime = nil }
        if variant == 1 { samples[1].displayedHostTime = nil }
        if variant == 2 { samples[1].displayedHostTime = 101 }
        if variant == 3 { samples[1].writtenVideoTime = 20 }
        let evidence = RecordingMovieTimingEvidence(segmentID: UUID(), samples: samples,
            fileTrackStartPTS: variant == 4 ? 3 : 0, fileTrackDuration: 2,
            alignmentUnavailableReason: variant == 5 ? "Writer did not finalize." : "")
        #expect(RecordingReconstructionProvenance.writtenMovieClocks(movieEvidence: [evidence], origin: 100).isEmpty)
    }

}

import Foundation
import Testing
@testable import SparkleRecorderCore
@testable import SparkleRecorder

@Suite("Macro reconstruction package")
struct MacroReconstructionPackageTests {
    @Test("Export retains complete source and a strict candidate template without executing")
    func sourceAndTemplate() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let source = SavedMacro(name: "Example", events: TestFixtures.clickPair())
        let report = try MacroReconstructionPackage.export(source: source, to: output)
        #expect(report.sourceRevision == (try MacroCandidateIdentity.revision(of: source)))
        let decoded = try JSONDecoder().decode(SavedMacro.self, from: Data(contentsOf: output.appendingPathComponent("source-macro.json")))
        #expect(decoded.events == source.events)
        let template = try MacroCandidateValidator.decode(Data(contentsOf: output.appendingPathComponent("candidate-template.json")))
        #expect(template.sourceRevision == report.sourceRevision)
        #expect(template.coverage.count == 1)
        #expect(report.artifacts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("instructions.md").path))
    }

    @Test("Edited and legacy sources cannot export old alignment as current", arguments: 0...2)
    func sourceContentBinding(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = TestFixtures.clickPair()
        var source = SavedMacro(name: "Edited source", events: original)
        if variant == 1 { source.events[0].x += 50 }
        var provenance = RecordingReconstructionProvenance(sessionOriginHostTime: 100, sessionEndTime: 2,
            sourceEvents: [.init(sourceEventIndex: 0, sourcePlaybackTime: original[0].time, sessionTime: 0)],
            sourceEventDigest: try RecordingReconstructionProvenance.digest(ofSourceEvents: original))
        if variant == 2 { provenance.sourceEventDigest = nil }
        let report = try MacroReconstructionPackage.export(source: source,
            bundle: SemanticRecordingBundle(reconstructionProvenance: provenance), to: root)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("alignment.json").path) == (variant == 0))
        #expect(report.sourceEventsMatchRecording == (variant == 0))
        if variant != 0 { #expect(report.warnings.contains { $0.contains("source event content") }) }
    }

    @Test("Export refuses existing output rather than mixing evidence packages")
    func refusesExistingDirectory() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(throws: (any Error).self) {
            try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []), to: output)
        }
    }

    @Test("Visual evidence needs explicit inclusion and missing files stay reported")
    func visualOptIn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = SemanticRecordingBundle(videoSegments: [RecordingVideoSegment(
            artifactRef: try RecordingArtifactRef("video/missing.mov"), startTime: 0, duration: 1
        )])
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: false, to: root.appendingPathComponent("export"))
        #expect(report.artifacts.isEmpty)
        #expect(!report.visualEvidenceIncluded)
    }

    @Test("Suppressed movie export requires an exact complete clock and current redaction receipt", arguments: 0...7)
    func suppressedMovieEvidence(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try RecordingArtifactRef("original.mov")
        let redacted = try RecordingArtifactRef("redacted.mov")
        try Data("private".utf8).write(to: root.appendingPathComponent(original.path))
        try Data("masked".utf8).write(to: root.appendingPathComponent(redacted.path))
        let segment = RecordingVideoSegment(artifactRef: original, startTime: 0, duration: 10)
        let suppression = RecordingSuppressionRecord(reason: .privateRegion,
            timeRange: RecordingTimeRange(startTime: 4, duration: 1))
        let anchors = variant == 2
            ? [RecordingVideoClockAnchor(recordingTime: 2, videoTime: 0), .init(recordingTime: 12, videoTime: 10)]
            : [RecordingVideoClockAnchor(recordingTime: 0, videoTime: 0), .init(recordingTime: 10, videoTime: 10)]
        let clock = RecordingVideoClockSegment(id: segment.id.uuidString, anchors: anchors,
            maximumError: variant == 3 ? 0.01 : 0)
        let receipt = SemanticRecordingRenderedVideoRedaction(videoSegmentID: segment.id,
            sourceVideoRef: variant == 4 ? redacted : original,
            redactedVideoRef: variant == 7 ? original : redacted,
            renderedRangeCount: variant == 6 ? 0 : 1,
            sourceSuppressionIDs: variant == 5 ? [] : [suppression.id])
        let bundle = SemanticRecordingBundle(videoSegments: [segment], suppressions: [suppression],
            redactedVideos: [receipt], reconstructionProvenance: .init(sessionOriginHostTime: 100,
                sessionEndTime: 10, clockSegments: variant == 1 ? [] : [clock]))
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        #expect(report.visualEvidenceIncluded == (variant == 0))
        #expect(report.artifacts.count == (variant == 0 ? 1 : 0))
    }

    @Test("Suppressed frames require matching source, full mask coverage and distinct bytes", arguments: 0...5)
    func suppressedFrameEvidence(variant: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try RecordingArtifactRef("original.png")
        let redacted = try RecordingArtifactRef("redacted.png")
        try Data("private".utf8).write(to: root.appendingPathComponent(original.path))
        if variant == 5 {
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(redacted.path),
                withDestinationURL: root.appendingPathComponent(original.path))
        } else {
            try Data("masked".utf8).write(to: root.appendingPathComponent(redacted.path))
        }
        let frame = RecordingFrameReference(recordingTime: 1, imageRef: original,
            imageSize: .init(width: 10, height: 10), source: .manual)
        let suppression = RecordingSuppressionRecord(reason: .privateRegion, frameID: frame.id)
        let receipt = SemanticRecordingRenderedFrameRedaction(frameID: frame.id,
            sourceImageRef: variant == 1 ? redacted : original,
            redactedImageRef: variant == 4 ? original : redacted,
            renderedMaskCount: variant == 3 ? 0 : 1,
            sourceSuppressionIDs: variant == 2 ? [] : [suppression.id])
        let bundle = SemanticRecordingBundle(frames: [frame], suppressions: [suppression], redactedFrames: [receipt])
        let report = try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
            bundle: bundle, bundleDirectory: root, includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        #expect(report.visualEvidenceIncluded == (variant == 0))
        #expect(report.artifacts.count == (variant == 0 ? 1 : 0))
    }

    @Test("Visual export rejects an artifact symlink outside the bundle")
    func externalArtifactSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleRoot = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let privateFile = root.appendingPathComponent("private.png")
        try Data("private".utf8).write(to: privateFile)
        try FileManager.default.createSymbolicLink(at: bundleRoot.appendingPathComponent("frame.png"), withDestinationURL: privateFile)
        let frame = RecordingFrameReference(recordingTime: 0, imageRef: try RecordingArtifactRef("frame.png"), source: .manual)
        #expect(throws: (any Error).self) {
            try MacroReconstructionPackage.export(source: SavedMacro(name: "Example", events: []),
                bundle: SemanticRecordingBundle(frames: [frame]), bundleDirectory: bundleRoot,
                includeVisualEvidence: true, to: root.appendingPathComponent("export"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("export").path))
    }

}

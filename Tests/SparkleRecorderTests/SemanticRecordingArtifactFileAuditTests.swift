import Foundation
import SparkleRecorderCore
@testable import SparkleRecorder
import Testing

@Suite("Semantic Recording Artifact File Audit Tests")
struct SemanticRecordingArtifactFileAuditTests {
    @Test("Artifact auditor reports present empty and missing bundle files")
    func artifactAuditorReportsPresentEmptyAndMissingBundleFiles() throws {
        let recordingID = try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000001"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle-artifact-audit-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectory = root.appendingPathComponent(recordingID.uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let videoRef = try RecordingArtifactRef("video/recording.mov")
        let presentFrameRef = try RecordingArtifactRef("frames/present.png")
        let emptyFrameRef = try RecordingArtifactRef("frames/empty.png")
        let missingFrameRef = try RecordingArtifactRef("frames/missing.png")
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            capturePolicy: RecordingCapturePolicy(),
            videoSegments: [
                RecordingVideoSegment(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000002")),
                    artifactRef: videoRef,
                    startTime: 0,
                    duration: 1.5
                )
            ],
            frames: [
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000003")),
                    recordingTime: 0.1,
                    imageRef: presentFrameRef,
                    source: .recordingStart
                ),
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000004")),
                    recordingTime: 0.8,
                    imageRef: emptyFrameRef,
                    source: .mouseUp
                ),
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000005")),
                    recordingTime: 1.5,
                    imageRef: missingFrameRef,
                    source: .recordingStop
                )
            ]
        )

        try FileManager.default.createDirectory(
            at: bundleDirectory.appendingPathComponent("video", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundleDirectory.appendingPathComponent("frames", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2]).write(
            to: bundleDirectory
                .appendingPathComponent("video", isDirectory: true)
                .appendingPathComponent("recording.mov")
        )
        try Data([3, 4]).write(
            to: bundleDirectory
                .appendingPathComponent("frames", isDirectory: true)
                .appendingPathComponent("present.png")
        )
        try Data().write(
            to: bundleDirectory
                .appendingPathComponent("frames", isDirectory: true)
                .appendingPathComponent("empty.png")
        )

        let summary = try #require(
            SemanticRecordingArtifactFileAuditor.summary(
                bundle: bundle,
                bundleDirectory: bundleDirectory
            )
        )

        #expect(summary.checkedCount == 4)
        #expect(summary.presentCount == 2)
        #expect(summary.emptyCount == 1)
        #expect(summary.missingCount == 1)
        #expect(summary.videoPresentCount == 1)
        #expect(summary.framePresentCount == 1)
        #expect(summary.hasIssues)
        #expect(summary.evidence.first { $0.ref == missingFrameRef }?.status == .missing)
        #expect(summary.evidence.first { $0.ref == emptyFrameRef }?.status == .empty)
    }
}

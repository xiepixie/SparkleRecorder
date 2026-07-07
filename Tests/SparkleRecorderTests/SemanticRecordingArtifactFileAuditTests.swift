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
        let visualObservationRef = try RecordingArtifactRef("visual-index/ocr/confirmation.png")
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
            ],
            visualObservations: [
                RecordingVisualObservation(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000006")),
                    kind: .ocrText,
                    recordingTime: 1.2,
                    artifactRef: visualObservationRef,
                    text: "Order confirmed",
                    confidence: 0.9,
                    provider: "FixtureOCR"
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
        try FileManager.default.createDirectory(
            at: bundleDirectory.appendingPathComponent("visual-index/ocr", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data([5, 6]).write(
            to: bundleDirectory
                .appendingPathComponent("visual-index/ocr", isDirectory: true)
                .appendingPathComponent("confirmation.png")
        )

        let summary = try #require(
            SemanticRecordingArtifactFileAuditor.summary(
                bundle: bundle,
                bundleDirectory: bundleDirectory
            )
        )

        #expect(summary.checkedCount == 5)
        #expect(summary.presentCount == 3)
        #expect(summary.emptyCount == 1)
        #expect(summary.missingCount == 1)
        #expect(summary.deletedCount == 0)
        #expect(summary.videoPresentCount == 1)
        #expect(summary.framePresentCount == 1)
        #expect(summary.hasIssues)
        #expect(summary.evidence.first { $0.ref == visualObservationRef }?.kind == .visualObservation)
        #expect(summary.evidence.first { $0.ref == visualObservationRef }?.status == .present)
        #expect(summary.evidence.first { $0.ref == missingFrameRef }?.status == .missing)
        #expect(summary.evidence.first { $0.ref == emptyFrameRef }?.status == .empty)
    }

    @Test("Artifact auditor reports user-deleted refs separately from missing files")
    func artifactAuditorReportsUserDeletedRefsSeparatelyFromMissingFiles() throws {
        let recordingID = try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000101"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle-artifact-audit-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectory = root.appendingPathComponent(recordingID.uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let deletedFrameRef = try RecordingArtifactRef("frames/deleted.png")
        let missingFrameRef = try RecordingArtifactRef("frames/missing.png")
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            frames: [
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000102")),
                    recordingTime: 0.1,
                    imageRef: deletedFrameRef,
                    source: .recordingStart
                ),
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000103")),
                    recordingTime: 0.8,
                    imageRef: missingFrameRef,
                    source: .recordingStop
                )
            ],
            suppressions: [
                RecordingSuppressionRecord(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000104")),
                    reason: .userDeleted,
                    redactedArtifactRef: deletedFrameRef,
                    detail: "Artifact was deleted during retention cleanup."
                )
            ]
        )

        try FileManager.default.createDirectory(
            at: bundleDirectory,
            withIntermediateDirectories: true
        )

        let summary = try #require(
            SemanticRecordingArtifactFileAuditor.summary(
                bundle: bundle,
                bundleDirectory: bundleDirectory
            )
        )

        #expect(summary.checkedCount == 2)
        #expect(summary.deletedCount == 1)
        #expect(summary.missingCount == 1)
        #expect(summary.hasIssues)
        #expect(summary.evidence.first { $0.ref == deletedFrameRef }?.status == .deleted)
        #expect(summary.evidence.first { $0.ref == deletedFrameRef }?.reason?.contains("retention cleanup") == true)
        #expect(summary.evidence.first { $0.ref == missingFrameRef }?.status == .missing)
    }
}

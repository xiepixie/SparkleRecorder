import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Workflow Product Evidence Directory Tests")
struct WorkflowProductEvidenceDirectoryTests {
    @Test("Missing product evidence directory produces an empty snapshot")
    func missingDirectoryProducesEmptySnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let snapshot = try WorkflowProductEvidenceDirectory.snapshot(at: directory)

        #expect(snapshot.existingPaths.isEmpty)
        #expect(snapshot.fileByteCounts.isEmpty)
        #expect(snapshot.clipContainers.isEmpty)
        #expect(snapshot.sidecarContents.isEmpty)
    }

    @Test("Snapshot collects sidecars byte counts and clip containers together")
    func snapshotCollectsDirectoryFactsTogether() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sidecar = directory.appendingPathComponent("capture.md")
        let clip = directory.appendingPathComponent("capture.mov")
        let text = "# Capture\nEvidence source: live app recording\n"
        let clipData = Data([0, 0, 0, 24] + Array("ftyp".utf8) + [0, 0, 0, 0])
        try text.write(to: sidecar, atomically: true, encoding: .utf8)
        try clipData.write(to: clip, options: .atomic)

        let snapshot = try WorkflowProductEvidenceDirectory.snapshot(at: directory)

        #expect(snapshot.existingPaths == Set(["capture.md", "capture.mov"]))
        #expect(snapshot.sidecarContents["capture.md"] == text)
        #expect(snapshot.fileByteCounts["capture.md"] == Int64(text.utf8.count))
        #expect(snapshot.fileByteCounts["capture.mov"] == Int64(clipData.count))
        #expect(snapshot.clipContainers["capture.mov"] == .isoBaseMedia)
    }

    @Test("Clip container classification stays behind the directory Module")
    func clipContainerClassificationStaysBehindDirectoryModule() {
        let mp4Header = Data([0, 0, 0, 24] + Array("ftyp".utf8) + [0, 0, 0, 0])
        let movHeader = Data([0, 0, 0, 24] + Array("moov".utf8) + [0, 0, 0, 0])
        let unsupported = Data("not-video".utf8)

        #expect(WorkflowProductEvidenceDirectory.clipContainer(from: mp4Header) == .isoBaseMedia)
        #expect(WorkflowProductEvidenceDirectory.clipContainer(from: movHeader) == .isoBaseMedia)
        #expect(WorkflowProductEvidenceDirectory.clipContainer(from: unsupported) == .unsupported)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-ProductEvidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

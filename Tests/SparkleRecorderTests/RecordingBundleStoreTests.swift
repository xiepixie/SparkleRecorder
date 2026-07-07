import Foundation
@testable import SparkleRecorder
@testable import SparkleRecorderCore
import Testing

@Suite("Recording Bundle Store Tests")
struct RecordingBundleStoreTests {
    @Test("Default root uses stable App Support semantic recordings directory")
    func defaultRootUsesStableSemanticRecordingsDirectory() {
        let root = RecordingBundleStore.defaultRootDirectory.standardizedFileURL
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .standardizedFileURL

        #expect(root.path.hasPrefix(appSupport.path))
        #expect(root.lastPathComponent == "SemanticRecordings")
        #expect(root.deletingLastPathComponent().lastPathComponent == "SparkleRecorder")
    }

    @Test("Store writes, loads, and catalogs bundle sidecars in a scratch root")
    func storeWritesLoadsAndCatalogsBundleSidecars() async throws {
        let root = scratchRoot()
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RecordingBundleStore(rootDirectory: root)
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let directory = try await store.createBundleDirectory(recordingID: bundle.id)

        try await store.write(bundle, to: directory)

        let expectedFiles = [
            "manifest.json",
            "video/segments.json",
            "frames/index.jsonl",
            "timeline.jsonl",
            "events.jsonl",
            "ocr/observations.jsonl",
            "suppressed.jsonl"
        ]
        for relativePath in expectedFiles {
            #expect(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(relativePath).path
                ),
                "Expected bundle sidecar file to exist: \(relativePath)"
            )
        }

        let loaded = try await store.loadBundle(recordingID: bundle.id)
        #expect(loaded.id == bundle.id)
        #expect(loaded.videoSegments == bundle.videoSegments)
        #expect(loaded.frames == bundle.frames)
        #expect(loaded.timelineEvents == bundle.timelineEvents)
        #expect(loaded.aiSafeEvents == bundle.aiSafeEvents)
        #expect(loaded.visualObservations == bundle.visualObservations)
        #expect(loaded.suppressions == bundle.suppressions)

        let tolerant = try await store.loadBundleTolerant(recordingID: bundle.id)
        #expect(tolerant.bundle.id == bundle.id)
        #expect(!tolerant.sidecarDiagnostics.isDegraded)
        #expect(tolerant.sidecarDiagnostics.loadedKinds.contains(.videoSegments))
        #expect(tolerant.sidecarDiagnostics.loadedKinds.contains(.frames))
        #expect(tolerant.sidecarDiagnostics.loadedKinds.contains(.semanticEvents))

        let catalog = try await store.listBundleCatalog()
        #expect(catalog.map(\.recordingID) == [bundle.id])
        #expect(catalog.first?.directory.standardizedFileURL == directory.standardizedFileURL)
    }

    @Test("Store rejects explicit bundle loads outside its configured root")
    func storeRejectsExplicitBundleLoadsOutsideRoot() async throws {
        let root = scratchRoot()
        let outsideRoot = scratchRoot()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outsideRoot)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let store = RecordingBundleStore(rootDirectory: root)
        let bundle = SemanticRecordingFixture.checkoutBundle()
        let outsideDirectory = outsideRoot
            .appendingPathComponent(bundle.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true
        )

        await #expect(throws: RecordingBundleStoreLoadError.unsafeBundleDirectory(outsideDirectory.path)) {
            try await store.loadBundle(from: outsideDirectory)
        }
    }

    private func scratchRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-RecordingBundleStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

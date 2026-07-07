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

    @Test("Pruned artifacts reload as user-deleted artifact evidence")
    func prunedArtifactsReloadAsUserDeletedArtifactEvidence() async throws {
        let root = scratchRoot()
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let recordingID = try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000201"))
        let videoRef = try RecordingArtifactRef("video/recording.mov")
        let frameRef = try RecordingArtifactRef("frames/start.png")
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let evaluatedAt = createdAt.addingTimeInterval(120)
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            createdAt: createdAt,
            videoSegments: [
                RecordingVideoSegment(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000202")),
                    artifactRef: videoRef,
                    startTime: 0,
                    duration: 1.0
                )
            ],
            frames: [
                RecordingFrameReference(
                    id: try #require(UUID(uuidString: "92000000-0000-0000-0000-000000000203")),
                    recordingTime: 0,
                    imageRef: frameRef,
                    source: .recordingStart
                )
            ]
        )

        let store = RecordingBundleStore(rootDirectory: root)
        let directory = try await store.createBundleDirectory(recordingID: bundle.id)
        try await store.write(bundle, to: directory)
        try Data([0, 1, 2]).write(to: directory.appendingRecordingArtifactRef(videoRef))
        try Data([3, 4]).write(to: directory.appendingRecordingArtifactRef(frameRef))

        let plan = SemanticRecordingRetentionPlanner.plan(
            for: bundle,
            policy: SemanticRecordingRetentionPolicy(
                maximumArtifactAge: 60,
                expiredDisposition: .pruneArtifacts
            ),
            evaluatedAt: evaluatedAt
        )
        let result = try await store.applyRetentionPlan(plan, dryRun: false)

        #expect(result.deletedRelativePaths.sorted() == [frameRef.path, videoRef.path].sorted())

        let loaded = try await store.loadBundleTolerant(recordingID: recordingID).bundle
        let deletedRefs = loaded.suppressions
            .filter { $0.reason == .userDeleted }
            .compactMap(\.redactedArtifactRef?.path)
            .sorted()
        #expect(deletedRefs == [frameRef.path, videoRef.path].sorted())

        let summary = try #require(
            SemanticRecordingArtifactFileAuditor.summary(
                bundle: loaded,
                bundleDirectory: directory
            )
        )
        #expect(summary.deletedCount == 2)
        #expect(summary.missingCount == 0)
        #expect(summary.evidence.first { $0.ref == videoRef }?.status == .deleted)
        #expect(summary.evidence.first { $0.ref == frameRef }?.status == .deleted)
    }

    private func scratchRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-RecordingBundleStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

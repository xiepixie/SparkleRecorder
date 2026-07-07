import Foundation
import SparkleRecorderCore

struct RecordingBundleRetentionApplicationResult: Codable, Equatable, Sendable {
    var plan: SemanticRecordingRetentionPlan
    var dryRun: Bool
    var plannedRelativePaths: [String]
    var candidateRelativePaths: [String]
    var deletedRelativePaths: [String]
    var missingRelativePaths: [String]
    var preservedRelativePaths: [String]
    var deletedBundleDirectory: Bool

    init(
        plan: SemanticRecordingRetentionPlan,
        dryRun: Bool,
        plannedRelativePaths: [String] = [],
        candidateRelativePaths: [String] = [],
        deletedRelativePaths: [String] = [],
        missingRelativePaths: [String] = [],
        preservedRelativePaths: [String] = [],
        deletedBundleDirectory: Bool = false
    ) {
        self.plan = plan
        self.dryRun = dryRun
        self.plannedRelativePaths = plannedRelativePaths
        self.candidateRelativePaths = candidateRelativePaths
        self.deletedRelativePaths = deletedRelativePaths
        self.missingRelativePaths = missingRelativePaths
        self.preservedRelativePaths = preservedRelativePaths
        self.deletedBundleDirectory = deletedBundleDirectory
    }
}

struct RecordingBundleRedactionApplicationResult: Codable, Equatable, Sendable {
    var plan: SemanticRecordingRedactionPlan
    var dryRun: Bool
    var frameIndexRelativePath: String
    var videoIndexRelativePath: String
    var plannedFrameRelativePaths: [String]
    var plannedVideoRelativePaths: [String]
    var renderedFrameRelativePaths: [String]
    var renderedVideoRelativePaths: [String]
    var renderedFrames: [SemanticRecordingRenderedFrameRedaction]
    var renderedVideos: [SemanticRecordingRenderedVideoRedaction]
    var pendingVideoRangeRedactions: [SemanticRecordingVideoRangeRedaction]

    init(
        plan: SemanticRecordingRedactionPlan,
        dryRun: Bool,
        frameIndexRelativePath: String = RecordingBundleStore.redactedFrameIndexRelativePath,
        videoIndexRelativePath: String = RecordingBundleStore.redactedVideoIndexRelativePath,
        plannedFrameRelativePaths: [String] = [],
        plannedVideoRelativePaths: [String] = [],
        renderedFrameRelativePaths: [String] = [],
        renderedVideoRelativePaths: [String] = [],
        renderedFrames: [SemanticRecordingRenderedFrameRedaction] = [],
        renderedVideos: [SemanticRecordingRenderedVideoRedaction] = [],
        pendingVideoRangeRedactions: [SemanticRecordingVideoRangeRedaction] = []
    ) {
        self.plan = plan
        self.dryRun = dryRun
        self.frameIndexRelativePath = frameIndexRelativePath
        self.videoIndexRelativePath = videoIndexRelativePath
        self.plannedFrameRelativePaths = plannedFrameRelativePaths
        self.plannedVideoRelativePaths = plannedVideoRelativePaths
        self.renderedFrameRelativePaths = renderedFrameRelativePaths
        self.renderedVideoRelativePaths = renderedVideoRelativePaths
        self.renderedFrames = renderedFrames
        self.renderedVideos = renderedVideos
        self.pendingVideoRangeRedactions = pendingVideoRangeRedactions
    }
}

struct RecordingBundleStoreCatalogEntry: Equatable, Sendable {
    var recordingID: UUID
    var directory: URL
    var manifestURL: URL
    var modifiedAt: Date?
}

enum RecordingBundleStoreRetentionError: Error, Equatable, Sendable {
    case unsafeArtifactPath(String)
    case artifactPathIsDirectory(String)
}

enum RecordingBundleStoreLoadError: Error, Equatable, Sendable {
    case unsafeBundleDirectory(String)
}

enum RecordingBundleStoreRedactionError: Error, Equatable, Sendable {
    case missingVideoSegment(UUID)
}

actor RecordingBundleStore {
    static let redactedFrameIndexRelativePath = "redacted/frames/index.json"
    static let redactedVideoIndexRelativePath = "redacted/video/index.json"
    nonisolated static var defaultRootDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
            .appendingPathComponent("SemanticRecordings", isDirectory: true)
    }

    let rootDirectory: URL

    init(rootDirectory: URL = RecordingBundleStore.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    func createBundleDirectory(recordingID: UUID) throws -> URL {
        let directory = bundleDirectory(for: recordingID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try createBundleSubdirectories(in: directory)
        return directory
    }

    func bundleDirectory(for recordingID: UUID) -> URL {
        rootDirectory.appendingPathComponent(
            SemanticRecordingBundleDirectoryIdentity.directoryName(for: recordingID),
            isDirectory: true
        )
    }

    @discardableResult
    func removeBundleDirectory(recordingID: UUID) throws -> Bool {
        let directory = bundleDirectory(for: recordingID)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return false
        }
        guard isDirectory.boolValue else {
            throw RecordingBundleStoreRetentionError.unsafeArtifactPath(directory.lastPathComponent)
        }
        try FileManager.default.removeItem(at: directory)
        return true
    }

    func write(_ bundle: SemanticRecordingBundle, to directory: URL) throws {
        try createBundleSubdirectories(in: directory)
        try writeJSON(bundle, to: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName))
        try writeJSON(
            bundle.videoSegments,
            to: directory
                .appendingPathComponent("video", isDirectory: true)
                .appendingPathComponent("segments.json")
        )
        try writeJSONLines(
            bundle.frames,
            to: directory
                .appendingPathComponent("frames", isDirectory: true)
                .appendingPathComponent("index.jsonl")
        )
        try writeJSONLines(
            bundle.timelineEvents,
            to: directory.appendingPathComponent(SemanticRecordingSchema.privateTimelineFileName)
        )
        try writeJSONLines(
            bundle.aiSafeEvents,
            to: directory.appendingPathComponent(SemanticRecordingSchema.aiSafeEventsFileName)
        )
        try writeJSONLines(
            bundle.visualObservations,
            to: directory
                .appendingPathComponent("ocr", isDirectory: true)
                .appendingPathComponent("observations.jsonl")
        )
        try writeJSONLines(
            bundle.suppressions,
            to: directory.appendingPathComponent(SemanticRecordingSchema.suppressionsFileName)
        )
    }

    func listBundleCatalog() throws -> [RecordingBundleStoreCatalogEntry] {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [RecordingBundleStoreCatalogEntry] = []
        for directory in directories {
            let values = try directory.resourceValues(
                forKeys: [.isDirectoryKey, .contentModificationDateKey]
            )
            guard values.isDirectory == true,
                  let recordingID = SemanticRecordingBundleDirectoryIdentity.recordingID(
                    fromDirectoryName: directory.lastPathComponent
                  ) else {
                continue
            }
            let manifestURL = directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName)
            guard FileManager.default.fileExists(atPath: manifestURL.path),
                  let manifest = try? loadManifest(from: directory),
                  manifest.id == recordingID else {
                continue
            }
            entries.append(
                RecordingBundleStoreCatalogEntry(
                    recordingID: recordingID,
                    directory: directory,
                    manifestURL: manifestURL,
                    modifiedAt: values.contentModificationDate
                )
            )
        }

        return entries.sorted { lhs, rhs in
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (left?, right?) where left != right:
                return left > right
            default:
                return lhs.recordingID.uuidString < rhs.recordingID.uuidString
            }
        }
    }

    func loadBundle(recordingID: UUID) throws -> SemanticRecordingBundle {
        try loadBundleResult(
            from: bundleDirectory(for: recordingID),
            toleratesSidecarFailures: false
        ).bundle
    }

    func loadBundleTolerant(recordingID: UUID) throws -> SemanticRecordingBundleLoadResult {
        try loadBundleResult(
            from: bundleDirectory(for: recordingID),
            toleratesSidecarFailures: true
        )
    }

    func retentionCleanupPreview(
        settings: SemanticRecordingRetentionSettings,
        evaluatedAt: Date = Date()
    ) throws -> SemanticRecordingRetentionCleanupPreview {
        let entries = try listBundleCatalog()
        let policy = settings.policy()
        let plans = try entries.map { entry in
            let bundle = try loadBundleTolerant(from: entry.directory).bundle
            return SemanticRecordingRetentionPlanner.plan(
                for: bundle,
                policy: policy,
                evaluatedAt: evaluatedAt
            )
        }
        return SemanticRecordingRetentionCleanupPresenter.preview(
            plans: plans,
            scannedRecordingCount: entries.count,
            evaluatedAt: evaluatedAt
        )
    }

    func applyRetentionCleanup(
        _ preview: SemanticRecordingRetentionCleanupPreview,
        dryRun: Bool = true
    ) throws -> [RecordingBundleRetentionApplicationResult] {
        try preview.plans.map { plan in
            try applyRetentionPlan(plan, dryRun: dryRun)
        }
    }

    func loadBundle(from directory: URL) throws -> SemanticRecordingBundle {
        try loadBundleResult(
            from: directory,
            toleratesSidecarFailures: false
        ).bundle
    }

    func loadBundleTolerant(from directory: URL) throws -> SemanticRecordingBundleLoadResult {
        try loadBundleResult(
            from: directory,
            toleratesSidecarFailures: true
        )
    }

    private func loadBundleResult(
        from directory: URL,
        toleratesSidecarFailures: Bool
    ) throws -> SemanticRecordingBundleLoadResult {
        let directory = try safeBundleDirectory(directory)
        let manifest = try loadManifest(from: directory)
        try SemanticRecordingBundleDirectoryIdentity.validate(
            bundle: manifest,
            directoryName: directory.lastPathComponent
        )
        var diagnostics = SemanticRecordingBundleSidecarLoadDiagnostics()
        let sidecars = SemanticRecordingBundleSidecars(
            videoSegments: try readSidecarJSONIfPresent(
                [RecordingVideoSegment].self,
                kind: .videoSegments,
                relativePath: "video/segments.json",
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            frames: try readSidecarJSONLinesIfPresent(
                RecordingFrameReference.self,
                kind: .frames,
                relativePath: "frames/index.jsonl",
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            timelineEvents: try readSidecarJSONLinesIfPresent(
                RecordingTimelineEvent.self,
                kind: .timelineEvents,
                relativePath: SemanticRecordingSchema.privateTimelineFileName,
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            semanticEvents: try readSidecarJSONLinesIfPresent(
                RecordingSemanticEvent.self,
                kind: .semanticEvents,
                relativePath: SemanticRecordingSchema.aiSafeEventsFileName,
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            visualObservations: try readSidecarJSONLinesIfPresent(
                RecordingVisualObservation.self,
                kind: .visualObservations,
                relativePath: "ocr/observations.jsonl",
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            suppressions: try readSidecarJSONLinesIfPresent(
                RecordingSuppressionRecord.self,
                kind: .suppressions,
                relativePath: SemanticRecordingSchema.suppressionsFileName,
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            redactedFrames: try readSidecarJSONIfPresent(
                [SemanticRecordingRenderedFrameRedaction].self,
                kind: .redactedFrames,
                relativePath: Self.redactedFrameIndexRelativePath,
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            ),
            redactedVideos: try readSidecarJSONIfPresent(
                [SemanticRecordingRenderedVideoRedaction].self,
                kind: .redactedVideos,
                relativePath: Self.redactedVideoIndexRelativePath,
                in: directory,
                diagnostics: &diagnostics,
                toleratesFailures: toleratesSidecarFailures
            )
        )
        return SemanticRecordingBundleLoadResult(
            manifest: manifest,
            sidecars: sidecars,
            sidecarDiagnostics: diagnostics
        )
    }

    func loadManifest(from directory: URL) throws -> SemanticRecordingBundle {
        let directory = try safeBundleDirectory(directory)
        let data = try Data(contentsOf: directory.appendingPathComponent(SemanticRecordingSchema.manifestFileName))
        return try Self.decoder.decode(SemanticRecordingBundle.self, from: data)
    }

    @discardableResult
    func applyRedactionPlan(
        _ plan: SemanticRecordingRedactionPlan,
        dryRun: Bool = true,
        renderer: SemanticRecordingFrameRedactionRenderer = SemanticRecordingFrameRedactionRenderer(),
        videoRenderer: SemanticRecordingVideoRedactionRenderer = SemanticRecordingVideoRedactionRenderer()
    ) async throws -> RecordingBundleRedactionApplicationResult {
        let directory = bundleDirectory(for: plan.recordingID)
        let plannedFramePaths = plan.frameRedactions.map(\.redactedImageRef.path)
        let bundle = try loadBundle(recordingID: plan.recordingID)
        var segmentByID: [UUID: RecordingVideoSegment] = [:]
        for segment in bundle.videoSegments where segmentByID[segment.id] == nil {
            segmentByID[segment.id] = segment
        }
        let videoPlans = try groupedVideoRedactions(
            plan.videoRangeRedactions,
            segmentByID: segmentByID
        )
        let plannedVideoPaths = videoPlans.map(\.redactedVideoRef.path)
        guard !dryRun else {
            return RecordingBundleRedactionApplicationResult(
                plan: plan,
                dryRun: true,
                plannedFrameRelativePaths: plannedFramePaths,
                plannedVideoRelativePaths: plannedVideoPaths,
                pendingVideoRangeRedactions: plan.videoRangeRedactions
            )
        }

        var renderedFrames: [SemanticRecordingRenderedFrameRedaction] = []
        for frameRedaction in plan.frameRedactions {
            let sourceURL = try safeArtifactURL(
                for: frameRedaction.sourceImageRef,
                in: directory
            )
            let outputURL = try safeArtifactURL(
                for: frameRedaction.redactedImageRef,
                in: directory
            )
            let rendered = try renderer.render(
                frameRedaction,
                sourceURL: sourceURL,
                outputURL: outputURL
            )
            renderedFrames.append(rendered)
        }
        let frameIndexRef = try RecordingArtifactRef(Self.redactedFrameIndexRelativePath)
        try writeJSON(
            renderedFrames,
            to: safeArtifactURL(for: frameIndexRef, in: directory)
        )

        var renderedVideos: [SemanticRecordingRenderedVideoRedaction] = []
        for videoPlan in videoPlans {
            let sourceURL = try safeArtifactURL(
                for: videoPlan.segment.artifactRef,
                in: directory
            )
            let outputURL = try safeArtifactURL(
                for: videoPlan.redactedVideoRef,
                in: directory
            )
            let rendered = try await videoRenderer.render(
                segment: videoPlan.segment,
                redactions: videoPlan.redactions,
                redactedVideoRef: videoPlan.redactedVideoRef,
                sourceURL: sourceURL,
                outputURL: outputURL
            )
            renderedVideos.append(rendered)
        }
        let videoIndexRef = try RecordingArtifactRef(Self.redactedVideoIndexRelativePath)
        try writeJSON(
            renderedVideos,
            to: safeArtifactURL(for: videoIndexRef, in: directory)
        )

        return RecordingBundleRedactionApplicationResult(
            plan: plan,
            dryRun: false,
            plannedFrameRelativePaths: plannedFramePaths,
            plannedVideoRelativePaths: plannedVideoPaths,
            renderedFrameRelativePaths: renderedFrames.map(\.redactedImageRef.path),
            renderedVideoRelativePaths: renderedVideos.map(\.redactedVideoRef.path),
            renderedFrames: renderedFrames,
            renderedVideos: renderedVideos,
            pendingVideoRangeRedactions: []
        )
    }

    @discardableResult
    func applyRedactions(
        for bundle: SemanticRecordingBundle,
        dryRun: Bool = true,
        renderer: SemanticRecordingFrameRedactionRenderer = SemanticRecordingFrameRedactionRenderer(),
        videoRenderer: SemanticRecordingVideoRedactionRenderer = SemanticRecordingVideoRedactionRenderer()
    ) async throws -> RecordingBundleRedactionApplicationResult {
        try await applyRedactionPlan(
            SemanticRecordingRedactionPlanner.plan(for: bundle),
            dryRun: dryRun,
            renderer: renderer,
            videoRenderer: videoRenderer
        )
    }

    @discardableResult
    func applyRetentionPlan(
        _ plan: SemanticRecordingRetentionPlan,
        dryRun: Bool = true
    ) throws -> RecordingBundleRetentionApplicationResult {
        let plannedRelativePaths = plan.artifactRefsToDelete.map(\.path)

        switch plan.disposition {
        case .retain:
            return RecordingBundleRetentionApplicationResult(
                plan: plan,
                dryRun: dryRun,
                plannedRelativePaths: plannedRelativePaths
            )

        case .pruneArtifacts:
            return try pruneArtifacts(
                for: plan,
                dryRun: dryRun,
                plannedRelativePaths: plannedRelativePaths
            )

        case .deleteBundle:
            let directory = bundleDirectory(for: plan.recordingID)
            let exists = FileManager.default.fileExists(atPath: directory.path)
            if exists && !dryRun {
                try FileManager.default.removeItem(at: directory)
            }
            return RecordingBundleRetentionApplicationResult(
                plan: plan,
                dryRun: dryRun,
                plannedRelativePaths: plannedRelativePaths,
                candidateRelativePaths: plannedRelativePaths,
                missingRelativePaths: exists ? [] : plannedRelativePaths,
                deletedBundleDirectory: exists && !dryRun
            )
        }
    }

    private func createBundleSubdirectories(in directory: URL) throws {
        for component in [
            "video",
            "frames",
            "redacted",
            "redacted/frames",
            "redacted/video",
            "ocr",
            "accessibility",
            "windows",
            "visual-index",
            "ai",
            "runs"
        ] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private struct PlannedVideoRedaction {
        var segment: RecordingVideoSegment
        var redactions: [SemanticRecordingVideoRangeRedaction]
        var redactedVideoRef: RecordingArtifactRef
    }

    private func groupedVideoRedactions(
        _ redactions: [SemanticRecordingVideoRangeRedaction],
        segmentByID: [UUID: RecordingVideoSegment]
    ) throws -> [PlannedVideoRedaction] {
        let grouped = Dictionary(grouping: redactions, by: \.videoSegmentID)
        return try grouped.keys.sorted { $0.uuidString < $1.uuidString }.map { segmentID in
            guard let segment = segmentByID[segmentID] else {
                throw RecordingBundleStoreRedactionError.missingVideoSegment(segmentID)
            }
            return PlannedVideoRedaction(
                segment: segment,
                redactions: grouped[segmentID, default: []].sorted {
                    if $0.timeRange.startTime == $1.timeRange.startTime {
                        return $0.timeRange.duration < $1.timeRange.duration
                    }
                    return $0.timeRange.startTime < $1.timeRange.startTime
                },
                redactedVideoRef: try redactedVideoArtifactRef(for: segment)
            )
        }
    }

    private func redactedVideoArtifactRef(
        for segment: RecordingVideoSegment
    ) throws -> RecordingArtifactRef {
        let ext = sanitizedVideoExtension(segment.fileType)
        return try RecordingArtifactRef(
            "redacted/video/\(segment.id.uuidString.lowercased()).\(ext)"
        )
    }

    private func sanitizedVideoExtension(_ fileType: String) -> String {
        let lowercased = fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        guard !lowercased.isEmpty,
              lowercased.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "mov"
        }
        return lowercased
    }

    private func pruneArtifacts(
        for plan: SemanticRecordingRetentionPlan,
        dryRun: Bool,
        plannedRelativePaths: [String]
    ) throws -> RecordingBundleRetentionApplicationResult {
        let directory = bundleDirectory(for: plan.recordingID)
        let preservedMetadata = Set(plan.metadataFilesToPreserve)
        var candidates: [String] = []
        var deleted: [String] = []
        var deletedRefs: [RecordingArtifactRef] = []
        var missing: [String] = []
        var preserved: [String] = []

        for ref in plan.artifactRefsToDelete {
            if preservedMetadata.contains(ref.path) {
                preserved.append(ref.path)
                continue
            }

            candidates.append(ref.path)
            let url = try safeArtifactURL(for: ref, in: directory)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                missing.append(ref.path)
                continue
            }
            if isDirectory.boolValue {
                throw RecordingBundleStoreRetentionError.artifactPathIsDirectory(ref.path)
            }

            if !dryRun {
                try FileManager.default.removeItem(at: url)
                deleted.append(ref.path)
                deletedRefs.append(ref)
            }
        }
        if !dryRun, !deletedRefs.isEmpty {
            try appendUserDeletedSuppressions(
                for: deletedRefs,
                plan: plan,
                in: directory
            )
        }

        return RecordingBundleRetentionApplicationResult(
            plan: plan,
            dryRun: dryRun,
            plannedRelativePaths: plannedRelativePaths,
            candidateRelativePaths: candidates,
            deletedRelativePaths: deleted,
            missingRelativePaths: missing,
            preservedRelativePaths: preserved
        )
    }

    private func appendUserDeletedSuppressions(
        for refs: [RecordingArtifactRef],
        plan: SemanticRecordingRetentionPlan,
        in directory: URL
    ) throws {
        let existingSuppressions = (
            try? loadBundleTolerant(from: directory).bundle.suppressions
        ) ?? []
        let existingDeletionRefs = Set(
            existingSuppressions.compactMap { suppression -> String? in
                guard suppression.reason == .userDeleted else {
                    return nil
                }
                return suppression.redactedArtifactRef?.path
            }
        )
        let newSuppressions = refs
            .filter { !existingDeletionRefs.contains($0.path) }
            .map { ref in
                RecordingSuppressionRecord(
                    reason: .userDeleted,
                    redactedArtifactRef: ref,
                    detail: "Artifact was deleted by semantic recording retention cleanup.",
                    createdAt: plan.evaluatedAt
                )
            }
        guard !newSuppressions.isEmpty else {
            return
        }
        try writeJSONLines(
            existingSuppressions + newSuppressions,
            to: directory.appendingPathComponent(SemanticRecordingSchema.suppressionsFileName)
        )
    }

    private func safeArtifactURL(
        for ref: RecordingArtifactRef,
        in directory: URL
    ) throws -> URL {
        let rootURL = directory.standardizedFileURL.resolvingSymlinksInPath()
        let artifactURL = directory
            .appendingRecordingArtifactRef(ref)
            .standardizedFileURL
        let resolvedArtifactURL = artifactURL
            .resolvingSymlinksInPath()

        let rootPath = rootURL.path
        let artifactPath = resolvedArtifactURL.path
        guard artifactPath == rootPath || artifactPath.hasPrefix(rootPath + "/") else {
            throw RecordingBundleStoreRetentionError.unsafeArtifactPath(ref.path)
        }
        return artifactURL
    }

    private func safeBundleDirectory(_ directory: URL) throws -> URL {
        let rootURL = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let bundleURL = directory.standardizedFileURL.resolvingSymlinksInPath()

        let rootPath = rootURL.path
        let bundlePath = bundleURL.path
        guard bundlePath == rootPath || bundlePath.hasPrefix(rootPath + "/") else {
            throw RecordingBundleStoreLoadError.unsafeBundleDirectory(directory.path)
        }
        return directory.standardizedFileURL
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output = Data()
        for value in values {
            output.append(try Self.jsonLineEncoder.encode(value))
            output.append(Data("\n".utf8))
        }
        try output.write(to: url, options: .atomic)
    }

    private func readJSONIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(type, from: data)
    }

    private func readJSONLinesIfPresent<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> [T]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var values: [T] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            values.append(try Self.decoder.decode(type, from: Data(trimmed.utf8)))
        }
        return values
    }

    private func readSidecarJSONIfPresent<T: Decodable>(
        _ type: T.Type,
        kind: SemanticRecordingBundleSidecarKind,
        relativePath: String,
        in directory: URL,
        diagnostics: inout SemanticRecordingBundleSidecarLoadDiagnostics,
        toleratesFailures: Bool
    ) throws -> T? {
        let url = directory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            diagnostics.recordMissing(kind)
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let value = try Self.decoder.decode(type, from: data)
            diagnostics.recordLoaded(kind)
            return value
        } catch {
            guard toleratesFailures else { throw error }
            diagnostics.recordFailed(
                kind,
                relativePath: relativePath,
                message: sidecarLoadFailureMessage(error)
            )
            return nil
        }
    }

    private func readSidecarJSONLinesIfPresent<T: Decodable>(
        _ type: T.Type,
        kind: SemanticRecordingBundleSidecarKind,
        relativePath: String,
        in directory: URL,
        diagnostics: inout SemanticRecordingBundleSidecarLoadDiagnostics,
        toleratesFailures: Bool
    ) throws -> [T]? {
        let url = directory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            diagnostics.recordMissing(kind)
            return nil
        }

        do {
            let values = try readJSONLines(type, from: url)
            diagnostics.recordLoaded(kind)
            return values
        } catch {
            guard toleratesFailures else { throw error }
            diagnostics.recordFailed(
                kind,
                relativePath: relativePath,
                message: sidecarLoadFailureMessage(error)
            )
            return nil
        }
    }

    private func readJSONLines<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> [T] {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var values: [T] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            values.append(try Self.decoder.decode(type, from: Data(trimmed.utf8)))
        }
        return values
    }

    private func sidecarLoadFailureMessage(_ error: Error) -> String {
        switch error {
        case let decodingError as DecodingError:
            return "Could not decode sidecar: \(decodingError)"
        default:
            return "Could not read sidecar: \(error.localizedDescription)"
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var jsonLineEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

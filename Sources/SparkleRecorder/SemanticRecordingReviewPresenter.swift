import AppKit
import CryptoKit
import Foundation
import SparkleRecorderCore
import UniformTypeIdentifiers

struct SemanticRecordingReviewState: Identifiable {
    let id = UUID()
    let sourceName: String
    let bundleDirectory: URL?
    let loadedAt: Date
    let bundle: SemanticRecordingBundle
    let suggestions: [RecordingSuggestion]
    let validationIssues: [SemanticRecordingBundleIssue]
    let artifactStatuses: [String: SemanticRecordingReviewArtifactStatus]

    func artifactStatus(for path: String?) -> SemanticRecordingReviewArtifactStatus? {
        guard let path else {
            return nil
        }
        return artifactStatuses[path]
    }
}

struct SemanticRecordingReviewArtifactStatus: Identifiable {
    var id: String { path }
    var path: String
    var url: URL
    var exists: Bool

    init(path: String, url: URL, exists: Bool) {
        self.path = path
        self.url = url
        self.exists = exists
    }
}

enum SemanticRecordingReviewArtifactAction: Equatable {
    case open
    case reveal
}

enum SemanticRecordingReviewArtifactActionFeedback: Equatable {
    case succeeded(SemanticRecordingReviewArtifactAction, String)
    case failed(SemanticRecordingReviewArtifactAction, String)
}

enum SemanticRecordingReviewPresenterError: LocalizedError {
    case applicationSupportDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return NSLocalizedString("Application Support directory is unavailable.", comment: "")
        }
    }
}

private struct SemanticRecordingReviewMaterializedPatch {
    var patch: AutomationWorkflowDraftPatchDocument
    var packageDirectory: URL?
}

@MainActor
enum SemanticRecordingReviewPresenter {
    static func openBundle(
        suggestions: [RecordingSuggestion] = [],
        onReview: @escaping (Result<SemanticRecordingReviewState, Error>) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Open Macro Review Bundle", comment: "")
        panel.prompt = NSLocalizedString("Open Review", comment: "")
        panel.message = NSLocalizedString("Choose a semantic recording bundle folder or its manifest.json.", comment: "")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.directoryURL = defaultBundleRootURL

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task {
                do {
                    let state = try await reviewState(from: url, suggestions: suggestions)
                    await MainActor.run {
                        onReview(.success(state))
                    }
                } catch {
                    await MainActor.run {
                        onReview(.failure(error))
                    }
                }
            }
        }
    }

    static func reviewState(
        from selectedURL: URL,
        suggestions: [RecordingSuggestion] = []
    ) async throws -> SemanticRecordingReviewState {
        let directory = bundleDirectory(from: selectedURL)
        let store = RecordingBundleStore(rootDirectory: directory.deletingLastPathComponent())
        let bundle = try await store.loadManifest(from: directory)
        let validationIssues = bundle.validate()
        let artifactStatuses = artifactStatuses(for: bundle, directory: directory)

        return SemanticRecordingReviewState(
            sourceName: directory.lastPathComponent,
            bundleDirectory: directory,
            loadedAt: Date(),
            bundle: bundle,
            suggestions: suggestions,
            validationIssues: validationIssues,
            artifactStatuses: artifactStatuses
        )
    }

    static func reviewState(
        from reference: MacroSemanticRecordingReference,
        sourceName: String? = nil,
        suggestions: [RecordingSuggestion] = []
    ) async throws -> SemanticRecordingReviewState {
        let bundleRef = try RecordingArtifactRef(reference.bundleRelativePath)
        guard let appSupportRootURL else {
            throw SemanticRecordingReviewPresenterError.applicationSupportDirectoryUnavailable
        }
        let directory = appSupportRootURL.appendingRecordingArtifactRef(bundleRef)
        let store = RecordingBundleStore(rootDirectory: directory.deletingLastPathComponent())
        let bundle = try await store.loadManifest(from: directory)
        let validationIssues = bundle.validate()
        let artifactStatuses = artifactStatuses(for: bundle, directory: directory)

        return SemanticRecordingReviewState(
            sourceName: sourceName ?? directory.lastPathComponent,
            bundleDirectory: directory,
            loadedAt: Date(),
            bundle: bundle,
            suggestions: suggestions,
            validationIssues: validationIssues,
            artifactStatuses: artifactStatuses
        )
    }

    static func openArtifact(
        path: String?,
        in state: SemanticRecordingReviewState
    ) -> SemanticRecordingReviewArtifactActionFeedback {
        guard let status = state.artifactStatus(for: path), status.exists else {
            return .failed(.open, NSLocalizedString("Artifact is missing from the bundle.", comment: ""))
        }

        let didOpen = NSWorkspace.shared.open(status.url)
        return didOpen
            ? .succeeded(.open, status.path)
            : .failed(.open, NSLocalizedString("macOS could not open this artifact.", comment: ""))
    }

    static func revealArtifact(
        path: String?,
        in state: SemanticRecordingReviewState
    ) -> SemanticRecordingReviewArtifactActionFeedback {
        guard let status = state.artifactStatus(for: path), status.exists else {
            return .failed(.reveal, NSLocalizedString("Artifact is missing from the bundle.", comment: ""))
        }

        NSWorkspace.shared.activateFileViewerSelecting([status.url])
        return .succeeded(.reveal, status.path)
    }

    static func previewState(
        applying patch: AutomationWorkflowDraftPatchDocument,
        to workflow: AutomationWorkflow?,
        macros: [SavedMacro],
        sourceName: String,
        sourceDirectory: URL?
    ) throws -> AutomationWorkflowDraftPreviewState {
        let materializedPatch = try materializePatchAssetsIfNeeded(
            patch,
            sourceDirectory: sourceDirectory
        )
        let baseDocument: AutomationWorkflowDraftDocument
        if let workflow {
            baseDocument = AutomationWorkflowDraftExporter.export(workflow).document
        } else {
            baseDocument = AutomationWorkflowDraftDocument(workflow: AutomationWorkflowDraft(
                name: NSLocalizedString("Macro Review Draft", comment: "")
            ))
        }

        let macroCatalog = macros.map(AutomationWorkflowDraftMacroCatalogEntry.init(macro:))
        let patched = try AutomationWorkflowDraftPatchApplier.apply(
            materializedPatch.patch,
            to: baseDocument,
            context: AutomationWorkflowDraftValidationContext(macroCatalog: macroCatalog)
        )
        let preview = AutomationWorkflowDraftPreviewPresenter.previewState(
            document: patched.document,
            sourceName: sourceName,
            sourceDirectory: materializedPatch.packageDirectory ?? sourceDirectory,
            macroCatalog: macroCatalog
        )
        guard let workflow,
              var compiledWorkflow = preview.compiledWorkflow else {
            return preview
        }

        compiledWorkflow.id = workflow.id
        compiledWorkflow.createdAt = workflow.createdAt
        return AutomationWorkflowDraftPreviewState(
            sourceName: preview.sourceName,
            sourceDirectory: preview.sourceDirectory,
            loadedAt: preview.loadedAt,
            document: preview.document,
            macroCatalog: preview.macroCatalog,
            projection: preview.projection,
            compiledWorkflow: compiledWorkflow
        )
    }

    private static func materializePatchAssetsIfNeeded(
        _ patch: AutomationWorkflowDraftPatchDocument,
        sourceDirectory: URL?
    ) throws -> SemanticRecordingReviewMaterializedPatch {
        guard let sourceDirectory else {
            return SemanticRecordingReviewMaterializedPatch(
                patch: patch,
                packageDirectory: nil
            )
        }

        let packageDirectory = try reviewAssetPackageDirectory(
            for: patch,
            sourceDirectory: sourceDirectory
        )
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: patch,
            readArtifact: { path in
                let ref = try RecordingArtifactRef(path)
                let url = sourceDirectory.appendingRecordingArtifactRef(ref)
                return try Data(contentsOf: url)
            },
            writeAsset: { data, path in
                let ref = try RecordingArtifactRef(path)
                let url = packageDirectory.appendingRecordingArtifactRef(ref)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            }
        )

        return SemanticRecordingReviewMaterializedPatch(
            patch: materialized.patch,
            packageDirectory: materialized.copiedAssets.isEmpty ? nil : packageDirectory
        )
    }

    private static func reviewAssetPackageDirectory(
        for patch: AutomationWorkflowDraftPatchDocument,
        sourceDirectory: URL
    ) throws -> URL {
        let supportDirectory = AutomationPersistence.defaultFileURL
            .deletingLastPathComponent()
            .standardizedFileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let patchData = try encoder.encode(patch)
        var digestInput = Data(sourceDirectory.standardizedFileURL.path.utf8)
        digestInput.append(patchData)
        let digest = SHA256.hash(data: digestInput)
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()

        return supportDirectory
            .appendingPathComponent("ReviewVisualAssets", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }

    static func savePatch(
        _ patch: AutomationWorkflowDraftPatchDocument,
        defaultName: String,
        onComplete: @escaping (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("Save Workflow Draft Patch", comment: "")
        panel.prompt = NSLocalizedString("Save Patch", comment: "")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultName

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(patch)
                try data.write(to: url, options: .atomic)
                onComplete(.success(url))
            } catch {
                onComplete(.failure(error))
            }
        }
    }

    private static var defaultBundleRootURL: URL? {
        appSupportRootURL?
            .appendingPathComponent("SemanticRecordings", isDirectory: true)
    }

    private static var appSupportRootURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SparkleRecorder", isDirectory: true)
    }

    private static func bundleDirectory(from selectedURL: URL) -> URL {
        selectedURL.lastPathComponent == SemanticRecordingSchema.manifestFileName
            ? selectedURL.deletingLastPathComponent()
            : selectedURL
    }

    private static func artifactStatuses(
        for bundle: SemanticRecordingBundle,
        directory: URL
    ) -> [String: SemanticRecordingReviewArtifactStatus] {
        Dictionary(uniqueKeysWithValues: artifactRefs(in: bundle).map { ref in
            let url = directory.appendingRecordingArtifactRef(ref)
            return (
                ref.path,
                SemanticRecordingReviewArtifactStatus(
                    path: ref.path,
                    url: url,
                    exists: FileManager.default.fileExists(atPath: url.path)
                )
            )
        })
    }

    private static func artifactRefs(in bundle: SemanticRecordingBundle) -> [RecordingArtifactRef] {
        var refs: [RecordingArtifactRef] = []
        refs.append(contentsOf: bundle.videoSegments.map(\.artifactRef))
        refs.append(contentsOf: bundle.frames.map(\.imageRef))
        refs.append(contentsOf: bundle.visualObservations.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.sourcePreviews.compactMap(\.artifactRef))
        refs.append(contentsOf: bundle.runtimeSamples.map(\.artifactRef))
        refs.append(contentsOf: bundle.previewComparisons.compactMap(\.diffArtifactRef))
        refs.append(contentsOf: bundle.suppressions.compactMap(\.redactedArtifactRef))

        var seen = Set<String>()
        return refs
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }
}

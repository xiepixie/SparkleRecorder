import AppKit
import CryptoKit
import Foundation
import ImageIO
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
    case couldNotDecodeFrameImage(String)
    case emptyCropRegion(String)
    case emptyPixelSample(String)
    case missingPixelSampleBounds(String)
    case missingPixelSampleFrame(UUID)
    case pngEncodingFailed(String)
    case unsupportedPixelSampleCandidate(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return NSLocalizedString("Application Support directory is unavailable.", comment: "")
        case .couldNotDecodeFrameImage(let path):
            return String(format: NSLocalizedString("Could not decode frame image %@.", comment: ""), path)
        case .emptyCropRegion(let key):
            return String(format: NSLocalizedString("Selected crop region is empty for %@.", comment: ""), key)
        case .emptyPixelSample(let key):
            return String(format: NSLocalizedString("Could not sample pixel color for %@.", comment: ""), key)
        case .missingPixelSampleBounds(let key):
            return String(format: NSLocalizedString("Pixel sample %@ does not have bounds.", comment: ""), key)
        case .missingPixelSampleFrame(let frameID):
            return String(format: NSLocalizedString("Pixel sample frame %@ is missing.", comment: ""), frameID.uuidString)
        case .pngEncodingFailed(let key):
            return String(format: NSLocalizedString("Could not encode cropped asset %@.", comment: ""), key)
        case .unsupportedPixelSampleCandidate(let key):
            return String(format: NSLocalizedString("Candidate %@ is not a pixel sample.", comment: ""), key)
        }
    }
}

struct SemanticRecordingReviewDraftPreviewResult {
    var previewState: AutomationWorkflowDraftPreviewState
    var previewAction: SemanticRecordingReviewActionSemantics
    var importAction: SemanticRecordingReviewActionSemantics
}

struct SemanticRecordingReviewPixelColorSample: Equatable {
    var candidateID: String
    var frameID: UUID
    var sourcePreviewRefID: UUID?
    var observationID: UUID?
    var frameImagePath: String
    var bounds: RecordingBounds
    var pixelX: Int
    var pixelY: Int
    var colorHex: String

    var observationMetadataPatch: [String: String] {
        [
            "colorHex": colorHex,
            "samplePixelX": String(pixelX),
            "samplePixelY": String(pixelY),
            "sampleFrameID": frameID.uuidString,
            "sampleFrameImageRef": frameImagePath
        ]
    }
}

private struct SemanticRecordingReviewMaterializedPatch {
    var patch: AutomationWorkflowDraftPatchDocument
    var packageDirectory: URL?
    var copiedAssets: [SemanticRecordingReviewMaterializedAsset]
}

@MainActor
enum SemanticRecordingReviewPresenter {
    static func pixelColorSample(
        for candidate: SemanticRecordingReviewProjection.ConditionCandidateRow,
        bundle: SemanticRecordingBundle,
        bundleDirectory: URL
    ) throws -> SemanticRecordingReviewPixelColorSample {
        guard candidate.kind == .pixelMatched else {
            throw SemanticRecordingReviewPresenterError.unsupportedPixelSampleCandidate(candidate.id)
        }
        guard let frame = bundle.frames.first(where: { $0.id == candidate.sourceFrameID }) else {
            throw SemanticRecordingReviewPresenterError.missingPixelSampleFrame(candidate.sourceFrameID)
        }

        let sourcePreview = candidate.sourcePreviewRefID.flatMap { sourcePreviewID in
            bundle.sourcePreviews.first { $0.id == sourcePreviewID }
        }
        let observation = candidate.observationID.flatMap { observationID in
            bundle.visualObservations.first { $0.id == observationID }
        } ?? sourcePreview.flatMap { sourcePreview in
            bundle.visualObservations.first { $0.sourcePreviewRefID == sourcePreview.id && $0.kind == .pixelSample }
        }
        guard let bounds = candidate.bounds ?? observation?.bounds ?? sourcePreview?.bounds else {
            throw SemanticRecordingReviewPresenterError.missingPixelSampleBounds(candidate.id)
        }

        let effectiveFrameRef = bundle.redactedFrames
            .first { $0.frameID == frame.id }
            .map(\.redactedImageRef) ?? frame.imageRef
        let imageURL = bundleDirectory.appendingRecordingArtifactRef(effectiveFrameRef)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SemanticRecordingReviewPresenterError
                .couldNotDecodeFrameImage(effectiveFrameRef.path)
        }

        let point = pixelPoint(for: bounds, image: image)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let color = bitmap.colorAt(x: point.x, y: point.y)?.usingColorSpace(.sRGB) else {
            throw SemanticRecordingReviewPresenterError.emptyPixelSample(candidate.id)
        }
        let colorHex = String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )

        return SemanticRecordingReviewPixelColorSample(
            candidateID: candidate.id,
            frameID: frame.id,
            sourcePreviewRefID: candidate.sourcePreviewRefID,
            observationID: candidate.observationID ?? observation?.id,
            frameImagePath: effectiveFrameRef.path,
            bounds: bounds,
            pixelX: point.x,
            pixelY: point.y,
            colorHex: colorHex
        )
    }

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
        let bundle = try await store.loadBundle(from: directory)
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
        let bundle = try await store.loadBundle(from: directory)
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

    static func revealBundle(
        from reference: MacroSemanticRecordingReference
    ) -> SemanticRecordingReviewArtifactActionFeedback {
        do {
            let bundleRef = try RecordingArtifactRef(reference.bundleRelativePath)
            guard let appSupportRootURL else {
                return .failed(.reveal, NSLocalizedString("Application Support directory is unavailable.", comment: ""))
            }
            let directory = appSupportRootURL.appendingRecordingArtifactRef(bundleRef)
            guard FileManager.default.fileExists(atPath: directory.path) else {
                return .failed(.reveal, NSLocalizedString("Macro Review bundle is missing from Application Support.", comment: ""))
            }
            NSWorkspace.shared.activateFileViewerSelecting([directory])
            return .succeeded(.reveal, bundleRef.path)
        } catch {
            return .failed(
                .reveal,
                String(format: NSLocalizedString("Could not reveal Macro Review bundle: %@", comment: ""), String(describing: error))
            )
        }
    }

    static func previewState(
        applying result: SemanticRecordingReviewDraftPatchResult,
        to workflow: AutomationWorkflow?,
        macros: [SavedMacro],
        sourceName: String,
        sourceDirectory: URL?
    ) throws -> AutomationWorkflowDraftPreviewState {
        try previewResult(
            applying: result,
            to: workflow,
            macros: macros,
            sourceName: sourceName,
            sourceDirectory: sourceDirectory
        ).previewState
    }

    static func previewResult(
        applying result: SemanticRecordingReviewDraftPatchResult,
        to workflow: AutomationWorkflow?,
        macros: [SavedMacro],
        sourceName: String,
        sourceDirectory: URL?
    ) throws -> SemanticRecordingReviewDraftPreviewResult {
        let preview = try materializedPreview(
            applying: result.patch,
            assetExtractions: result.assetExtractions,
            to: workflow,
            macros: macros,
            sourceName: sourceName,
            sourceDirectory: sourceDirectory
        )
        return SemanticRecordingReviewDraftPreviewResult(
            previewState: preview.previewState,
            previewAction: .previewDraft(
                result,
                materializedAssets: preview.copiedAssets
            ),
            importAction: .importDraft(
                result,
                materializedAssets: preview.copiedAssets
            )
        )
    }

    static func previewState(
        applying patch: AutomationWorkflowDraftPatchDocument,
        to workflow: AutomationWorkflow?,
        macros: [SavedMacro],
        sourceName: String,
        sourceDirectory: URL?
    ) throws -> AutomationWorkflowDraftPreviewState {
        try materializedPreview(
            applying: patch,
            assetExtractions: [],
            to: workflow,
            macros: macros,
            sourceName: sourceName,
            sourceDirectory: sourceDirectory
        ).previewState
    }

    private static func materializedPreview(
        applying patch: AutomationWorkflowDraftPatchDocument,
        assetExtractions: [SemanticRecordingReviewAssetExtraction],
        to workflow: AutomationWorkflow?,
        macros: [SavedMacro],
        sourceName: String,
        sourceDirectory: URL?
    ) throws -> (
        previewState: AutomationWorkflowDraftPreviewState,
        copiedAssets: [SemanticRecordingReviewMaterializedAsset]
    ) {
        let materializedPatch = try materializePatchAssetsIfNeeded(
            patch,
            assetExtractions: assetExtractions,
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
            return (
                previewState: preview,
                copiedAssets: materializedPatch.copiedAssets
            )
        }

        compiledWorkflow.id = workflow.id
        compiledWorkflow.createdAt = workflow.createdAt
        return (
            previewState: AutomationWorkflowDraftPreviewState(
                sourceName: preview.sourceName,
                sourceDirectory: preview.sourceDirectory,
                loadedAt: preview.loadedAt,
                document: preview.document,
                macroCatalog: preview.macroCatalog,
                projection: preview.projection,
                compiledWorkflow: compiledWorkflow
            ),
            copiedAssets: materializedPatch.copiedAssets
        )
    }

    private static func materializePatchAssetsIfNeeded(
        _ patch: AutomationWorkflowDraftPatchDocument,
        assetExtractions: [SemanticRecordingReviewAssetExtraction],
        sourceDirectory: URL?
    ) throws -> SemanticRecordingReviewMaterializedPatch {
        guard let sourceDirectory else {
            return SemanticRecordingReviewMaterializedPatch(
                patch: patch,
                packageDirectory: nil,
                copiedAssets: []
            )
        }

        let packageDirectory = try reviewAssetPackageDirectory(
            for: patch,
            sourceDirectory: sourceDirectory
        )
        let materialized = try SemanticRecordingReviewAssetMaterializer.materialize(
            patch: patch,
            assetExtractions: assetExtractions,
            readArtifact: { path in
                let ref = try RecordingArtifactRef(path)
                let url = sourceDirectory.appendingRecordingArtifactRef(ref)
                return try Data(contentsOf: url)
            },
            prepareAssetData: { data, extraction in
                guard let extraction else {
                    return data
                }
                return try croppedPNGData(from: data, extraction: extraction)
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
            packageDirectory: materialized.copiedAssets.isEmpty ? nil : packageDirectory,
            copiedAssets: materialized.copiedAssets
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

    private static func croppedPNGData(
        from data: Data,
        extraction: SemanticRecordingReviewAssetExtraction
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SemanticRecordingReviewPresenterError
                .couldNotDecodeFrameImage(extraction.sourceFrameImagePath)
        }
        guard let cropRect = cropRect(for: extraction.bounds, image: image),
              let cropped = image.cropping(to: cropRect) else {
            throw SemanticRecordingReviewPresenterError.emptyCropRegion(extraction.assetKey)
        }

        let representation = NSBitmapImageRep(cgImage: cropped)
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw SemanticRecordingReviewPresenterError.pngEncodingFailed(extraction.assetKey)
        }
        return pngData
    }

    private static func cropRect(
        for bounds: RecordingBounds,
        image: CGImage
    ) -> CGRect? {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect: CGRect
        switch bounds.coordinateSpace {
        case .normalizedFrame:
            rect = CGRect(
                x: bounds.rect.x * Double(image.width),
                y: bounds.rect.y * Double(image.height),
                width: bounds.rect.width * Double(image.width),
                height: bounds.rect.height * Double(image.height)
            )
        case .screenPixels, .displayPixels, .windowPixels, .contentPixels, .framePixels:
            rect = CGRect(
                x: bounds.rect.x,
                y: bounds.rect.y,
                width: bounds.rect.width,
                height: bounds.rect.height
            )
        }

        let clipped = rect.integral.intersection(imageBounds)
        guard !clipped.isNull,
              clipped.width >= 2,
              clipped.height >= 2 else {
            return nil
        }
        return clipped
    }

    private static func pixelPoint(
        for bounds: RecordingBounds,
        image: CGImage
    ) -> (x: Int, y: Int) {
        let rawX: Double
        let rawY: Double
        switch bounds.coordinateSpace {
        case .normalizedFrame:
            rawX = (bounds.rect.x + bounds.rect.width / 2) * Double(image.width)
            rawY = (bounds.rect.y + bounds.rect.height / 2) * Double(image.height)
        case .screenPixels, .displayPixels, .windowPixels, .contentPixels, .framePixels:
            rawX = bounds.rect.x + bounds.rect.width / 2
            rawY = bounds.rect.y + bounds.rect.height / 2
        }

        return (
            x: min(max(0, Int(rawX.rounded(.down))), max(0, image.width - 1)),
            y: min(max(0, Int(rawY.rounded(.down))), max(0, image.height - 1))
        )
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
        refs.append(contentsOf: bundle.redactedFrames.map(\.redactedImageRef))
        refs.append(contentsOf: bundle.redactedVideos.map(\.redactedVideoRef))

        var seen = Set<String>()
        return refs
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
    }
}

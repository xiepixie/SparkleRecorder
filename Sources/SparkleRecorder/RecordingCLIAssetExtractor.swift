import AppKit
import CryptoKit
import Foundation
import SparkleRecorderCore
import SparkleRecorderTooling

struct RecordingCLIAssetExtractionResult {
    var name: String
    var sourceArtifactRef: RecordingArtifactRef
    var materializedAsset: SemanticRecordingReviewMaterializedAsset
    var visualAsset: AutomationWorkflowDraftVisualImageAsset
    var evidence: [RecordingEvidenceReference]
}

enum RecordingCLIAssetExtractor {
    static func extract(
        bundle: SemanticRecordingBundle,
        bundleDirectory: URL?,
        sourceRoot: URL?,
        frameID: UUID,
        region: RecordingBounds,
        kind: SemanticRecordingCLIAssetExtractionKind,
        name: String,
        outputRoot: URL
    ) throws -> RecordingCLIAssetExtractionResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw WorkflowCLIError(
                "missingArgument",
                "recording asset extract requires --name <asset-name>.",
                path: "--name"
            )
        }
        guard let frame = bundle.frames.first(where: { $0.id == frameID }) else {
            throw WorkflowCLIError(
                "unknownFrame",
                "Recording bundle does not contain frame '\(frameID.uuidString)'.",
                path: "--frame"
            )
        }
        guard let resolvedSourceRoot = sourceRoot ?? bundleDirectory else {
            throw WorkflowCLIError(
                "artifactRootRequired",
                "Fixture asset extraction requires --source-root <fixture-artifact-dir>; stored bundles use their bundle directory by default.",
                path: "--source-root"
            )
        }

        let sourceArtifactRef = bundle.redactedFrame(frameID: frame.id)?.redactedImageRef ?? frame.imageRef
        let sourceURL = try artifactURL(
            ref: sourceArtifactRef,
            root: resolvedSourceRoot,
            optionPath: "--source-root"
        )
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw WorkflowCLIError(
                "missingSourceArtifact",
                "Source frame artifact '\(sourceArtifactRef.path)' was not found under '\(resolvedSourceRoot.path)'.",
                path: sourceArtifactRef.path
            )
        }

        let sourceImage = try cgImage(at: sourceURL)
        let cropRect = try cropRect(for: region, image: sourceImage)
        guard let croppedImage = sourceImage.cropping(to: cropRect) else {
            throw WorkflowCLIError(
                "invalidRegion",
                "Could not crop the requested region from the source frame.",
                path: "--region"
            )
        }
        let pngData = try pngData(for: croppedImage)
        let digest = sha256(pngData)
        let assetKey = assetKey(
            name: trimmedName,
            recordingID: bundle.id,
            kind: kind
        )
        let destinationPath = "assets/\(kind.materializedKind.directoryName)/\(assetKey).png"
        guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(destinationPath) == destinationPath else {
            throw WorkflowCLIError(
                "unsafeDestinationPath",
                "Unsafe asset destination '\(destinationPath)'.",
                path: destinationPath
            )
        }
        let destinationURL = try outputURL(
            root: outputRoot,
            relativePath: destinationPath,
            optionPath: "--output-root"
        )
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: destinationURL, options: .atomic)

        let visualAsset = AutomationWorkflowDraftVisualImageAsset(
            key: assetKey,
            label: trimmedName,
            path: destinationPath,
            sha256: digest,
            sourceFrameID: frame.id,
            sourceSurfaceID: frame.surfaceID,
            sourceArtifactPath: sourceArtifactRef.path,
            sourceBounds: draftRect(region.rect),
            sourceBoundsSpace: draftRegionSpace(region.coordinateSpace)
        )
        let materializedAsset = SemanticRecordingReviewMaterializedAsset(
            kind: kind.materializedKind,
            key: assetKey,
            sourcePath: sourceArtifactRef.path,
            destinationPath: destinationPath,
            sha256: digest
        )
        let evidence = [
            RecordingEvidenceReference(
                frameID: frame.id,
                eventIDs: frame.relatedEventIDs,
                observationIDs: [],
                artifactRef: sourceArtifactRef,
                bounds: region,
                summary: "Frame region was extracted as a draft-compatible visual asset."
            )
        ]

        return RecordingCLIAssetExtractionResult(
            name: trimmedName,
            sourceArtifactRef: sourceArtifactRef,
            materializedAsset: materializedAsset,
            visualAsset: visualAsset,
            evidence: evidence
        )
    }

    private static func artifactURL(
        ref: RecordingArtifactRef,
        root: URL,
        optionPath: String
    ) throws -> URL {
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let artifactURL = root
            .appendingRecordingArtifactRef(ref)
            .standardizedFileURL
        let artifactPath = artifactURL.resolvingSymlinksInPath().path
        let rootPath = rootURL.path
        guard artifactPath == rootPath || artifactPath.hasPrefix(rootPath + "/") else {
            throw WorkflowCLIError(
                "unsafeSourceArtifactPath",
                "Artifact ref '\(ref.path)' escapes source root '\(root.path)'.",
                path: optionPath
            )
        }
        return artifactURL
    }

    private static func outputURL(
        root: URL,
        relativePath: String,
        optionPath: String
    ) throws -> URL {
        guard AutomationWorkflowDraftVisualAssets.normalizedRelativeAssetPath(relativePath) == relativePath else {
            throw WorkflowCLIError(
                "unsafeDestinationPath",
                "Unsafe output asset path '\(relativePath)'.",
                path: relativePath
            )
        }
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let outputURL = relativePath
            .split(separator: "/")
            .map(String.init)
            .reduce(root.standardizedFileURL) { partial, component in
                partial.appendingPathComponent(component, isDirectory: false)
            }
        let outputPath = outputURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(outputURL.lastPathComponent)
            .path
        let rootPath = rootURL.path
        guard outputPath == rootPath || outputPath.hasPrefix(rootPath + "/") else {
            throw WorkflowCLIError(
                "unsafeOutputPath",
                "Output path '\(relativePath)' escapes output root '\(root.path)'.",
                path: optionPath
            )
        }
        return outputURL
    }

    private static func cgImage(at url: URL) throws -> CGImage {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw WorkflowCLIError(
                "unreadableSourceImage",
                "Could not decode source frame image at '\(url.path)'.",
                path: url.path
            )
        }
        return cgImage
    }

    private static func cropRect(
        for bounds: RecordingBounds,
        image: CGImage
    ) throws -> CGRect {
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let requested: CGRect
        switch bounds.coordinateSpace {
        case .normalizedFrame:
            requested = CGRect(
                x: CGFloat(bounds.rect.x * Double(image.width)),
                y: CGFloat(bounds.rect.y * Double(image.height)),
                width: CGFloat(bounds.rect.width * Double(image.width)),
                height: CGFloat(bounds.rect.height * Double(image.height))
            )
        case .screenPixels, .displayPixels, .windowPixels, .contentPixels, .framePixels:
            requested = CGRect(
                x: CGFloat(bounds.rect.x),
                y: CGFloat(bounds.rect.y),
                width: CGFloat(bounds.rect.width),
                height: CGFloat(bounds.rect.height)
            )
        }

        let clipped = requested.integral.intersection(imageBounds)
        guard !clipped.isNull,
              clipped.width >= 1,
              clipped.height >= 1 else {
            throw WorkflowCLIError(
                "regionOutsideFrame",
                "Requested region does not overlap the source frame.",
                path: "--region"
            )
        }
        return clipped
    }

    private static func pngData(for image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw WorkflowCLIError("pngEncodingFailed", "Could not encode extracted asset as PNG.")
        }
        return data
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func assetKey(
        name: String,
        recordingID: UUID,
        kind: SemanticRecordingCLIAssetExtractionKind
    ) -> String {
        let suffix = kind == .baseline ? "baseline" : "template"
        return "sr_\(shortID(recordingID))_\(safeStem(name))_\(suffix)"
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    private static func safeStem(_ value: String) -> String {
        let stem = value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "_"
            }
            .reduce(into: "") { partial, character in
                if partial.last == "_" && character == "_" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return stem.isEmpty ? "asset" : stem
    }

    private static func draftRect(_ rect: RecordingRect) -> RectValue {
        RectValue(
            x: CGFloat(rect.x),
            y: CGFloat(rect.y),
            width: CGFloat(rect.width),
            height: CGFloat(rect.height)
        )
    }

    private static func draftRegionSpace(
        _ space: RecordingCoordinateSpace
    ) -> AutomationOCRSearchRegionSpace {
        switch space {
        case .screenPixels, .displayPixels, .framePixels:
            return .displayAbsolute
        case .windowPixels:
            return .windowLocal
        case .contentPixels:
            return .contentLocal
        case .normalizedFrame:
            return .displayNormalized
        }
    }
}

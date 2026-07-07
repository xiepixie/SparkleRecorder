import Foundation
import SparkleRecorderCore

struct SemanticRecordingArtifactFileAuditor {
    static func summary(
        bundle: SemanticRecordingBundle,
        bundleDirectory: URL?
    ) -> SemanticRecordingCLIArtifactFileSummary? {
        guard let bundleDirectory else {
            return nil
        }

        let refs = artifactRefs(bundle: bundle)
        guard !refs.isEmpty else {
            return SemanticRecordingCLIArtifactFileSummary(evidence: [])
        }

        let evidence = refs.map { kind, ref in
            fileEvidence(
                kind: kind,
                ref: ref,
                bundleDirectory: bundleDirectory
            )
        }
        return SemanticRecordingCLIArtifactFileSummary(evidence: evidence)
    }

    private static func artifactRefs(
        bundle: SemanticRecordingBundle
    ) -> [(SemanticRecordingCLIArtifactFileKind, RecordingArtifactRef)] {
        var refs: [(SemanticRecordingCLIArtifactFileKind, RecordingArtifactRef)] = []
        refs.append(contentsOf: bundle.videoSegments.map { (.video, $0.artifactRef) })
        refs.append(contentsOf: bundle.redactedVideos.map { (.redactedVideo, $0.redactedVideoRef) })
        refs.append(contentsOf: bundle.frames.map { (.frame, $0.imageRef) })
        refs.append(contentsOf: bundle.redactedFrames.map { (.redactedFrame, $0.redactedImageRef) })
        refs.append(contentsOf: bundle.sourcePreviews.compactMap { preview in
            preview.artifactRef.map { (.sourcePreview, $0) }
        })
        refs.append(contentsOf: bundle.runtimeSamples.map { (.runtimeSample, $0.artifactRef) })
        refs.append(contentsOf: bundle.previewComparisons.compactMap { comparison in
            comparison.diffArtifactRef.map { (.diff, $0) }
        })
        return refs
    }

    private static func fileEvidence(
        kind: SemanticRecordingCLIArtifactFileKind,
        ref: RecordingArtifactRef,
        bundleDirectory: URL
    ) -> SemanticRecordingCLIArtifactFileEvidence {
        let rootURL = bundleDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let artifactURL = bundleDirectory
            .appendingRecordingArtifactRef(ref)
            .standardizedFileURL
        let artifactPath = artifactURL.resolvingSymlinksInPath().path
        let rootPath = rootURL.path
        guard artifactPath == rootPath || artifactPath.hasPrefix(rootPath + "/") else {
            return SemanticRecordingCLIArtifactFileEvidence(
                kind: kind,
                ref: ref,
                status: .unsafe,
                reason: "Artifact ref resolves outside bundle directory."
            )
        }

        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: artifactURL.path, isDirectory: &isDirectory) else {
            return SemanticRecordingCLIArtifactFileEvidence(
                kind: kind,
                ref: ref,
                status: .missing
            )
        }
        guard !isDirectory.boolValue else {
            return SemanticRecordingCLIArtifactFileEvidence(
                kind: kind,
                ref: ref,
                status: .directory
            )
        }

        let byteCount = (try? fileManager.attributesOfItem(atPath: artifactURL.path)[.size] as? NSNumber)?
            .intValue
        if (byteCount ?? 0) <= 0 {
            return SemanticRecordingCLIArtifactFileEvidence(
                kind: kind,
                ref: ref,
                status: .empty,
                byteCount: byteCount
            )
        }

        return SemanticRecordingCLIArtifactFileEvidence(
            kind: kind,
            ref: ref,
            status: .present,
            byteCount: byteCount
        )
    }
}

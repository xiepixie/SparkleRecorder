import CryptoKit
import Foundation
import SparkleRecorderCore

struct MacroReconstructionPackageArtifact: Codable, Equatable, Sendable {
    var path: String
    var sha256: String
}

struct MacroReconstructionPackageReport: Codable, Equatable, Sendable {
    var packageVersion: String? = MacroReconstructionPackage.currentVersion
    var sourceRevision: String
    var visualEvidenceIncluded: Bool
    var mechanicalEvidenceIncluded: Bool = false
    var sourceEventsMatchRecording: Bool = false
    var artifacts: [MacroReconstructionPackageArtifact]
    var warnings: [String]
}

enum MacroReconstructionPackageError: Error {
    case outputExists
    case sourceNeedsSanitization
    case unsafeArtifact
}

enum MacroReconstructionPackage {
    static let currentVersion = MacroReconstructionContractVersions.package

    static func export(
        source: SavedMacro, bundle: SemanticRecordingBundle? = nil,
        bundleDirectory: URL? = nil, includeVisualEvidence: Bool = false,
        objective: MacroReconstructionObjective = .robust, to output: URL
    ) throws -> MacroReconstructionPackageReport {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: output.path) else { throw MacroReconstructionPackageError.outputExists }
        if let bundle {
            let plan = SemanticRecordingPlayableSanitizationPlanner.plan(for: source, bundle: bundle)
            guard plan.sanitizedEvents(from: source.events) == source.events else {
                throw MacroReconstructionPackageError.sourceNeedsSanitization
            }
        }
        let template = try MacroReconstructionCandidateTemplate.document(source: source)
        let revision = template.sourceRevision
        let actions = try MacroActionReconstructor.reconstruct(events: source.events, sourceRevision: revision)
        var report = MacroReconstructionPackageReport(sourceRevision: revision,
            visualEvidenceIncluded: false, artifacts: [], warnings: [])
        var verifiedProvenance: RecordingReconstructionProvenance?
        var exportedVideoPaths: [UUID: String] = [:]
        var exportedFramePaths: [UUID: String] = [:]
        let staging = output.deletingLastPathComponent().appendingPathComponent(".reconstruction-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func write<T: Encodable>(_ value: T, _ name: String) throws {
            try encoder.encode(value).write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        let sourceContext = MacroReconstructionSourceContext(source: source, sourceRevision: revision)
        let harness = MacroReconstructionHarnessIndex(
            sourceRevision: revision,
            macroID: source.id,
            objective: objective
        )
        let authoringContract = MacroReconstructionAuthoringContract(objective: objective)
        try write(harness, "harness.json")
        try write(authoringContract, "authoring-contract.json")
        try write(sourceContext, "source-context.json")
        try MacroCandidateAuthoringProjection.encode(template)
            .write(to: staging.appendingPathComponent("candidate-template.json"), options: .atomic)
        let actionContext = MacroReconstructionActionContextProjector.document(
            actions: actions,
            events: source.events,
            surfaceContexts: sourceContext.surfaces,
            sourceRevision: revision
        )
        try write(actionContext, "reconstruction.json")
        if let provenance = bundle?.reconstructionProvenance, provenance.matchesSourceEvents(source.events) {
            verifiedProvenance = provenance
            report.sourceEventsMatchRecording = true
            try write(provenance, "alignment.json")
            if let bundle, !bundle.inputEvidenceSamples.isEmpty {
                try write(bundle.inputEvidenceSamples, "input-evidence.json")
                report.mechanicalEvidenceIncluded = true
            }
            if provenance.clockSegments.isEmpty { report.warnings.append("Video clock alignment is unavailable; do not assume video time equals event time.") }
        } else {
            report.warnings.append("Recording source event content is unverified or differs from this macro. Alignment is withheld; any supplied video, frames and observations belong to the original recording and must not be treated as synchronized evidence for this source.")
        }
        if let bundle, let bundleDirectory, includeVisualEvidence {
            let suppressed = !bundle.suppressions.isEmpty
            let redactionPlan = SemanticRecordingRedactionPlanner.plan(for: bundle)
            func copy(_ ref: RecordingArtifactRef, to destination: String) throws -> Bool {
                let root = bundleDirectory.resolvingSymlinksInPath().standardizedFileURL
                let url = root.appendingPathComponent(ref.path).resolvingSymlinksInPath().standardizedFileURL
                guard url.path.hasPrefix(root.path + "/") else { throw MacroReconstructionPackageError.unsafeArtifact }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    report.warnings.append("Missing evidence: \(ref.path)"); return false
                }
                let target = staging.appendingPathComponent(destination)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: target)
                let digest = SHA256.hash(data: try Data(contentsOf: target)).map { String(format: "%02x", $0) }.joined()
                report.artifacts.append(.init(path: destination, sha256: digest))
                return true
            }
            for segment in bundle.videoSegments {
                let redacted = bundle.redactedVideos.first { $0.videoSegmentID == segment.id }
                if suppressed {
                    // The current renderer uses session time minus segment.startTime.
                    // Permit its output only when exact, full-file clock evidence proves
                    // that mapping; nonzero uncertainty needs a renderer that pads masks.
                    guard hasRendererCompatibleClock(segment, bundle: bundle) else {
                        report.warnings.append("Video withheld: verified redaction clock alignment unavailable.")
                        continue
                    }
                    let ranges = redactionPlan.videoRangeRedactions.filter { $0.videoSegmentID == segment.id }
                    let requiredIDs = Set(ranges.flatMap(\.sourceSuppressionIDs))
                    guard let redacted, !requiredIDs.isEmpty,
                          redacted.sourceVideoRef == segment.artifactRef,
                          redacted.renderedRangeCount >= ranges.count,
                          requiredIDs.isSubset(of: Set(redacted.sourceSuppressionIDs)),
                          distinctArtifacts(redacted.redactedVideoRef, segment.artifactRef, in: bundleDirectory) else {
                        report.warnings.append("Video withheld: complete redaction evidence unavailable.")
                        continue
                    }
                }
                let ref = suppressed ? redacted!.redactedVideoRef : segment.artifactRef
                let ext = ref.path.lowercased().hasSuffix(".mp4") ? "mp4" : "mov"
                let destination = "video/\(segment.id.uuidString).\(ext)"
                if try copy(ref, to: destination) {
                    exportedVideoPaths[segment.id] = destination
                }
            }
            for frame in bundle.frames {
                let redacted = bundle.redactedFrames.first { $0.frameID == frame.id }
                if suppressed {
                    guard let planned = redactionPlan.frameRedactions.first(where: { $0.frameID == frame.id }),
                          let redacted, !planned.sourceSuppressionIDs.isEmpty,
                          redacted.sourceImageRef == frame.imageRef,
                          redacted.renderedMaskCount >= planned.masks.count,
                          Set(planned.sourceSuppressionIDs).isSubset(of: Set(redacted.sourceSuppressionIDs)),
                          distinctArtifacts(redacted.redactedImageRef, frame.imageRef, in: bundleDirectory) else {
                        report.warnings.append("Frame withheld: complete redaction evidence unavailable.")
                        continue
                    }
                }
                let destination = "frames/\(frame.id.uuidString).png"
                if try copy(suppressed ? redacted!.redactedImageRef : frame.imageRef, to: destination) {
                    exportedFramePaths[frame.id] = destination
                }
            }
            report.visualEvidenceIncluded = !report.artifacts.isEmpty
        } else {
            report.warnings.append("No visual bytes included. Export with explicit visual inclusion to provide permitted video/frames.")
        }
        if let provenance = verifiedProvenance,
           let bundle,
           !exportedVideoPaths.isEmpty || !exportedFramePaths.isEmpty {
            let guide = try MacroVisualInspectionGuideProjector.project(
                events: source.events,
                sourceRevision: revision,
                provenance: provenance,
                videoSegments: bundle.videoSegments,
                frames: bundle.frames,
                observations: bundle.suppressions.isEmpty ? bundle.visualObservations : [],
                exportedVideoPaths: exportedVideoPaths,
                exportedFramePaths: exportedFramePaths
            )
            try write(guide, "visual-inspection.json")
        }
        try write(report, "manifest.json")
        try fm.moveItem(at: staging, to: output)
        return report
    }

    private static func distinctArtifacts(_ redacted: RecordingArtifactRef, _ source: RecordingArtifactRef, in root: URL) -> Bool {
        root.appendingPathComponent(redacted.path).resolvingSymlinksInPath().standardizedFileURL
            != root.appendingPathComponent(source.path).resolvingSymlinksInPath().standardizedFileURL
    }

    private static func hasRendererCompatibleClock(_ segment: RecordingVideoSegment, bundle: SemanticRecordingBundle) -> Bool {
        guard let segments = bundle.reconstructionProvenance?.clockSegments,
              let mapping = try? RecordingVideoClockMapping(segments: segments, tolerance: 0),
              let clock = mapping.segments.first(where: { $0.id == segment.id.uuidString }),
              clock.maximumError == 0,
              mapping.videoTime(forRecordingTime: segment.startTime, segmentID: clock.id) == 0,
              mapping.videoTime(forRecordingTime: segment.startTime + segment.duration, segmentID: clock.id) == segment.duration else { return false }
        return clock.anchors.allSatisfy { $0.videoTime == $0.recordingTime - segment.startTime }
    }

}

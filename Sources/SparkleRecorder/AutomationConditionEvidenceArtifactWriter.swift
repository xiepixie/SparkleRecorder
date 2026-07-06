import AppKit
import CoreGraphics
import Foundation
import SparkleRecorderCore

struct AutomationConditionEvidenceArtifactSample: @unchecked Sendable {
    var runID: UUID
    var workflowID: UUID
    var taskID: UUID
    var conditionID: UUID
    var image: CGImage
    var displayBounds: RectValue
    var resolvedSearchRegion: RectValue?
    var sampleAt: Date

    init(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        conditionID: UUID,
        image: CGImage,
        displayBounds: RectValue,
        resolvedSearchRegion: RectValue?,
        sampleAt: Date
    ) {
        self.runID = runID
        self.workflowID = workflowID
        self.taskID = taskID
        self.conditionID = conditionID
        self.image = image
        self.displayBounds = displayBounds
        self.resolvedSearchRegion = resolvedSearchRegion
        self.sampleAt = sampleAt
    }
}

struct AutomationConditionEvidenceArtifactWriter: Sendable {
    var saveSample: @Sendable (AutomationConditionEvidenceArtifactSample) async -> [AutomationConditionDiagnosticArtifact]

    init(
        saveSample: @escaping @Sendable (AutomationConditionEvidenceArtifactSample) async -> [AutomationConditionDiagnosticArtifact]
    ) {
        self.saveSample = saveSample
    }

    static let inactive = AutomationConditionEvidenceArtifactWriter { _ in [] }

    static func fileBacked(
        supportDirectory: URL = AutomationPersistence.defaultFileURL.deletingLastPathComponent()
    ) -> AutomationConditionEvidenceArtifactWriter {
        AutomationConditionEvidenceArtifactWriter { sample in
            await AutomationConditionEvidenceArtifactStore(
                supportDirectory: supportDirectory
            ).saveSample(sample)
        }
    }
}

private struct AutomationConditionEvidenceArtifactStore: Sendable {
    let supportDirectory: URL

    func saveSample(
        _ sample: AutomationConditionEvidenceArtifactSample
    ) async -> [AutomationConditionDiagnosticArtifact] {
        await Task.detached(priority: .utility) {
            saveSampleSynchronously(sample)
        }.value
    }

    private func saveSampleSynchronously(
        _ sample: AutomationConditionEvidenceArtifactSample
    ) -> [AutomationConditionDiagnosticArtifact] {
        let rootURL = supportDirectory.appendingPathComponent("AutomationEvidence", isDirectory: true)
        let runURL = rootURL.appendingPathComponent(sample.runID.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
        } catch {
            return []
        }

        var artifacts: [AutomationConditionDiagnosticArtifact] = []
        let sampleRelativePath = relativePath(
            runID: sample.runID,
            filename: "condition-last-sample.png"
        )
        let sampleURL = supportDirectory.appendingPathComponent(sampleRelativePath)
        if writePNG(sample.image, to: sampleURL) {
            artifacts.append(AutomationConditionDiagnosticArtifact(
                id: "lastSampleImage",
                title: "Last sample",
                kind: .displaySampleImage,
                relativePath: sampleRelativePath,
                pixelBounds: sample.displayBounds,
                createdAt: sample.sampleAt
            ))
        }

        guard let clippedRegion = clippedRegion(sample.resolvedSearchRegion, image: sample.image),
              let croppedImage = sample.image.cropping(to: clippedRegion) else {
            return artifacts
        }

        let regionRelativePath = relativePath(
            runID: sample.runID,
            filename: "condition-region-sample.png"
        )
        let regionURL = supportDirectory.appendingPathComponent(regionRelativePath)
        if writePNG(croppedImage, to: regionURL) {
            artifacts.append(AutomationConditionDiagnosticArtifact(
                id: "regionSampleImage",
                title: "Watched region",
                kind: .regionSampleImage,
                relativePath: regionRelativePath,
                pixelBounds: RectValue(
                    x: clippedRegion.origin.x,
                    y: clippedRegion.origin.y,
                    width: clippedRegion.width,
                    height: clippedRegion.height
                ),
                createdAt: sample.sampleAt
            ))
        }

        return artifacts
    }

    private func relativePath(runID: UUID, filename: String) -> String {
        "AutomationEvidence/\(runID.uuidString)/\(filename)"
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func clippedRegion(_ region: RectValue?, image: CGImage) -> CGRect? {
        guard let region else {
            return nil
        }
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let requested = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        let clipped = requested.intersection(imageBounds).integral
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }
        return clipped
    }
}

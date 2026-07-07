import AppKit
import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Semantic Recording Review Pixel Sampling Tests")
@MainActor
struct SemanticRecordingReviewPixelSamplingTests {
    @Test("Review presenter samples pixel color from recorded frame artifact")
    func reviewPresenterSamplesPixelColorFromRecordedFrameArtifact() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle-review-pixel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var bundle = SemanticRecordingFixture.checkoutBundle()
        let frameID = SemanticRecordingFixture.afterClickFrameID
        let frame = try #require(bundle.frames.first { $0.id == frameID })
        let frameURL = temporaryDirectory.appendingRecordingArtifactRef(frame.imageRef)
        try FileManager.default.createDirectory(
            at: frameURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writePNG(
            rgba: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ],
            width: 2,
            height: 2,
            to: frameURL
        )

        let sourcePreviewID = UUID(uuidString: "75000000-0000-0000-0000-000000000001")!
        let observationID = UUID(uuidString: "75000000-0000-0000-0000-000000000002")!
        let bounds = RecordingBounds(
            rect: RecordingRect(x: 1, y: 1, width: 1, height: 1),
            coordinateSpace: .framePixels
        )
        bundle.sourcePreviews.append(RecordingSourcePreviewReference(
            id: sourcePreviewID,
            kind: .pixelSample,
            recordingID: bundle.id,
            frameID: frameID,
            eventID: SemanticRecordingFixture.waitEventID,
            surfaceID: SemanticRecordingFixture.surfaceID,
            bounds: bounds,
            imageSize: RecordingImageSize(width: 1, height: 1),
            createdAt: bundle.createdAt,
            recordingTime: frame.recordingTime,
            label: "Ready color pixel"
        ))
        bundle.visualObservations.append(RecordingVisualObservation(
            id: observationID,
            kind: .pixelSample,
            recordingTime: frame.recordingTime,
            frameID: frameID,
            sourcePreviewRefID: sourcePreviewID,
            bounds: bounds,
            confidence: 1,
            score: 0.98,
            provider: "SparkleRecorder.test",
            labels: ["readyColor"],
            createdAt: bundle.createdAt
        ))

        let projection = SemanticRecordingReviewProjection(
            bundle: bundle,
            selectedEventID: SemanticRecordingFixture.waitEventID,
            selectedFrameID: frameID
        )
        let candidate = try #require(
            projection.selectedFrame?.conditionCandidates.first {
                $0.kind == .pixelMatched && $0.observationID == observationID
            }
        )

        let sample = try SemanticRecordingReviewPresenter.pixelColorSample(
            for: candidate,
            bundle: bundle,
            bundleDirectory: temporaryDirectory
        )

        #expect(sample.colorHex == "#FFFFFF")
        #expect(sample.pixelX == 1)
        #expect(sample.pixelY == 1)
        #expect(sample.observationID == observationID)
        #expect(sample.sourcePreviewRefID == sourcePreviewID)
        #expect(sample.observationMetadataPatch["colorHex"] == "#FFFFFF")

        let index = try #require(bundle.visualObservations.firstIndex { $0.id == observationID })
        bundle.visualObservations[index].metadata.merge(sample.observationMetadataPatch) { _, new in new }

        let result = try SemanticRecordingReviewDraftPatchBuilder.makePatch(
            bundle: bundle,
            request: SemanticRecordingReviewDraftPatchRequest(
                candidate: candidate,
                threshold: 0.96
            )
        )

        #expect(result.condition.type == "pixelMatched")
        #expect(result.condition.colorHex == "#FFFFFF")
        #expect(result.condition.threshold == 0.96)
        #expect(result.condition.regionRef == "sr_00000001_ready_color_pixel_00000001_region")
    }

    private func writePNG(
        rgba: [UInt8],
        width: Int,
        height: Int,
        to url: URL
    ) throws {
        let image = try makeImage(width: width, height: height, rgba: rgba)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    private func makeImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        let data = Data(rgba)
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}

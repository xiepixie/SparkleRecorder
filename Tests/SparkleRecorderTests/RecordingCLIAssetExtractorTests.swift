import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore
@testable import SparkleRecorderTooling

@Suite("Recording CLI Asset Extractor Tests")
struct RecordingCLIAssetExtractorTests {
    @Test("Extractor materializes a draft-compatible visual asset")
    func extractorMaterializesDraftCompatibleVisualAsset() throws {
        let recordingID = UUID(uuidString: "12345678-0000-0000-0000-000000000001")!
        let frameID = UUID(uuidString: "12345678-0000-0000-0000-000000000002")!
        let eventID = UUID(uuidString: "12345678-0000-0000-0000-000000000003")!
        let fixture = try makeFixture(
            recordingID: recordingID,
            frameID: frameID,
            eventID: eventID
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let region = RecordingBounds(
            rect: RecordingRect(x: 1, y: 1, width: 2, height: 2),
            coordinateSpace: .framePixels
        )
        let result = try RecordingCLIAssetExtractor.extract(
            bundle: fixture.bundle,
            bundleDirectory: fixture.sourceRoot,
            sourceRoot: nil,
            frameID: frameID,
            region: region,
            kind: .imageTemplate,
            name: " Checkout Button ",
            outputRoot: fixture.outputRoot
        )

        #expect(result.name == "Checkout Button")
        #expect(result.materializedAsset.key == "sr_12345678_checkout_button_template")
        #expect(result.materializedAsset.kind == .image)
        #expect(result.materializedAsset.destinationPath == "assets/images/sr_12345678_checkout_button_template.png")
        #expect(result.materializedAsset.sha256.count == 64)
        #expect(result.visualAsset.sourceFrameID == frameID)
        #expect(result.visualAsset.sourceSurfaceID == "window:test")
        #expect(result.visualAsset.sourceBounds == RectValue(x: 1, y: 1, width: 2, height: 2))
        #expect(result.visualAsset.sourceBoundsSpace == .displayAbsolute)
        #expect(result.evidence.first?.eventIDs == [eventID])
        #expect(result.evidence.first?.bounds == region)

        let outputURL = fixture.outputRoot.appendingPathComponent(result.materializedAsset.destinationPath)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect((try Data(contentsOf: outputURL)).isEmpty == false)
    }

    @Test("Extractor keeps path and frame failures behind its interface")
    func extractorKeepsFailuresBehindItsInterface() throws {
        let recordingID = UUID(uuidString: "87654321-0000-0000-0000-000000000001")!
        let frameID = UUID(uuidString: "87654321-0000-0000-0000-000000000002")!
        let eventID = UUID(uuidString: "87654321-0000-0000-0000-000000000003")!
        let fixture = try makeFixture(
            recordingID: recordingID,
            frameID: frameID,
            eventID: eventID
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let missingFrameID = UUID(uuidString: "87654321-0000-0000-0000-000000000099")!
        let region = RecordingBounds(
            rect: RecordingRect(x: 0, y: 0, width: 2, height: 2),
            coordinateSpace: .framePixels
        )

        do {
            _ = try RecordingCLIAssetExtractor.extract(
                bundle: fixture.bundle,
                bundleDirectory: fixture.sourceRoot,
                sourceRoot: nil,
                frameID: missingFrameID,
                region: region,
                kind: .baseline,
                name: "Status",
                outputRoot: fixture.outputRoot
            )
            Issue.record("Expected unknown-frame failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "unknownFrame")
            #expect(error.path == "--frame")
        }

        try FileManager.default.removeItem(at: fixture.sourceRoot.appendingPathComponent("frames/source.png"))
        do {
            _ = try RecordingCLIAssetExtractor.extract(
                bundle: fixture.bundle,
                bundleDirectory: fixture.sourceRoot,
                sourceRoot: nil,
                frameID: frameID,
                region: region,
                kind: .baseline,
                name: "Status",
                outputRoot: fixture.outputRoot
            )
            Issue.record("Expected missing-source-artifact failure")
        } catch let error as WorkflowCLIError {
            #expect(error.code == "missingSourceArtifact")
            #expect(error.path == "frames/source.png")
        }
    }

    private func makeFixture(
        recordingID: UUID,
        frameID: UUID,
        eventID: UUID
    ) throws -> (root: URL, sourceRoot: URL, outputRoot: URL, bundle: SemanticRecordingBundle) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleRecorder-asset-extractor-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("recording", isDirectory: true)
        let outputRoot = root.appendingPathComponent("draft", isDirectory: true)
        let frameURL = sourceRoot.appendingPathComponent("frames/source.png")
        try FileManager.default.createDirectory(
            at: frameURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        try pngData(width: 4, height: 4).write(to: frameURL, options: .atomic)

        let frame = RecordingFrameReference(
            id: frameID,
            recordingTime: 1,
            imageRef: try RecordingArtifactRef("frames/source.png"),
            imageSize: RecordingImageSize(width: 4, height: 4),
            source: .manual,
            surfaceID: "window:test",
            relatedEventIDs: [eventID]
        )
        let bundle = SemanticRecordingBundle(
            id: recordingID,
            frames: [frame]
        )
        return (root, sourceRoot, outputRoot, bundle)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let representation = NSBitmapImageRep(cgImage: image)
        return try #require(representation.representation(using: .png, properties: [:]))
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SparkleRecorder

@Suite("Run evidence screenshot thumbnails")
struct RunEvidenceScreenshotThumbnailTests {
    @Test("Desktop screenshots are decoded to bounded previews")
    func boundedPreview() async throws {
        let context = try #require(CGContext(data: nil, width: 4096, height: 2048,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let data = bytes as Data
        let preview = try #require(await Task.detached {
            RunEvidenceScreenshotThumbnail.make(from: data)
        }.value)
        #expect(preview.width == 1024)
        #expect(preview.height == 512)
    }

    @Test("Invalid image data leaves the preview unavailable")
    func invalidImage() {
        #expect(RunEvidenceScreenshotThumbnail.make(from: Data("not an image".utf8)) == nil)
        #expect(RunEvidenceScreenshotThumbnail.make(from: Data(), maximumPixelSize: 0) == nil)
    }
}

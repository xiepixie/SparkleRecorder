import AppKit
import CoreGraphics
import Testing
@testable import SparkleRecorder
@testable import SparkleRecorderCore

@Suite("Automation OCR Region Picker Selection Tests")
@MainActor
struct AutomationOCRRegionPickerSelectionTests {
    @Test("Automatic selection prefers content then window before display bounds")
    func automaticSelectionPrefersMostStableAvailableSpace() {
        let contentSelection = AutomationScreenRegionPickerSelection(
            regionSelection: AutomationOCRSearchRegionSelection(
                displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
                selectedDisplayRegion: RectValue(x: 200, y: 160, width: 100, height: 80),
                windowFrame: RectValue(x: 100, y: 100, width: 500, height: 400),
                contentFrame: RectValue(x: 150, y: 140, width: 400, height: 320)
            ),
            windowSummary: nil,
            preview: nil
        )

        let windowSelection = AutomationScreenRegionPickerSelection(
            regionSelection: AutomationOCRSearchRegionSelection(
                displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
                selectedDisplayRegion: RectValue(x: 200, y: 160, width: 100, height: 80),
                windowFrame: RectValue(x: 100, y: 100, width: 500, height: 400)
            ),
            windowSummary: nil,
            preview: nil
        )

        let displaySelection = AutomationScreenRegionPickerSelection(
            regionSelection: AutomationOCRSearchRegionSelection(
                displayBounds: RectValue(x: 0, y: 0, width: 1_000, height: 800),
                selectedDisplayRegion: RectValue(x: 200, y: 160, width: 100, height: 80)
            ),
            windowSummary: nil,
            preview: nil
        )

        #expect(contentSelection.resolvedSpace(for: .automatic) == .contentNormalized)
        #expect(windowSelection.resolvedSpace(for: .automatic) == .windowNormalized)
        #expect(displaySelection.resolvedSpace(for: .automatic) == .displayAbsolute)
        #expect(contentSelection.resolvedSpace(for: .displayNormalized) == .displayNormalized)
    }

    @Test("Capture preview samples pixel color")
    func capturePreviewSamplesPixelColor() throws {
        let image = try makeTestImage(
            width: 2,
            height: 2,
            rgba: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255
            ]
        )
        let preview = AutomationRegionCapturePreview(
            image: NSImage(cgImage: image, size: NSSize(width: 2, height: 2)),
            pixelWidth: 2,
            pixelHeight: 2,
            windowSummary: nil
        )

        #expect(preview.colorHex(atPixelX: 0, y: 0) == "#FF0000")
        #expect(preview.colorHex(atPixelX: 1, y: 0) == "#00FF00")
        #expect(preview.colorHex(atPixelX: 0, y: 1) == "#0000FF")
        #expect(preview.colorHex(atPixelX: 5, y: 5) == "#FFFFFF")
    }

    private func makeTestImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
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

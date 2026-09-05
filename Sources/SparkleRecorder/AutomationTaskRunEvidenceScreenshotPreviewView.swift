import AppKit
import ImageIO
import SwiftUI

struct AutomationTaskRunEvidenceScreenshotPreviewView: View {
    let screenshotData: Data
    let loadedAt: Date

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 128)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                    )
                    .accessibilityLabel(String(localized: "Run result screenshot preview", table: "Automation"))
            } else {
                Label(String(localized: "Screenshot preview unavailable", table: "Common"), systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: loadedAt) {
            let data = screenshotData
            let thumbnail = await Task.detached(priority: .userInitiated) {
                RunEvidenceScreenshotThumbnail.make(from: data)
            }.value
            guard !Task.isCancelled else { return }
            image = thumbnail
        }
    }
}

/// Decode and downsample off the main actor. A full desktop screenshot can be
/// many megapixels; the evidence card displays only a 128-point preview.
enum RunEvidenceScreenshotThumbnail {
    nonisolated static func make(from data: Data, maximumPixelSize: Int = 1024) -> CGImage? {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

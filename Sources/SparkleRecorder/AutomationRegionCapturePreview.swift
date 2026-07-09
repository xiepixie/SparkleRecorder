import AppKit
import SwiftUI

struct AutomationRegionCaptureWindowSummary {
    var appName: String?
    var bundleIdentifier: String?
    var windowTitle: String?
    var windowID: UInt32?

    var displayTitle: String {
        let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !app.isEmpty, !title.isEmpty {
            return "\(app) · \(title)"
        }
        if !title.isEmpty {
            return title
        }
        if !app.isEmpty {
            return app
        }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        return NSLocalizedString("Top window", comment: "")
    }
}

struct AutomationRegionCapturePreview {
    var image: NSImage
    var pixelWidth: Int
    var pixelHeight: Int
    var windowSummary: AutomationRegionCaptureWindowSummary?

    var sourceTitle: String {
        windowSummary?.displayTitle ?? NSLocalizedString("Display crop", comment: "")
    }

    var pixelDetail: String {
        String(
            format: NSLocalizedString("%d x %d px · Original pixels", comment: ""),
            pixelWidth,
            pixelHeight
        )
    }

    var cgImage: CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    func colorHex(atPixelX x: Int, y: Int) -> String? {
        guard let cgImage else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let clampedX = min(max(0, x), max(0, bitmap.pixelsWide - 1))
        let clampedY = min(max(0, y), max(0, bitmap.pixelsHigh - 1))
        guard let color = bitmap.colorAt(x: clampedX, y: clampedY)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}

struct AutomationRegionCapturePixelSample {
    var normalizedX: Double
    var normalizedY: Double
    var pixelX: Int
    var pixelY: Int
    var colorHex: String?
}

struct AutomationRegionCapturePreviewView<Placeholder: View>: View {
    let preview: AutomationRegionCapturePreview?
    let tint: Color
    var selectedPixel: CGPoint? = nil
    var onPickPixel: ((AutomationRegionCapturePixelSample) -> Void)? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 7) {
                previewCanvas(preview)
                .frame(maxWidth: .infinity, minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Label(preview.sourceTitle, systemImage: "macwindow")
                        .font(.caption)
                        .foregroundStyle(tint)
                        .lineLimit(2)
                    Text(preview.pixelDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            placeholder()
        }
    }

    private func previewCanvas(_ preview: AutomationRegionCapturePreview) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.22))

            Image(nsImage: preview.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: preview.image.size.width, maxHeight: preview.image.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(6)

            GeometryReader { proxy in
                if let selectedPixel,
                   let point = renderedPoint(for: selectedPixel, in: proxy.size, preview: preview) {
                    Circle()
                        .strokeBorder(tint, lineWidth: 2)
                        .background(Circle().fill(Color.black.opacity(0.28)))
                        .frame(width: 13, height: 13)
                        .position(point)
                        .allowsHitTesting(false)
                }

                if let onPickPixel {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    if let sample = pixelSample(
                                        at: value.location,
                                        in: proxy.size,
                                        preview: preview
                                    ) {
                                        onPickPixel(sample)
                                    }
                                }
                        )
                        .help(NSLocalizedString("Click preview to sample pixel color", comment: ""))
                }
            }
        }
    }

    private func pixelSample(
        at location: CGPoint,
        in size: CGSize,
        preview: AutomationRegionCapturePreview
    ) -> AutomationRegionCapturePixelSample? {
        guard let imageRect = renderedImageRect(in: size, preview: preview),
              imageRect.contains(location) else {
            return nil
        }

        let normalizedX = (location.x - imageRect.minX) / imageRect.width
        let normalizedY = (location.y - imageRect.minY) / imageRect.height
        let pixelX = min(
            max(0, Int((normalizedX * CGFloat(preview.pixelWidth)).rounded(.down))),
            max(0, preview.pixelWidth - 1)
        )
        let pixelY = min(
            max(0, Int((normalizedY * CGFloat(preview.pixelHeight)).rounded(.down))),
            max(0, preview.pixelHeight - 1)
        )

        return AutomationRegionCapturePixelSample(
            normalizedX: Double(normalizedX),
            normalizedY: Double(normalizedY),
            pixelX: pixelX,
            pixelY: pixelY,
            colorHex: preview.colorHex(atPixelX: pixelX, y: pixelY)
        )
    }

    private func renderedPoint(
        for normalizedPoint: CGPoint,
        in size: CGSize,
        preview: AutomationRegionCapturePreview
    ) -> CGPoint? {
        guard let imageRect = renderedImageRect(in: size, preview: preview) else {
            return nil
        }
        return CGPoint(
            x: imageRect.minX + min(max(0, normalizedPoint.x), 1) * imageRect.width,
            y: imageRect.minY + min(max(0, normalizedPoint.y), 1) * imageRect.height
        )
    }

    private func renderedImageRect(
        in size: CGSize,
        preview: AutomationRegionCapturePreview
    ) -> CGRect? {
        let logicalWidth = preview.image.size.width
        let logicalHeight = preview.image.size.height
        
        guard logicalWidth > 0, logicalHeight > 0 else {
            return nil
        }

        let inset: CGFloat = 6
        let availableWidth = max(1, size.width - inset * 2)
        let availableHeight = max(1, size.height - inset * 2)
        let scale = min(
            availableWidth / logicalWidth,
            availableHeight / logicalHeight,
            1.0
        )
        let renderedWidth = logicalWidth * scale
        let renderedHeight = logicalHeight * scale
        return CGRect(
            x: (size.width - renderedWidth) / 2,
            y: (size.height - renderedHeight) / 2,
            width: renderedWidth,
            height: renderedHeight
        )
    }
}

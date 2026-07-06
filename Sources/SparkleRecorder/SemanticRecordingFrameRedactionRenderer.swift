import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SparkleRecorderCore

enum SemanticRecordingFrameRedactionRendererError: Error, Equatable, Sendable {
    case sourceImageIsDirectory(String)
    case sourceImageMissing(String)
    case imageDecodeFailed(String)
    case bitmapContextCreationFailed(String)
    case pngEncodingFailed(String)
    case noRenderableMasks(UUID)
}

struct SemanticRecordingFrameRedactionRenderer {
    func render(
        _ redaction: SemanticRecordingFrameRedaction,
        sourceURL: URL,
        outputURL: URL
    ) throws -> SemanticRecordingRenderedFrameRedaction {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw SemanticRecordingFrameRedactionRendererError
                .sourceImageMissing(redaction.sourceImageRef.path)
        }
        guard !isDirectory.boolValue else {
            throw SemanticRecordingFrameRedactionRendererError
                .sourceImageIsDirectory(redaction.sourceImageRef.path)
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SemanticRecordingFrameRedactionRendererError
                .imageDecodeFailed(redaction.sourceImageRef.path)
        }

        let maskRects = redaction.masks.compactMap { maskRect(for: $0.bounds, image: image) }
        guard !maskRects.isEmpty else {
            throw SemanticRecordingFrameRedactionRendererError
                .noRenderableMasks(redaction.frameID)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SemanticRecordingFrameRedactionRendererError
                .bitmapContextCreationFailed(redaction.sourceImageRef.path)
        }

        let imageRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: imageRect)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for rect in maskRects {
            context.fill(rect)
        }

        guard let redactedImage = context.makeImage(),
              let pngData = NSBitmapImageRep(cgImage: redactedImage)
                .representation(using: .png, properties: [:]) else {
            throw SemanticRecordingFrameRedactionRendererError
                .pngEncodingFailed(redaction.redactedImageRef.path)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)

        return SemanticRecordingRenderedFrameRedaction(
            frameID: redaction.frameID,
            sourceImageRef: redaction.sourceImageRef,
            redactedImageRef: redaction.redactedImageRef,
            renderedMaskCount: maskRects.count,
            sourceSuppressionIDs: redaction.sourceSuppressionIDs
        )
    }

    private func maskRect(
        for bounds: RecordingBounds,
        image: CGImage
    ) -> CGRect? {
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let requested: CGRect
        switch bounds.coordinateSpace {
        case .normalizedFrame:
            requested = CGRect(
                x: bounds.rect.x * Double(image.width),
                y: bounds.rect.y * Double(image.height),
                width: bounds.rect.width * Double(image.width),
                height: bounds.rect.height * Double(image.height)
            )
        case .screenPixels, .displayPixels, .windowPixels, .contentPixels, .framePixels:
            requested = CGRect(
                x: bounds.rect.x,
                y: bounds.rect.y,
                width: bounds.rect.width,
                height: bounds.rect.height
            )
        }

        let clipped = requested.standardized.intersection(imageBounds).integral
        guard !clipped.isNull,
              clipped.width >= 1,
              clipped.height >= 1 else {
            return nil
        }
        return clipped
    }
}

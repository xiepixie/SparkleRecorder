import CoreGraphics
import Foundation
import OSLog
import SparkleRecorderCore

/// Owns the live meaning of a TextAnchor: target-surface selection, stable window
/// capture, current content-relative geometry, OCR matching, repeated-occurrence
/// ranking, and conversion back to a screen-space match.
@available(macOS 14.0, *)
final class PlaybackTextTargetResolver: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.sparklerecorder.mac", category: "PlaybackTextTargetResolver")
    private let visionDetector: VisionDetector

    init(visionDetector: VisionDetector = VisionDetector()) {
        self.visionDetector = visionDetector
    }

    func resolve(
        event: RecordedEvent,
        context: PlaybackContext,
        anchor: TextAnchor
    ) async throws -> ResolvedTextAnchorMatch {
        let target = try resolveTarget(event: event, context: context, anchor: anchor)
        let image = try await ScreenCaptureService.shared.captureWindow(
            bundleIdentifier: target.surface.bundleIdentifier,
            title: target.surface.windowTitle,
            recordedWindowID: target.surface.recordedWindowId,
            expectedFrame: target.windowFrame.cgRect
        )
        let geometry = TextAnchorGeometryProjection.resolve(
            anchor,
            contentFrame: target.contentFrame,
            recordedWindowFrame: target.surface.recordedFrame,
            currentWindowFrame: target.windowFrame
        )
        let prepared = prepareImage(
            image,
            searchRegion: geometry.searchRegion,
            windowFrame: target.windowFrame
        )
        let detections = try await visionDetector.detectText(in: prepared.image)
        let candidates = detections.map {
            TextAnchorMatchCandidate(
                text: $0.text,
                normalizedBounds: RectValue($0.boundingBox),
                confidence: Double($0.confidence)
            )
        }
        guard let best = TextAnchorMatchRanking.bestMatch(
            anchor: anchor,
            candidates: candidates,
            detectionFrame: prepared.detectionFrame,
            observedFrame: geometry.observedFrame
        ) else {
            throw VisionDetectorError.textNotMatched
        }

        logger.debug("OCR matched text '\(best.recognizedText)' at \(best.screenFrame.cgRect.debugDescription)")
        return best
    }

    private struct TargetContext {
        var surface: PlaybackSurface
        var windowFrame: RectValue
        var contentFrame: RectValue?
    }

    private func resolveTarget(
        event: RecordedEvent,
        context: PlaybackContext,
        anchor: TextAnchor
    ) throws -> TargetContext {
        guard let surfaceId = PlaybackTextSurfaceSelection.resolve(
            event: event,
            surfaces: context.surfaces
        ) else {
            throw PointResolveError.missingSurface(event.surfaceId ?? "nil")
        }

        guard let surface = context.surfaces[surfaceId],
              let windowFrame = context.currentSurfaceFrames[surfaceId] else {
            throw PointResolveError.missingSurface(event.surfaceId ?? "nil")
        }
        return TargetContext(
            surface: surface,
            windowFrame: windowFrame,
            contentFrame: context.currentContentFrames[surfaceId]
        )
    }

    private func prepareImage(
        _ image: CGImage,
        searchRegion: RectValue?,
        windowFrame: RectValue
    ) -> (image: CGImage, detectionFrame: RectValue) {
        guard let searchRegion, searchRegion.width > 0, searchRegion.height > 0 else {
            return (image, windowFrame)
        }

        let windowRect = windowFrame.cgRect
        let clampedSearch = searchRegion.cgRect.intersection(windowRect)
        guard !clampedSearch.isNull, clampedSearch.width > 1, clampedSearch.height > 1 else {
            return (image, windowFrame)
        }

        let nx = (clampedSearch.minX - windowRect.minX) / max(1, windowRect.width)
        let ny = (clampedSearch.minY - windowRect.minY) / max(1, windowRect.height)
        let nw = clampedSearch.width / max(1, windowRect.width)
        let nh = clampedSearch.height / max(1, windowRect.height)
        let pixelRect = CGRect(
            x: nx * CGFloat(image.width),
            y: ny * CGFloat(image.height),
            width: nw * CGFloat(image.width),
            height: nh * CGFloat(image.height)
        ).integral
        let fullPixelRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = pixelRect.intersection(fullPixelRect)
        guard !cropRect.isNull, let cropped = image.cropping(to: cropRect) else {
            return (image, windowFrame)
        }

        return (
            cropped,
            RectValue(
                x: clampedSearch.minX,
                y: clampedSearch.minY,
                width: clampedSearch.width,
                height: clampedSearch.height
            )
        )
    }
}

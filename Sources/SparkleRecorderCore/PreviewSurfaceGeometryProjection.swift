import CoreGraphics
import Foundation

/// Pure geometry used by editor previews when the live Playback Surface cannot
/// currently be resolved. The preview is intentionally a visual model of the
/// recorded surface; it never changes playback resolution semantics.
public struct PreviewSurfaceGeometry: Equatable, Sendable {
    public let windowFrame: RectValue
    public let contentFrame: RectValue

    public init(windowFrame: RectValue, contentFrame: RectValue) {
        self.windowFrame = windowFrame
        self.contentFrame = contentFrame
    }
}

public struct PreviewPlaybackContextProjection: Sendable {
    public let context: PlaybackContext
    public let simulatedSurfaces: [String: PreviewSurfaceGeometry]

    public init(
        context: PlaybackContext,
        simulatedSurfaces: [String: PreviewSurfaceGeometry]
    ) {
        self.context = context
        self.simulatedSurfaces = simulatedSurfaces
    }
}

public enum PreviewSurfaceGeometryProjection {
    private static let maximumCanvasFraction: CGFloat = 0.68
    private static let minimumWindowSize = CGSize(width: 640, height: 420)

    /// Extends a live-only playback context with editor-only simulated geometry for
    /// Playback Surfaces that cannot currently be resolved. This keeps ordinary
    /// coordinate actions on the same PointResolver path as live playback while
    /// giving the editor a stable place to render them. The returned context must
    /// never be used for actual playback.
    public static func fillingUnavailableSurfaces(
        in context: PlaybackContext,
        canvas: RectValue
    ) -> PreviewPlaybackContextProjection {
        var projected = context
        var simulated: [String: PreviewSurfaceGeometry] = [:]

        for (surfaceID, surface) in context.surfaces {
            guard context.currentSurfaceFrames[surfaceID] == nil else { continue }

            let recordedContent = surface.recordedContentFrame ?? surface.recordedFrame
            let preview = centered(
                recordedWindowFrame: surface.recordedFrame,
                recordedContentFrame: recordedContent,
                in: canvas
            )
            projected.currentSurfaceFrames[surfaceID] = preview.windowFrame
            projected.currentContentFrames[surfaceID] = preview.contentFrame
            projected.currentTitleBarHeights[surfaceID] = max(
                0,
                preview.contentFrame.y - preview.windowFrame.y
            )
            simulated[surfaceID] = preview
        }

        return PreviewPlaybackContextProjection(
            context: projected,
            simulatedSurfaces: simulated
        )
    }

    public static func centered(
        recordedWindowFrame: RectValue,
        recordedContentFrame: RectValue?,
        in canvas: RectValue
    ) -> PreviewSurfaceGeometry {
        let sourceWidth = max(recordedWindowFrame.width, 1)
        let sourceHeight = max(recordedWindowFrame.height, 1)
        let maxWidth = max(1, canvas.width * maximumCanvasFraction)
        let maxHeight = max(1, canvas.height * maximumCanvasFraction)
        let scale = min(1, maxWidth / sourceWidth, maxHeight / sourceHeight)
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        let window = RectValue(
            x: canvas.x + (canvas.width - width) / 2,
            y: canvas.y + (canvas.height - height) / 2,
            width: width,
            height: height
        )

        let content: RectValue
        if let recordedContentFrame {
            content = map(
                recordedContentFrame,
                from: recordedWindowFrame,
                to: window
            )
        } else {
            content = window
        }
        return PreviewSurfaceGeometry(windowFrame: window, contentFrame: content)
    }

    /// Creates a stable synthetic source frame for legacy/unbound text anchors.
    /// The inferred frame is only an editor visualization aid; it is not persisted
    /// as a Playback Surface and cannot make an unbound action executable.
    public static func inferredRecordedWindowFrame(for anchor: TextAnchor) -> RectValue {
        var bounds: CGRect?

        func include(_ rect: CGRect) {
            guard rect.width > 0, rect.height > 0 else { return }
            bounds = bounds.map { $0.union(rect) } ?? rect
        }

        include(anchor.observedFrame.cgRect)
        if let searchRegion = anchor.searchRegion {
            include(searchRegion.cgRect)
        }
        if let fallback = anchor.coordinateFallback {
            include(CGRect(x: fallback.x - 1, y: fallback.y - 1, width: 2, height: 2))
        }

        guard let evidence = bounds else {
            return RectValue(x: 0, y: 0, width: minimumWindowSize.width, height: minimumWindowSize.height)
        }

        let padded = evidence.insetBy(dx: -80, dy: -72)
        let width = max(padded.width, minimumWindowSize.width)
        let height = max(padded.height, minimumWindowSize.height)
        return RectValue(
            x: padded.midX - width / 2,
            y: padded.midY - height / 2,
            width: width,
            height: height
        )
    }

    public static func resolveTextAnchor(
        _ anchor: TextAnchor,
        recordedWindowFrame: RectValue,
        preview: PreviewSurfaceGeometry,
        useContentNormalizedGeometry: Bool = true
    ) -> ResolvedTextAnchorGeometry {
        var resolved = useContentNormalizedGeometry
            ? TextAnchorGeometryProjection.resolve(anchor, contentFrame: preview.contentFrame)
            : ResolvedTextAnchorGeometry()

        if !useContentNormalizedGeometry || anchor.observedContentNormalizedFrame == nil {
            if anchor.observedFrame.width > 0, anchor.observedFrame.height > 0 {
                resolved.observedFrame = map(
                    anchor.observedFrame,
                    from: recordedWindowFrame,
                    to: preview.windowFrame
                )
            } else {
                resolved.observedFrame = nil
            }
        }

        if (!useContentNormalizedGeometry || anchor.searchContentNormalizedRegion == nil),
           let absoluteSearch = anchor.searchRegion {
            resolved.searchRegion = map(
                absoluteSearch,
                from: recordedWindowFrame,
                to: preview.windowFrame
            )
        }

        if (!useContentNormalizedGeometry || anchor.coordinateFallbackContentNormalized == nil),
           let absoluteFallback = anchor.coordinateFallback {
            resolved.coordinateFallback = map(
                absoluteFallback,
                from: recordedWindowFrame,
                to: preview.windowFrame
            )
        }

        return resolved
    }

    private static func map(
        _ rect: RectValue,
        from source: RectValue,
        to destination: RectValue
    ) -> RectValue {
        let nx = source.width > 0 ? (rect.x - source.x) / source.width : 0
        let ny = source.height > 0 ? (rect.y - source.y) / source.height : 0
        let nw = source.width > 0 ? rect.width / source.width : 0
        let nh = source.height > 0 ? rect.height / source.height : 0
        return RectValue(
            x: destination.x + nx * destination.width,
            y: destination.y + ny * destination.height,
            width: nw * destination.width,
            height: nh * destination.height
        )
    }

    private static func map(
        _ point: PointValue,
        from source: RectValue,
        to destination: RectValue
    ) -> PointValue {
        let nx = source.width > 0 ? (point.x - source.x) / source.width : 0
        let ny = source.height > 0 ? (point.y - source.y) / source.height : 0
        return PointValue(
            x: destination.x + nx * destination.width,
            y: destination.y + ny * destination.height
        )
    }

    public static func recordedDelta(
        dx: CGFloat,
        dy: CGFloat,
        recordedWindowFrame: RectValue,
        previewWindowFrame: RectValue
    ) -> CGSize {
        let scaleX = previewWindowFrame.width > 0
            ? recordedWindowFrame.width / previewWindowFrame.width
            : 1
        let scaleY = previewWindowFrame.height > 0
            ? recordedWindowFrame.height / previewWindowFrame.height
            : 1
        return CGSize(width: dx * scaleX, height: dy * scaleY)
    }

    public static func recordedRect(
        from previewRect: RectValue,
        previewContentFrame: RectValue,
        recordedContentFrame: RectValue
    ) -> (absolute: RectValue, normalized: RectValue) {
        let normalized = RectValue.normalized(
            rect: previewRect.cgRect,
            in: previewContentFrame.cgRect
        )
        return (
            denormalized(normalized, in: recordedContentFrame),
            normalized
        )
    }

    public static func recordedPoint(
        from previewPoint: PointValue,
        previewContentFrame: RectValue,
        recordedContentFrame: RectValue
    ) -> (absolute: PointValue, normalized: PointValue) {
        let nx = previewContentFrame.width > 0
            ? (previewPoint.x - previewContentFrame.x) / previewContentFrame.width
            : 0
        let ny = previewContentFrame.height > 0
            ? (previewPoint.y - previewContentFrame.y) / previewContentFrame.height
            : 0
        let normalized = PointValue(x: nx, y: ny)
        return (
            PointValue(
                x: recordedContentFrame.x + nx * recordedContentFrame.width,
                y: recordedContentFrame.y + ny * recordedContentFrame.height
            ),
            normalized
        )
    }

    private static func denormalized(_ rect: RectValue, in bounds: RectValue) -> RectValue {
        RectValue(
            x: bounds.x + rect.x * bounds.width,
            y: bounds.y + rect.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
    }
}

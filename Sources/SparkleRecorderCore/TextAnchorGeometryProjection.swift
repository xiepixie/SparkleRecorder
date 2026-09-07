import Foundation

/// Resolves a persisted text anchor against the current target content frame.
/// Content-normalized geometry is authoritative when a current content frame is
/// available; absolute geometry remains a compatibility fallback for legacy data.
public struct ResolvedTextAnchorGeometry: Equatable, Sendable {
    public var observedFrame: RectValue?
    public var searchRegion: RectValue?
    public var coordinateFallback: PointValue?

    public init(
        observedFrame: RectValue? = nil,
        searchRegion: RectValue? = nil,
        coordinateFallback: PointValue? = nil
    ) {
        self.observedFrame = observedFrame
        self.searchRegion = searchRegion
        self.coordinateFallback = coordinateFallback
    }
}

public enum TextAnchorGeometryProjection {
    public static func resolve(
        _ anchor: TextAnchor,
        contentFrame: RectValue?,
        recordedWindowFrame: RectValue,
        currentWindowFrame: RectValue
    ) -> ResolvedTextAnchorGeometry {
        let projected = resolve(anchor, contentFrame: contentFrame)
        guard approximatelySameWindow(recordedWindowFrame, currentWindowFrame) else {
            return projected
        }

        // Absolute text geometry is captured from the same screenshot the user
        // clicked. When the target window has not moved but content-normalized
        // geometry projects somewhere else, the normalized values were authored
        // against a different content frame (for example an incorrect browser
        // process falling back to a synthetic title-bar inset). In that case the
        // normalized geometry must not move the just-picked target.
        let dx = currentWindowFrame.x - recordedWindowFrame.x
        let dy = currentWindowFrame.y - recordedWindowFrame.y
        var repaired = projected

        if let projectedObserved = projected.observedFrame,
           anchor.observedFrame.width > 0,
           anchor.observedFrame.height > 0 {
            let absolute = translated(anchor.observedFrame, dx: dx, dy: dy)
            if !approximatelySameRect(projectedObserved, absolute) {
                repaired.observedFrame = absolute
            }
        }
        if let absoluteSearch = anchor.searchRegion,
           let projectedSearch = projected.searchRegion {
            let absolute = translated(absoluteSearch, dx: dx, dy: dy)
            if !approximatelySameRect(projectedSearch, absolute) {
                repaired.searchRegion = absolute
            }
        }
        if let absoluteFallback = anchor.coordinateFallback,
           let projectedFallback = projected.coordinateFallback {
            let absolute = PointValue(x: absoluteFallback.x + dx, y: absoluteFallback.y + dy)
            if hypot(projectedFallback.x - absolute.x, projectedFallback.y - absolute.y) > 3 {
                repaired.coordinateFallback = absolute
            }
        }
        return repaired
    }

    public static func resolve(
        _ anchor: TextAnchor,
        contentFrame: RectValue?
    ) -> ResolvedTextAnchorGeometry {
        ResolvedTextAnchorGeometry(
            observedFrame: resolveRect(
                normalized: anchor.observedContentNormalizedFrame,
                absolute: anchor.observedFrame,
                contentFrame: contentFrame,
                omitEmptyAbsolute: true
            ),
            searchRegion: resolveOptionalRect(
                normalized: anchor.searchContentNormalizedRegion,
                absolute: anchor.searchRegion,
                contentFrame: contentFrame
            ),
            coordinateFallback: resolvePoint(
                normalized: anchor.coordinateFallbackContentNormalized,
                absolute: anchor.coordinateFallback,
                contentFrame: contentFrame
            )
        )
    }

    private static func resolveRect(
        normalized: RectValue?,
        absolute: RectValue,
        contentFrame: RectValue?,
        omitEmptyAbsolute: Bool
    ) -> RectValue? {
        if let normalized, let contentFrame {
            return denormalized(normalized, in: contentFrame)
        }
        if omitEmptyAbsolute, absolute.width <= 0 || absolute.height <= 0 {
            return nil
        }
        return absolute
    }

    private static func resolveOptionalRect(
        normalized: RectValue?,
        absolute: RectValue?,
        contentFrame: RectValue?
    ) -> RectValue? {
        if let normalized, let contentFrame {
            return denormalized(normalized, in: contentFrame)
        }
        return absolute
    }

    private static func resolvePoint(
        normalized: PointValue?,
        absolute: PointValue?,
        contentFrame: RectValue?
    ) -> PointValue? {
        if let normalized, let contentFrame {
            return PointValue(
                x: contentFrame.x + normalized.x * contentFrame.width,
                y: contentFrame.y + normalized.y * contentFrame.height
            )
        }
        return absolute
    }

    private static func denormalized(_ rect: RectValue, in bounds: RectValue) -> RectValue {
        RectValue(
            x: bounds.x + rect.x * bounds.width,
            y: bounds.y + rect.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
    }

    private static func approximatelySameWindow(_ lhs: RectValue, _ rhs: RectValue) -> Bool {
        abs(lhs.x - rhs.x) <= 3
            && abs(lhs.y - rhs.y) <= 3
            && abs(lhs.width - rhs.width) <= 3
            && abs(lhs.height - rhs.height) <= 3
    }

    private static func approximatelySameRect(_ lhs: RectValue, _ rhs: RectValue) -> Bool {
        abs(lhs.x - rhs.x) <= 3
            && abs(lhs.y - rhs.y) <= 3
            && abs(lhs.width - rhs.width) <= 3
            && abs(lhs.height - rhs.height) <= 3
    }

    private static func translated(_ rect: RectValue, dx: CGFloat, dy: CGFloat) -> RectValue {
        RectValue(
            x: rect.x + dx,
            y: rect.y + dy,
            width: rect.width,
            height: rect.height
        )
    }
}

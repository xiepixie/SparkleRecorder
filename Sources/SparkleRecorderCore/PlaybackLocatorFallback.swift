import CoreGraphics

/// Resolves coordinate fallback after a text locator misses. Content-normalized
/// fallback geometry is preferred when it can be projected safely inside the
/// current target surface; ordinary PointResolver semantics remain the legacy
/// compatibility fallback.
public enum PlaybackLocatorFallback {
    public static func resolve(
        event: RecordedEvent,
        surfaceId: String,
        context: PlaybackContext,
        pointResolver: PointResolver = PointResolver()
    ) -> Result<CGPoint, PointResolveError> {
        let effectiveSurfaceID: String
        if event.textAnchor != nil {
            guard let resolved = PlaybackTextSurfaceSelection.resolve(
                event: event,
                surfaces: context.surfaces
            ) else {
                return .failure(.missingSurface(event.surfaceId ?? "nil"))
            }
            effectiveSurfaceID = resolved
        } else {
            effectiveSurfaceID = surfaceId
        }

        if let anchor = event.textAnchor,
           let windowFrame = context.currentSurfaceFrames[effectiveSurfaceID] {
            let geometry: ResolvedTextAnchorGeometry
            if let surface = context.surfaces[effectiveSurfaceID] {
                geometry = TextAnchorGeometryProjection.resolve(
                    anchor,
                    contentFrame: context.currentContentFrames[effectiveSurfaceID],
                    recordedWindowFrame: surface.recordedFrame,
                    currentWindowFrame: windowFrame
                )
            } else {
                geometry = TextAnchorGeometryProjection.resolve(
                    anchor,
                    contentFrame: context.currentContentFrames[effectiveSurfaceID]
                )
            }
            if let point = geometry.coordinateFallback?.cgPoint,
               CoordinateMapper().assertPointIsInsideWindow(point, in: windowFrame) {
                return .success(point)
            }
        }

        return pointResolver.resolve(event, context: context)
    }
}

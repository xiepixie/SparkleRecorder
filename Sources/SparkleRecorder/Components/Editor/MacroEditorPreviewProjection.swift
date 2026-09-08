import CoreGraphics
import Foundation
import SparkleRecorderCore

struct MacroEditorPreviewItem {
    let id: UUID
    let group: ActionGroup
    let order: Int
}

struct MacroEditorPreviewDisplayPlan {
    let items: [MacroEditorPreviewItem]
    let detailActionIDs: Set<UUID>
    let focusedActionID: UUID?

    static func make(
        rows: [ActionRow],
        selection: Set<UUID>,
        showsSelectedPreview: Bool,
        showsAllPaths: Bool
    ) -> MacroEditorPreviewDisplayPlan {
        let visibleRows = rows.enumerated().compactMap { index, row -> MacroEditorPreviewItem? in
            let isSelected = selection.contains(row.id)
            guard showsAllPaths || (showsSelectedPreview && isSelected) else { return nil }
            return MacroEditorPreviewItem(id: row.id, group: row.group, order: index + 1)
        }
        let visibleIDs = Set(visibleRows.map(\.id))
        let detailActionIDs = showsSelectedPreview
            ? selection.intersection(visibleIDs)
            : []

        return MacroEditorPreviewDisplayPlan(
            items: visibleRows,
            detailActionIDs: detailActionIDs,
            focusedActionID: detailActionIDs.count == 1 ? detailActionIDs.first : nil
        )
    }
}

struct TextPreviewGeometryEditContext {
    let eventIndices: [Int]
    let recordedContentFrame: RectValue
    let previewContentFrame: RectValue
    let storesNormalizedGeometry: Bool
}

struct CoordinatePreviewGeometryEditContext {
    let recordedWindowFrame: RectValue
    let previewWindowFrame: RectValue

    func recordedDelta(dx: CGFloat, dy: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        let delta = PreviewSurfaceGeometryProjection.recordedDelta(
            dx: dx,
            dy: dy,
            recordedWindowFrame: recordedWindowFrame,
            previewWindowFrame: previewWindowFrame
        )
        return (delta.width, delta.height)
    }
}

struct MacroEditorPreviewProjectionResult {
    let actions: [PreviewAction]
    let textEditContexts: [UUID: TextPreviewGeometryEditContext]
    let coordinateEditContexts: [UUID: CoordinatePreviewGeometryEditContext]
}

/// Projects Macro editor rows into screen-space preview actions.
///
/// The Module has one geometry rule: every Recorded Event resolves through the
/// same Preview Playback Context. That context contains live Playback Surface
/// geometry when available and editor-only simulated geometry otherwise.
/// Text Anchor presentation adds observed/search/fallback evidence on top of the
/// same surface projection; it does not own a separate window-position model.
enum MacroEditorPreviewProjector {
    static func project(
        items: [MacroEditorPreviewItem],
        events: [RecordedEvent],
        liveContext: PlaybackContext,
        previewCanvas: RectValue,
        activeScreenUnion: CGRect,
        hideMouseMoves: Bool
    ) -> MacroEditorPreviewProjectionResult {
        let surfaces = liveContext.surfaces
        let previewContextProjection = PreviewSurfaceGeometryProjection.fillingUnavailableSurfaces(
            in: liveContext,
            canvas: previewCanvas
        )
        let previewContext = previewContextProjection.context
        let resolver = PointResolver()

        var actions: [PreviewAction] = []
        var textEditContexts: [UUID: TextPreviewGeometryEditContext] = [:]
        var coordinateEditContexts: [UUID: CoordinatePreviewGeometryEditContext] = [:]

        for item in items {
            let group = item.group
            guard !group.kind.isPassiveWait,
                  !(group.kind == .mouseMove && hideMouseMoves) else {
                continue
            }

            var selectedPoint: CGPoint?
            var observedFrame: CGRect?
            var searchRegion: CGRect?
            var fallbackPoint: CGPoint?
            var targetText = group.textAnchor?.text
            var usesTextLocator = group.textAnchor != nil
            var surfaceBackdrop: PreviewSurfaceBackdrop?
            var targetSurfaceFrame: CGRect?
            var searchRegionIsExplicit = false
            var allowsGeometryEditing = false
            var usesCoordinateFallback = false
            var coordinateEditContext: CoordinatePreviewGeometryEditContext?

            let firstEvent = group.eventIndices.first.flatMap { index in
                events.indices.contains(index) ? events[index] : nil
            }
            let surfaceID = effectiveSurfaceID(
                events: events,
                eventIndices: group.eventIndices,
                surfaces: surfaces
            )

            if let surfaceID, let surface = surfaces[surfaceID] {
                if let liveFrame = liveContext.currentSurfaceFrames[surfaceID] {
                    targetSurfaceFrame = liveFrame.cgRect
                } else if let simulated = previewContextProjection.simulatedSurfaces[surfaceID] {
                    targetSurfaceFrame = simulated.windowFrame.cgRect
                    surfaceBackdrop = recordedSurfaceBackdrop(
                        surfaceID: surfaceID,
                        surface: surface,
                        preview: simulated
                    )
                    coordinateEditContext = CoordinatePreviewGeometryEditContext(
                        recordedWindowFrame: surface.recordedFrame,
                        previewWindowFrame: simulated.windowFrame
                    )
                }
            }

            if let firstEvent {
                usesTextLocator = usesTextLocator
                    || firstEvent.coordinateStrategy == .locatorOnly
                    || firstEvent.textAnchor != nil
                selectedPoint = try? resolver.resolve(firstEvent, context: previewContext).get()

                if let anchor = firstEvent.textAnchor {
                    targetText = anchor.text
                    searchRegionIsExplicit = anchor.searchRegion != nil
                        || anchor.searchContentNormalizedRegion != nil
                    usesCoordinateFallback = !group.kind.editsSemanticTextTarget
                        && firstEvent.locatorFallbackPolicy == .allowCoordinateFallback

                    let textProjection = projectTextAnchor(
                        anchor,
                        actionID: item.id,
                        eventIndices: group.eventIndices,
                        surfaceID: surfaceID,
                        surfaces: surfaces,
                        liveContext: liveContext,
                        simulatedSurfaces: previewContextProjection.simulatedSurfaces,
                        previewCanvas: previewCanvas,
                        activeScreenUnion: activeScreenUnion
                    )
                    observedFrame = textProjection.geometry.observedFrame?.cgRect
                    searchRegion = textProjection.geometry.searchRegion?.cgRect
                    fallbackPoint = textProjection.geometry.coordinateFallback?.cgPoint
                    targetSurfaceFrame = textProjection.targetSurfaceFrame ?? targetSurfaceFrame
                    surfaceBackdrop = textProjection.surfaceBackdrop ?? surfaceBackdrop
                    if let editContext = textProjection.editContext {
                        textEditContexts[item.id] = editContext
                        allowsGeometryEditing = true
                    }

                    if searchRegion == nil {
                        searchRegion = targetSurfaceFrame
                    }
                    selectedPoint = selectedPoint
                        ?? fallbackPoint
                        ?? observedFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
                }
            }

            let resolvedPath = resolvePath(
                for: group,
                events: events,
                context: previewContext,
                resolver: resolver
            )

            if group.kind == .mouseMove, let destination = resolvedPath.last {
                selectedPoint = destination
            }

            if group.kind.editsSemanticTextTarget {
                searchRegion = searchRegion ?? observedFrame
                observedFrame = nil
                fallbackPoint = nil
                selectedPoint = nil
            }

            let affordance = ActionGroupProjection.previewAffordance(
                for: group.kind,
                usesTextLocator: usesTextLocator
            )
            guard affordance != .none else { continue }
            if let coordinateEditContext,
               affordance.hasInteractiveAnchor || affordance.showsPath {
                coordinateEditContexts[item.id] = coordinateEditContext
            }

            actions.append(PreviewAction(
                id: item.id,
                kind: group.kind,
                affordance: affordance,
                selectedPoint: selectedPoint,
                dragPath: resolvedPath,
                observedFrame: observedFrame,
                searchRegion: searchRegion,
                fallbackPoint: fallbackPoint,
                targetText: targetText,
                surfaceBackdrop: surfaceBackdrop,
                targetSurfaceFrame: targetSurfaceFrame,
                searchRegionIsExplicit: searchRegionIsExplicit,
                allowsGeometryEditing: allowsGeometryEditing,
                usesCoordinateFallback: usesCoordinateFallback,
                clickCount: group.clickCount,
                duration: group.duration,
                scrollDeltaX: group.scrollDeltaX,
                scrollDeltaY: group.scrollDeltaY,
                mouseButton: group.mouseButton,
                themeColor: actionKindColor(group.kind),
                order: item.order
            ))
        }

        return MacroEditorPreviewProjectionResult(
            actions: actions,
            textEditContexts: textEditContexts,
            coordinateEditContexts: coordinateEditContexts
        )
    }

    private struct TextProjection {
        let geometry: ResolvedTextAnchorGeometry
        let targetSurfaceFrame: CGRect?
        let surfaceBackdrop: PreviewSurfaceBackdrop?
        let editContext: TextPreviewGeometryEditContext?
    }

    private static func projectTextAnchor(
        _ anchor: TextAnchor,
        actionID: UUID,
        eventIndices: [Int],
        surfaceID: String?,
        surfaces: [String: PlaybackSurface],
        liveContext: PlaybackContext,
        simulatedSurfaces: [String: PreviewSurfaceGeometry],
        previewCanvas: RectValue,
        activeScreenUnion: CGRect
    ) -> TextProjection {
        if let surfaceID, let surface = surfaces[surfaceID] {
            let recordedContentFrame = surface.recordedContentFrame ?? surface.recordedFrame

            if let currentWindowFrame = liveContext.currentSurfaceFrames[surfaceID] {
                let currentContentFrame = liveContext.currentContentFrames[surfaceID] ?? currentWindowFrame
                return TextProjection(
                    geometry: TextAnchorGeometryProjection.resolve(
                        anchor,
                        contentFrame: currentContentFrame,
                        recordedWindowFrame: surface.recordedFrame,
                        currentWindowFrame: currentWindowFrame
                    ),
                    targetSurfaceFrame: currentWindowFrame.cgRect,
                    surfaceBackdrop: nil,
                    editContext: TextPreviewGeometryEditContext(
                        eventIndices: eventIndices,
                        recordedContentFrame: recordedContentFrame,
                        previewContentFrame: currentContentFrame,
                        storesNormalizedGeometry: true
                    )
                )
            }

            let preview = simulatedSurfaces[surfaceID]
                ?? PreviewSurfaceGeometryProjection.centered(
                    recordedWindowFrame: surface.recordedFrame,
                    recordedContentFrame: recordedContentFrame,
                    in: previewCanvas
                )
            return TextProjection(
                geometry: PreviewSurfaceGeometryProjection.resolveTextAnchor(
                    anchor,
                    recordedWindowFrame: surface.recordedFrame,
                    preview: preview
                ),
                targetSurfaceFrame: preview.windowFrame.cgRect,
                surfaceBackdrop: recordedSurfaceBackdrop(
                    surfaceID: surfaceID,
                    surface: surface,
                    preview: preview
                ),
                editContext: TextPreviewGeometryEditContext(
                    eventIndices: eventIndices,
                    recordedContentFrame: recordedContentFrame,
                    previewContentFrame: preview.contentFrame,
                    storesNormalizedGeometry: true
                )
            )
        }

        let inferredRecordedWindow = PreviewSurfaceGeometryProjection.inferredRecordedWindowFrame(for: anchor)
        let inferredCenter = CGPoint(
            x: inferredRecordedWindow.x + inferredRecordedWindow.width / 2,
            y: inferredRecordedWindow.y + inferredRecordedWindow.height / 2
        )
        let usesLastRecordedPosition = hasAbsolutePreviewEvidence(anchor)
            && activeScreenUnion.contains(inferredCenter)
        let preview = usesLastRecordedPosition
            ? PreviewSurfaceGeometry(
                windowFrame: inferredRecordedWindow,
                contentFrame: inferredRecordedWindow
            )
            : PreviewSurfaceGeometryProjection.centered(
                recordedWindowFrame: inferredRecordedWindow,
                recordedContentFrame: inferredRecordedWindow,
                in: previewCanvas
            )

        return TextProjection(
            geometry: PreviewSurfaceGeometryProjection.resolveTextAnchor(
                anchor,
                recordedWindowFrame: inferredRecordedWindow,
                preview: preview,
                useContentNormalizedGeometry: false
            ),
            targetSurfaceFrame: preview.windowFrame.cgRect,
            surfaceBackdrop: PreviewSurfaceBackdrop(
                id: "unbound-\(actionID.uuidString)",
                frame: preview.windowFrame.cgRect,
                mode: usesLastRecordedPosition ? .unboundLastPosition : .unboundCentered,
                title: nil
            ),
            editContext: TextPreviewGeometryEditContext(
                eventIndices: eventIndices,
                recordedContentFrame: inferredRecordedWindow,
                previewContentFrame: preview.contentFrame,
                storesNormalizedGeometry: false
            )
        )
    }

    private static func resolvePath(
        for group: ActionGroup,
        events: [RecordedEvent],
        context: PlaybackContext,
        resolver: PointResolver
    ) -> [CGPoint] {
        group.eventIndices.compactMap { index -> CGPoint? in
            guard events.indices.contains(index) else { return nil }
            let event = events[index]
            if group.kind.previewsPointSequence,
               event.kind != .leftMouseDown,
               event.kind != .rightMouseDown,
               event.kind != .otherMouseDown {
                return nil
            }
            return try? resolver.resolve(event, context: context).get()
        }
    }

    private static func effectiveSurfaceID(
        events: [RecordedEvent],
        eventIndices: [Int],
        surfaces: [String: PlaybackSurface]
    ) -> String? {
        (try? MacroPlaybackSurfaceEditing.effectiveSurfaceID(
            in: events,
            eventIndices: eventIndices,
            surfaces: surfaces
        )) ?? nil
    }

    private static func recordedSurfaceBackdrop(
        surfaceID: String,
        surface: PlaybackSurface,
        preview: PreviewSurfaceGeometry
    ) -> PreviewSurfaceBackdrop {
        PreviewSurfaceBackdrop(
            id: "recorded-\(surfaceID)",
            frame: preview.windowFrame.cgRect,
            mode: .recordedLayout,
            title: surfaceTitle(surface)
        )
    }

    private static func hasAbsolutePreviewEvidence(_ anchor: TextAnchor) -> Bool {
        (anchor.observedFrame.width > 0 && anchor.observedFrame.height > 0)
            || ((anchor.searchRegion?.width ?? 0) > 0 && (anchor.searchRegion?.height ?? 0) > 0)
            || anchor.coordinateFallback != nil
    }

    private static func surfaceTitle(_ surface: PlaybackSurface) -> String? {
        let parts = [surface.appName, surface.windowTitle]
            .compactMap { value -> String? in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else {
                    return nil
                }
                return value
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

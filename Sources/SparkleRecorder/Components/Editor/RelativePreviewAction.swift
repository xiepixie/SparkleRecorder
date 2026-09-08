import Cocoa
import SwiftUI
import SparkleRecorderCore

/// Overlay-local counterpart of `PreviewAction` after the single
/// screen-to-SwiftUI coordinate conversion in `CoordinatePreviewOverlay`.
struct RelativePreviewAction: Identifiable {
    let id: UUID
    let kind: ActionGroupKind
    let affordance: ActionPreviewAffordance
    let selectedPoint: CGPoint?
    let dragPath: [CGPoint]
    let observedFrame: CGRect?
    let searchRegion: CGRect?
    let fallbackPoint: CGPoint?
    let targetText: String?
    let surfaceBackdrop: PreviewSurfaceBackdrop?
    let targetSurfaceFrame: CGRect?
    let searchRegionIsExplicit: Bool
    let allowsGeometryEditing: Bool
    let usesCoordinateFallback: Bool
    let clickCount: Int
    let duration: TimeInterval
    let scrollDeltaX: Int32?
    let scrollDeltaY: Int32?
    let mouseButton: Int64?
    let themeColor: Color
    let order: Int

    init(
        id: UUID,
        kind: ActionGroupKind,
        affordance: ActionPreviewAffordance,
        selectedPoint: CGPoint?,
        dragPath: [CGPoint],
        observedFrame: CGRect?,
        searchRegion: CGRect?,
        fallbackPoint: CGPoint?,
        targetText: String? = nil,
        surfaceBackdrop: PreviewSurfaceBackdrop? = nil,
        targetSurfaceFrame: CGRect? = nil,
        searchRegionIsExplicit: Bool = false,
        allowsGeometryEditing: Bool = false,
        usesCoordinateFallback: Bool = false,
        clickCount: Int = 1,
        duration: TimeInterval = 0,
        scrollDeltaX: Int32? = nil,
        scrollDeltaY: Int32? = nil,
        mouseButton: Int64? = nil,
        themeColor: Color,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.affordance = affordance
        self.selectedPoint = selectedPoint
        self.dragPath = dragPath
        self.observedFrame = observedFrame
        self.searchRegion = searchRegion
        self.fallbackPoint = fallbackPoint
        self.targetText = targetText
        self.surfaceBackdrop = surfaceBackdrop
        self.targetSurfaceFrame = targetSurfaceFrame
        self.searchRegionIsExplicit = searchRegionIsExplicit
        self.allowsGeometryEditing = allowsGeometryEditing
        self.usesCoordinateFallback = usesCoordinateFallback
        self.clickCount = clickCount
        self.duration = duration
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.mouseButton = mouseButton
        self.themeColor = themeColor
        self.order = order
    }

    @MainActor
    init(
        screenAction: PreviewAction,
        window: NSWindow,
        primaryScreenHeight: CGFloat
    ) {
        self.init(
            id: screenAction.id,
            kind: screenAction.kind,
            affordance: screenAction.affordance,
            selectedPoint: screenAction.selectedPoint.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            dragPath: screenAction.dragPath.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            observedFrame: screenAction.observedFrame.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            searchRegion: screenAction.searchRegion.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            fallbackPoint: screenAction.fallbackPoint.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            targetText: screenAction.targetText,
            surfaceBackdrop: screenAction.surfaceBackdrop.map {
                PreviewSurfaceBackdrop(
                    id: $0.id,
                    frame: screenToSwiftUI(
                        $0.frame,
                        window: window,
                        primaryScreenHeight: primaryScreenHeight
                    ),
                    mode: $0.mode,
                    title: $0.title
                )
            },
            targetSurfaceFrame: screenAction.targetSurfaceFrame.map {
                screenToSwiftUI($0, window: window, primaryScreenHeight: primaryScreenHeight)
            },
            searchRegionIsExplicit: screenAction.searchRegionIsExplicit,
            allowsGeometryEditing: screenAction.allowsGeometryEditing,
            usesCoordinateFallback: screenAction.usesCoordinateFallback,
            clickCount: screenAction.clickCount,
            duration: screenAction.duration,
            scrollDeltaX: screenAction.scrollDeltaX,
            scrollDeltaY: screenAction.scrollDeltaY,
            mouseButton: screenAction.mouseButton,
            themeColor: screenAction.themeColor,
            order: screenAction.order
        )
    }
}

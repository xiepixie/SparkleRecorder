import CoreGraphics
import Foundation
import SparkleRecorderCore
import SwiftUI

enum PreviewSurfaceBackdropMode: String {
    case recordedLayout
    case unboundLastPosition
    case unboundCentered
}

enum PreviewInteractionMetrics {
    static let pointHitRadius: CGFloat = 28
    static let fallbackHitRadius: CGFloat = 32
    static let pathHitTolerance: CGFloat = 10
    static let searchCornerVisualDiameter: CGFloat = 12
    static let searchCornerHitDiameter: CGFloat = 42
    static let searchMoveVisualSize = CGSize(width: 44, height: 18)
    static let searchMoveHitSize = CGSize(width: 58, height: 36)
    static let searchRegionMinimumSize = CGSize(width: 44, height: 30)
}

struct PreviewSurfaceBackdrop: Identifiable {
    let id: String
    let frame: CGRect
    let mode: PreviewSurfaceBackdropMode
    let title: String?
}

/// One editor preview action in Core Graphics screen coordinates.
/// `CoordinatePreviewOverlay` is the only Module that converts this geometry
/// into overlay-local SwiftUI coordinates.
struct PreviewAction: Identifiable {
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
}

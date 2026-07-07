import CoreGraphics
import Foundation

public struct RecordingCoordinateFields: Equatable, Sendable {
    public var windowLocalX: CGFloat?
    public var windowLocalY: CGFloat?
    public var windowNormalizedX: CGFloat?
    public var windowNormalizedY: CGFloat?
    public var contentLocalX: CGFloat?
    public var contentLocalY: CGFloat?
    public var contentNormalizedX: CGFloat?
    public var contentNormalizedY: CGFloat?
    public var coordinateBinding: CoordinateBinding

    public init(
        windowLocalX: CGFloat? = nil,
        windowLocalY: CGFloat? = nil,
        windowNormalizedX: CGFloat? = nil,
        windowNormalizedY: CGFloat? = nil,
        contentLocalX: CGFloat? = nil,
        contentLocalY: CGFloat? = nil,
        contentNormalizedX: CGFloat? = nil,
        contentNormalizedY: CGFloat? = nil,
        coordinateBinding: CoordinateBinding = .unbound
    ) {
        self.windowLocalX = windowLocalX
        self.windowLocalY = windowLocalY
        self.windowNormalizedX = windowNormalizedX
        self.windowNormalizedY = windowNormalizedY
        self.contentLocalX = contentLocalX
        self.contentLocalY = contentLocalY
        self.contentNormalizedX = contentNormalizedX
        self.contentNormalizedY = contentNormalizedY
        self.coordinateBinding = coordinateBinding
    }
}

public struct RecordingCoordinateBindingResult: Equatable, Sendable {
    public var fields: RecordingCoordinateFields
    public var updatedSurface: PlaybackSurface?

    public init(fields: RecordingCoordinateFields, updatedSurface: PlaybackSurface? = nil) {
        self.fields = fields
        self.updatedSurface = updatedSurface
    }
}

public enum RecordingCoordinateBinder {
    public static let fallbackContentFrameSource = "fallbackOuterFrame"

    public static func bind(
        location: CGPoint,
        targetSurfaceId: String?,
        surfaces: [String: PlaybackSurface]
    ) -> RecordingCoordinateBindingResult {
        guard let targetSurfaceId, let surface = surfaces[targetSurfaceId] else {
            return RecordingCoordinateBindingResult(fields: RecordingCoordinateFields())
        }

        let frame = surface.recordedFrame
        guard contains(location, in: frame) else {
            return RecordingCoordinateBindingResult(
                fields: RecordingCoordinateFields(coordinateBinding: .globalScreen)
            )
        }

        let contentFrame: RectValue
        var updatedSurface: PlaybackSurface?
        if let recordedContentFrame = surface.recordedContentFrame {
            contentFrame = recordedContentFrame
        } else {
            contentFrame = frame
            var fallbackSurface = surface
            fallbackSurface.recordedContentFrame = contentFrame
            fallbackSurface.contentFrameSource = fallbackContentFrameSource
            updatedSurface = fallbackSurface
        }

        let localX = location.x - frame.x
        let localY = location.y - frame.y
        let titleBarHeight = contentFrame.y - frame.y
        let clientHeight = max(CGFloat(1.0), frame.height - titleBarHeight)

        let contentLocalX = location.x - contentFrame.x
        let contentLocalY = location.y - contentFrame.y

        return RecordingCoordinateBindingResult(
            fields: RecordingCoordinateFields(
                windowLocalX: localX,
                windowLocalY: localY - titleBarHeight,
                windowNormalizedX: frame.width > 0 ? localX / frame.width : 0,
                windowNormalizedY: localY >= titleBarHeight ? (localY - titleBarHeight) / clientHeight : 0,
                contentLocalX: contentLocalX,
                contentLocalY: contentLocalY,
                contentNormalizedX: contentFrame.width > 0 ? contentLocalX / contentFrame.width : 0,
                contentNormalizedY: contentFrame.height > 0 ? contentLocalY / contentFrame.height : 0,
                coordinateBinding: .targetWindow
            ),
            updatedSurface: updatedSurface
        )
    }

    private static func contains(_ point: CGPoint, in frame: RectValue) -> Bool {
        point.x >= frame.x &&
        point.x <= frame.x + frame.width &&
        point.y >= frame.y &&
        point.y <= frame.y + frame.height
    }
}

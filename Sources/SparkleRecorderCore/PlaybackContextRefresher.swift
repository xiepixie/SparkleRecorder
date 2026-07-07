import CoreGraphics
import Foundation

public struct PlaybackSurfaceFrameResolution: Equatable, Sendable {
    public var outerFrame: RectValue
    public var contentFrame: RectValue
    public var titleBarHeight: CGFloat

    public init(
        outerFrame: RectValue,
        contentFrame: RectValue,
        titleBarHeight: CGFloat? = nil
    ) {
        self.outerFrame = outerFrame
        self.contentFrame = contentFrame
        self.titleBarHeight = titleBarHeight ?? max(0, contentFrame.y - outerFrame.y)
    }
}

public enum PlaybackContextRefresher {
    public static func refreshed(
        _ context: PlaybackContext,
        with resolutions: [String: PlaybackSurfaceFrameResolution],
        resetExisting: Bool = true
    ) -> PlaybackContext {
        var context = context
        refresh(&context, with: resolutions, resetExisting: resetExisting)
        return context
    }

    public static func refresh(
        _ context: inout PlaybackContext,
        with resolutions: [String: PlaybackSurfaceFrameResolution],
        resetExisting: Bool = true
    ) {
        if resetExisting {
            resetResolvedFrames(in: &context)
        }

        for (surfaceId, resolution) in resolutions {
            guard context.surfaces[surfaceId] != nil else { continue }
            context.currentSurfaceFrames[surfaceId] = resolution.outerFrame
            context.currentContentFrames[surfaceId] = resolution.contentFrame
            context.currentTitleBarHeights[surfaceId] = resolution.titleBarHeight
        }
    }

    public static func resetResolvedFrames(in context: inout PlaybackContext) {
        context.currentSurfaceFrames.removeAll()
        context.currentContentFrames.removeAll()
        context.currentTitleBarHeights.removeAll()
    }
}

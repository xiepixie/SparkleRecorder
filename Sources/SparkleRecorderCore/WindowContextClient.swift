import Foundation

public struct WindowContextClient: Sendable {
    public var resolveFrameResolutions: @Sendable ([String: PlaybackSurface]) -> [String: PlaybackSurfaceFrameResolution]
    public var activateSurface: @Sendable (PlaybackSurface) -> Void

    public init(
        resolveFrameResolutions: @escaping @Sendable ([String: PlaybackSurface]) -> [String: PlaybackSurfaceFrameResolution],
        activateSurface: @escaping @Sendable (PlaybackSurface) -> Void
    ) {
        self.resolveFrameResolutions = resolveFrameResolutions
        self.activateSurface = activateSurface
    }

    public static let none = WindowContextClient(
        resolveFrameResolutions: { _ in [:] },
        activateSurface: { _ in }
    )

    public func activateAll<S: Sequence>(_ surfaces: S) where S.Element == PlaybackSurface {
        for surface in surfaces {
            activateSurface(surface)
        }
    }

    @discardableResult
    public func refreshResolvedFrames(
        in context: inout PlaybackContext,
        surfaces: [String: PlaybackSurface]? = nil,
        resetExisting: Bool = true
    ) -> Set<String> {
        if resetExisting {
            PlaybackContextRefresher.resetResolvedFrames(in: &context)
        }

        let targetSurfaces = surfaces ?? context.surfaces
        let resolutions = resolveFrameResolutions(targetSurfaces)
        PlaybackContextRefresher.refresh(&context, with: resolutions, resetExisting: false)
        return Set(resolutions.keys)
    }
}

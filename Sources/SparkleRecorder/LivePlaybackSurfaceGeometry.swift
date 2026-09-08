import SparkleRecorderCore

/// App-layer adapter that resolves current macOS window geometry for persisted
/// Playback Surfaces. Playback and editor preview both use this Module so outer
/// and content-frame resolution cannot drift between the two call sites.
enum LivePlaybackSurfaceGeometry {
    static func resolveFrameResolutions(
        for surfaces: [String: PlaybackSurface],
        tracker: WindowTracker
    ) -> [String: PlaybackSurfaceFrameResolution] {
        let windows = tracker.resolveCurrentWindows(for: surfaces)
        return windows.reduce(into: [:]) { resolutions, entry in
            let (surfaceID, window) = entry
            guard surfaces[surfaceID] != nil else { return }
            let resolvedContent = WindowContentFrameResolver.resolveContentFrame(
                for: window.processID,
                outerFrame: window.frame
            )
            resolutions[surfaceID] = PlaybackSurfaceFrameResolution(
                outerFrame: window.frame,
                contentFrame: RectValue(resolvedContent.frame)
            )
        }
    }

    static func playbackContext(
        for macro: SavedMacro,
        tracker: WindowTracker = WindowTracker()
    ) -> PlaybackContext {
        var context = PlaybackContext(
            surfaces: macro.surfaces,
            coordinateMode: macro.followWindowOffset ? .boundWindowOffset : .screenAbsolute
        )
        PlaybackContextRefresher.refresh(
            &context,
            with: resolveFrameResolutions(for: macro.surfaces, tracker: tracker)
        )
        return context
    }
}

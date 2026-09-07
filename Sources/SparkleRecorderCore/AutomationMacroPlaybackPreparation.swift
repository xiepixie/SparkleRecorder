import CoreGraphics
import Foundation

/// Prepares a saved macro for unattended automation without mutating the accepted source.
///
/// Older recordings can contain pointer events with no coordinate binding even when the
/// event was captured inside one recorded target window. For unattended playback that
/// is unsafe: opening or moving the target window would leave those events at absolute
/// screen coordinates. When the intent is unambiguous, reconstruct the same target-window
/// coordinate fields the recorder writes today. Explicit global-screen input is preserved.
public enum AutomationMacroPlaybackPreparation {
    public static func prepare(_ macro: SavedMacro) -> SavedMacro {
        guard macro.followWindowOffset, !macro.surfaces.isEmpty else { return macro }

        var prepared = macro
        for index in prepared.events.indices {
            var event = prepared.events[index]
            guard event.kind.isMouse,
                  event.coordinateBinding == nil || event.coordinateBinding == .unbound,
                  let surfaceID = targetSurfaceID(for: event, surfaces: prepared.surfaces),
                  prepared.surfaces[surfaceID]?.recordedContentFrame != nil else {
                continue
            }

            let binding = RecordingCoordinateBinder.bind(
                location: CGPoint(x: event.x, y: event.y),
                targetSurfaceId: surfaceID,
                surfaces: prepared.surfaces
            )
            guard binding.fields.coordinateBinding == .targetWindow else { continue }

            event.surfaceId = surfaceID
            event.windowLocalX = binding.fields.windowLocalX
            event.windowLocalY = binding.fields.windowLocalY
            event.windowNormalizedX = binding.fields.windowNormalizedX
            event.windowNormalizedY = binding.fields.windowNormalizedY
            event.contentLocalX = binding.fields.contentLocalX
            event.contentLocalY = binding.fields.contentLocalY
            event.contentNormalizedX = binding.fields.contentNormalizedX
            event.contentNormalizedY = binding.fields.contentNormalizedY
            event.coordinateBinding = binding.fields.coordinateBinding
            prepared.events[index] = event
        }
        return prepared
    }

    private static func targetSurfaceID(
        for event: RecordedEvent,
        surfaces: [String: PlaybackSurface]
    ) -> String? {
        if let surfaceID = event.surfaceId, surfaces[surfaceID] != nil {
            return surfaceID
        }

        let matches = surfaces.compactMap { surfaceID, surface -> String? in
            contains(CGPoint(x: event.x, y: event.y), in: surface.recordedFrame) ? surfaceID : nil
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func contains(_ point: CGPoint, in frame: RectValue) -> Bool {
        point.x >= frame.x
            && point.x <= frame.x + frame.width
            && point.y >= frame.y
            && point.y <= frame.y + frame.height
    }
}

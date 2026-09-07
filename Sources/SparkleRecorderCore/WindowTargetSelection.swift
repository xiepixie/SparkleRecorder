import CoreGraphics

/// Pure selection policy for choosing the visible layer-zero window beneath a screen point.
/// Window server observations must be ordered front-to-back.
public enum WindowTargetSelection {
    public static func window(
        at point: CGPoint,
        windows: [PlaybackForegroundWindowObservation],
        excludingProcessID: Int32? = nil
    ) -> PlaybackForegroundWindowObservation? {
        windows.first { window in
            if let excludingProcessID, window.processID == excludingProcessID {
                return false
            }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { return false }
            return point.x >= frame.x
                && point.x <= frame.x + frame.width
                && point.y >= frame.y
                && point.y <= frame.y + frame.height
        }
    }
}

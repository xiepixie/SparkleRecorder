import CoreGraphics
import SparkleRecorderCore

/// App-edge Adapter for the ordered, layer-zero window-server observations used
/// by both recording and playback. Keeping this parsing in one place prevents
/// capture identity and playback verification from drifting apart.
enum WindowServerObservationAdapter {
    static func visibleWindows(onScreenOnly: Bool = true) -> [PlaybackForegroundWindowObservation] {
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? UInt32,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double,
                  let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 0,
                  height > 0 else {
                return nil
            }
            return PlaybackForegroundWindowObservation(
                id: id,
                processID: pid,
                frame: RectValue(x: x, y: y, width: width, height: height)
            )
        }
    }
}

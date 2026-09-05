import Foundation

/// Visible, layer-zero windows, ordered front to back by the window server.
public struct PlaybackForegroundWindowObservation: Equatable, Sendable {
    public var id: UInt32
    public var processID: Int32
    public var frame: RectValue
    public init(id: UInt32, processID: Int32, frame: RectValue) {
        self.id = id; self.processID = processID; self.frame = frame
    }
}

public enum PlaybackForegroundWindowVerification {
    /// Conservative fallback when an app exposes no usable AX window. App
    /// activation alone is insufficient, and coincident windows are ambiguous.
    public static func isReady(active: Bool, targetProcessID: Int32,
                               expectedFrame: RectValue,
                               windows: [PlaybackForegroundWindowObservation]) -> Bool {
        guard active, let front = windows.first, front.processID == targetProcessID else { return false }
        let matches = windows.filter { window in
            window.processID == targetProcessID &&
            abs(window.frame.x - expectedFrame.x) + abs(window.frame.y - expectedFrame.y) +
            abs(window.frame.width - expectedFrame.width) + abs(window.frame.height - expectedFrame.height) < 8
        }
        return matches.count == 1 && matches.first?.id == front.id
    }
}

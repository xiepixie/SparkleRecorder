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
    public static func targetProcessID(recordedFrame: RectValue, recordedWindowID: UInt32? = nil,
                                       windows: [PlaybackForegroundWindowObservation]) -> Int32? {
        let matches = windows.filter { window in
            if let recordedWindowID { return window.id == recordedWindowID }
            return abs(window.frame.x - recordedFrame.x) + abs(window.frame.y - recordedFrame.y) +
                abs(window.frame.width - recordedFrame.width) + abs(window.frame.height - recordedFrame.height) < 8
        }
        let processes = Set(matches.map(\.processID))
        return processes.count == 1 ? processes.first : nil
    }

    /// Conservative fallback when an app exposes no usable AX window. App
    /// activation alone is insufficient, and coincident windows are ambiguous.
    public static func isReady(active: Bool, targetProcessID: Int32,
                               recordedFrame: RectValue, recordedWindowID: UInt32? = nil,
                               windows: [PlaybackForegroundWindowObservation]) -> Bool {
        guard active, let front = windows.first, front.processID == targetProcessID else { return false }
        if let recordedWindowID {
            return front.id == recordedWindowID
        }
        let matches = windows.filter { window in
            window.processID == targetProcessID &&
            abs(window.frame.x - recordedFrame.x) + abs(window.frame.y - recordedFrame.y) +
            abs(window.frame.width - recordedFrame.width) + abs(window.frame.height - recordedFrame.height) < 8
        }
        return matches.count == 1 && matches.first?.id == front.id
    }
}

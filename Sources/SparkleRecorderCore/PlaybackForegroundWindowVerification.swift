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
    public static func frontmostMatchingWindowID(
        targetProcessID: Int32,
        recordedFrame: RectValue,
        windows: [PlaybackForegroundWindowObservation]
    ) -> UInt32? {
        windows.first { window in
            window.processID == targetProcessID &&
            abs(window.frame.x - recordedFrame.x) + abs(window.frame.y - recordedFrame.y) +
                abs(window.frame.width - recordedFrame.width) + abs(window.frame.height - recordedFrame.height) < 8
        }?.id
    }

    public static func targetProcessID(recordedFrame: RectValue, recordedWindowID: UInt32? = nil,
                                       windows: [PlaybackForegroundWindowObservation]) -> Int32? {
        let matches = matchingWindows(
            recordedFrame: recordedFrame,
            recordedWindowID: recordedWindowID,
            windows: windows
        )
        let processes = Set(matches.map(\.processID))
        return processes.count == 1 ? processes.first : nil
    }

    /// Conservative fallback when an app exposes no usable AX window. App
    /// activation alone is insufficient, and coincident windows are ambiguous.
    public static func isReady(active: Bool, targetProcessID: Int32,
                               recordedFrame: RectValue, recordedWindowID: UInt32? = nil,
                               windows: [PlaybackForegroundWindowObservation]) -> Bool {
        guard active, let front = windows.first, front.processID == targetProcessID else { return false }
        let matches = matchingWindows(
            recordedFrame: recordedFrame,
            recordedWindowID: recordedWindowID,
            windows: windows
        ).filter { $0.processID == targetProcessID }
        return matches.count == 1 && matches.first?.id == front.id
    }

    /// A CGWindowID is strong identity only while that exact window still exists.
    /// Once the recorded window has been destroyed and recreated, fall back to the
    /// recorded geometry instead of treating the stale ID as a permanent failure.
    private static func matchingWindows(
        recordedFrame: RectValue,
        recordedWindowID: UInt32?,
        windows: [PlaybackForegroundWindowObservation]
    ) -> [PlaybackForegroundWindowObservation] {
        if let recordedWindowID {
            let exact = windows.filter { $0.id == recordedWindowID }
            if !exact.isEmpty { return exact }
        }
        return windows.filter { window in
            abs(window.frame.x - recordedFrame.x) + abs(window.frame.y - recordedFrame.y) +
                abs(window.frame.width - recordedFrame.width) + abs(window.frame.height - recordedFrame.height) < 8
        }
    }
}

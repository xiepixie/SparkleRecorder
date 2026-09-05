import AppKit
import ApplicationServices
import SparkleRecorderCore

@MainActor
enum PlaybackTargetWindowForeground {
    static func prepare(app: NSRunningApplication, surfaces: [String: PlaybackSurface]) async -> Bool {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        // Use the same resolved frame as playback, rather than raising whichever
        // browser window happened to be frontmost when the macro was started.
        let frames = WindowTracker().resolveCurrentFrames(for: surfaces)
        guard let target = matchingWindow(application: application, surfaces: surfaces, frames: frames) else { return false }
        let handles = ForegroundWindowHandles(application: application, target: target)
        let handoff = PlaybackForegroundPreparation(request: {
            await MainActor.run {
                NSApp.yieldActivation(to: app)
                app.unhide()
                _ = app.activate(from: .current, options: [])
                AXUIElementSetAttributeValue(handles.target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(handles.target, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(handles.target, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, handles.target)
            }
        }, isReady: {
            await MainActor.run {
                guard app.isActive else { return false }
                var focused: CFTypeRef?
                guard AXUIElementCopyAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                      let focused, CFEqual(focused, handles.target) else { return false }
                return true
            }
        }, sleep: { try await Task.sleep(for: .milliseconds(100)) })
        return await handoff.prepare()
    }

    private static func matchingWindow(application: AXUIElement, surfaces: [String: PlaybackSurface], frames: [String: RectValue]) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        let entries = surfaces.sorted { $0.key < $1.key }
        guard let entry = entries.first else { return nil }
        let frame = frames[entry.key] ?? entry.value.recordedFrame
        var best: AXUIElement?
        var bestScore = -Double.infinity
        for window in windows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
            var point = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { continue }
            let distance = abs(point.x - frame.x) + abs(point.y - frame.y) + abs(size.width - frame.width) + abs(size.height - frame.height)
            // The resolved live window rectangle wins; title handles minimized
            // windows which are absent from the on-screen window list.
            let score = (distance < 8 ? 10_000.0 : 0) + (title != nil && title == entry.value.windowTitle ? 1_000.0 : 0) - Double(distance)
            if score > bestScore { bestScore = score; best = window }
        }
        return best
    }
}

@MainActor
private final class ForegroundWindowHandles {
    let application: AXUIElement
    let target: AXUIElement
    init(application: AXUIElement, target: AXUIElement) {
        self.application = application; self.target = target
    }
}

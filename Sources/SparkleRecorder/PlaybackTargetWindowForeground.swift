import AppKit
import ApplicationServices
import OSLog
import SparkleRecorderCore

@MainActor
enum PlaybackTargetWindowForeground {
    private static let logger = Logger(subsystem: "com.sparklerecorder.app", category: "PlaybackForeground")
    static func selectApplication(candidates: [NSRunningApplication], surfaces: [String: PlaybackSurface]) -> NSRunningApplication? {
        guard candidates.count > 1 else { return candidates.first }
        guard let surface = surfaces.sorted(by: { $0.key < $1.key }).first?.value else { return nil }
        let processes = Set(candidates.map(\.processIdentifier))
        let windows = visibleWindows(onScreenOnly: false).filter { processes.contains($0.processID) }
        guard let pid = PlaybackForegroundWindowVerification.targetProcessID(
            recordedFrame: surface.recordedFrame, recordedWindowID: surface.recordedWindowId, windows: windows) else { return nil }
        return candidates.first { $0.processIdentifier == pid }
    }

    static func prepare(app: NSRunningApplication, surfaces: [String: PlaybackSurface]) async -> Bool {
        guard let surface = surfaces.sorted(by: { $0.key < $1.key }).first?.value else { return false }
        let expectedFrame: RectValue
        if let windowID = surface.recordedWindowId {
            guard let bound = visibleWindows(onScreenOnly: false).first(where: { $0.id == windowID && $0.processID == app.processIdentifier }) else { return false }
            expectedFrame = bound.frame
        } else {
            expectedFrame = surface.recordedFrame
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        // Wake and activate before querying AX: hidden Chromium windows may
        // otherwise time out before an activation request is even issued.
        let handles = ForegroundWindowHandles(application: application)
        let handoff = PlaybackForegroundPreparation(request: {
            await MainActor.run {
                NSApp.yieldActivation(to: app)
                app.unhide()
                _ = app.activate(from: .current, options: [])
                if handles.target == nil {
                    handles.target = matchingWindow(application: handles.application, surface: surface, frame: expectedFrame)
                }
                guard let target = handles.target else { return }
                AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, target)
            }
        }, isReady: {
            await MainActor.run {
                guard app.isActive, let target = handles.target else {
                    guard let entry = surfaces.sorted(by: { $0.key < $1.key }).first else { return false }
                    let ready = PlaybackForegroundWindowVerification.isReady(active: app.isActive,
                        targetProcessID: app.processIdentifier, recordedFrame: entry.value.recordedFrame, recordedWindowID: entry.value.recordedWindowId, windows: visibleWindows())
                    if ready { logger.notice("Foreground verified by window-server ordering") }
                    return ready
                }
                var focused: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(handles.application, kAXFocusedWindowAttribute as CFString, &focused)
                let matches = focused.map { CFEqual($0, target) } ?? false
                guard status == .success, matches else {
                    logger.notice("Foreground readiness: focusedStatus=\(status.rawValue, privacy: .public), matches=\(matches, privacy: .public)")
                    return false
                }
                if surface.recordedWindowId != nil {
                    return PlaybackForegroundWindowVerification.isReady(active: app.isActive,
                        targetProcessID: app.processIdentifier, recordedFrame: surface.recordedFrame,
                        recordedWindowID: surface.recordedWindowId, windows: visibleWindows())
                }
                return true
            }
        }, sleep: { try await Task.sleep(for: .milliseconds(100)) })
        return await handoff.prepare()
    }

    private static func visibleWindows(onScreenOnly: Bool = true) -> [PlaybackForegroundWindowObservation] {
        guard let info = CGWindowListCopyWindowInfo(onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? UInt32,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width > 0, height > 0 else { return nil }
            return .init(id: id, processID: pid, frame: .init(x: x, y: y, width: width, height: height))
        }
    }

    private static func matchingWindow(application: AXUIElement, surface: PlaybackSurface, frame: RectValue) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let windows = value as? [AXUIElement] else {
            logger.notice("Window enumeration status=\(status.rawValue, privacy: .public)")
            return nil
        }
        var best: AXUIElement?
        var bestScore = -Double.infinity
        var ambiguous = false
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.3)
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
            let titleMatches = title?.isEmpty == false && title == surface.windowTitle
            guard distance < 8 || (surface.recordedWindowId == nil && titleMatches) else { continue }
            let score = (distance < 8 ? 10_000.0 : 0) + (titleMatches ? 1_000.0 : 0) - Double(distance)
            if score > bestScore { bestScore = score; best = window; ambiguous = false }
            else if abs(score - bestScore) < 0.001 { ambiguous = true }
        }
        return ambiguous ? nil : best
    }
}

@MainActor
private final class ForegroundWindowHandles {
    let application: AXUIElement
    var target: AXUIElement?
    init(application: AXUIElement) { self.application = application }
}

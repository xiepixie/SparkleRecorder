import Cocoa
import ApplicationServices
import SparkleRecorderCore

public enum WindowCaptureError: LocalizedError {
    case noFrontmostApplication
    case noWindowAtPoint
    case noAccessibilityPermission
    case noFocusedWindow
    case apiFailure(String)
    
    public var errorDescription: String? {
        switch self {
        case .noFrontmostApplication:
            return "No active application window found."
        case .noWindowAtPoint:
            return "No app window was found at that point."
        case .noAccessibilityPermission:
            return "Accessibility permission is required to capture window details."
        case .noFocusedWindow:
            return "Could not find a focused window in the active application."
        case .apiFailure(let detail):
            return "Accessibility API failed: \(detail)"
        }
    }
}

public final class WindowSurfaceCapture {
    public init() {}

    /// Captures the visible app window beneath a global top-left screen point.
    /// This is used by the explicit window picker so SparkleRecorder does not
    /// accidentally bind its own foreground window.
    public func captureWindow(at point: CGPoint) throws -> PlaybackSurface {
        guard AXIsProcessTrusted() else {
            throw WindowCaptureError.noAccessibilityPermission
        }
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        guard let observation = WindowTargetSelection.window(
            at: point,
            windows: WindowServerObservationAdapter.visibleWindows(),
            excludingProcessID: ownPID
        ) else {
            throw WindowCaptureError.noWindowAtPoint
        }
        guard let app = NSRunningApplication(processIdentifier: observation.processID) else {
            throw WindowCaptureError.noFrontmostApplication
        }

        let frame = observation.frame
        let resolvedContent = WindowContentFrameResolver.resolveContentFrame(for: observation.processID, outerFrame: frame)
        let rectContentFrame = RectValue(resolvedContent.frame)

        return PlaybackSurface(
            appName: app.localizedName ?? "Unknown App",
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: Self.windowTitle(windowID: observation.id),
            recordedWindowId: observation.id,
            recordedFrame: frame,
            recordedContentFrame: rectContentFrame,
            contentElementRole: resolvedContent.role,
            contentElementSubrole: resolvedContent.subrole,
            contentFrameSource: resolvedContent.source.rawValue,
            capturedAt: Date()
        )
    }
    
    public func captureFrontmostWindow() throws -> PlaybackSurface {
        let frontmostApp: NSRunningApplication
        if let app = NSWorkspace.shared.runningApplications.first(where: { app in
            app.isActive && app.bundleIdentifier != "com.sparklerecorder.app"
        }) {
            frontmostApp = app
        } else if let app = NSWorkspace.shared.frontmostApplication {
            frontmostApp = app
        } else {
            throw WindowCaptureError.noFrontmostApplication
        }
        
        let pid = frontmostApp.processIdentifier
        let appName = frontmostApp.localizedName ?? "Unknown App"
        let bundleID = frontmostApp.bundleIdentifier
        
        // 2. Check accessibility permission
        guard AXIsProcessTrusted() else {
            throw WindowCaptureError.noAccessibilityPermission
        }
        
        // 3. Create AXUIElement for the application
        let axApp = AXUIElementCreateApplication(pid)
        
        // 4. Get focused window
        var focusedWindowRef: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        guard focusedWindowResult == .success, let focusedWindow = focusedWindowRef else {
            throw WindowCaptureError.noFocusedWindow
        }
        
        let axWindow = focusedWindow as! AXUIElement
        
        // 5. Get position (origin)
        var posRef: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
        guard posResult == .success, let posVal = posRef else {
            throw WindowCaptureError.apiFailure("Failed to get window position attribute.")
        }
        
        var pos = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        
        // 6. Get size
        var sizeRef: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        guard sizeResult == .success, let sizeVal = sizeRef else {
            throw WindowCaptureError.apiFailure("Failed to get window size attribute.")
        }
        
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        
        // 7. Optional title
        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleResult == .success && titleRef != nil) ? (titleRef as! String) : nil
        
        let frame = RectValue(x: pos.x, y: pos.y, width: size.width, height: size.height)
        let recordedWindowID = PlaybackForegroundWindowVerification.frontmostMatchingWindowID(
            targetProcessID: pid,
            recordedFrame: frame,
            windows: WindowServerObservationAdapter.visibleWindows()
        )
        let resolvedContent = WindowContentFrameResolver.resolveContentFrame(for: pid, outerFrame: frame)
        let rectContentFrame = RectValue(resolvedContent.frame)
        
        return PlaybackSurface(
            appName: appName,
            bundleIdentifier: bundleID,
            windowTitle: title,
            recordedWindowId: recordedWindowID,
            recordedFrame: frame,
            recordedContentFrame: rectContentFrame,
            contentElementRole: resolvedContent.role,
            contentElementSubrole: resolvedContent.subrole,
            contentFrameSource: resolvedContent.source.rawValue,
            capturedAt: Date()
        )
    }

    private static func windowTitle(windowID: CGWindowID) -> String? {
        guard let descriptions = CGWindowListCreateDescriptionFromArray(
            [NSNumber(value: windowID)] as CFArray
        ) as? [[String: Any]],
        let description = descriptions.first else {
            return nil
        }
        let title = description[kCGWindowName as String] as? String
        return title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

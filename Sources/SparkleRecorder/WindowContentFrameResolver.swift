import Cocoa
import SparkleRecorderCore

/// App-edge adapter that resolves the live content area of a macOS window.
/// Platform accessibility and screen queries stay here; Core consumes only the
/// resulting frames and metadata through PlaybackContext/PlaybackSurface.
enum WindowContentFrameResolver {
    static func resolveContentFrame(
        for pid: pid_t?,
        outerFrame: RectValue
    ) -> CoordinateMapper.ResolvedContentFrame {
        let fallback = fallbackGeometry(for: outerFrame)
        let fallbackResult = CoordinateMapper.ResolvedContentFrame(
            frame: fallback.contentFrame,
            source: fallback.isFullscreen ? .fallbackOuterFrame : .fallbackTitleBar,
            role: nil,
            subrole: nil,
            confidence: 50
        )
        guard let targetPid = pid else { return fallbackResult }

        let appAX = AXUIElementCreateApplication(targetPid)
        AXUIElementSetMessagingTimeout(appAX, 0.5)
        var windowsValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsValue)
        guard error == .success, let windows = windowsValue as? [AXUIElement] else {
            return fallbackResult
        }

        for window in windows {
            guard let windowFrame = frameOfAXElement(window),
                  approximatelySameSize(windowFrame, outerFrame.cgRect) else { continue }
            return extractContentElement(from: window) ?? fallbackResult
        }
        return fallbackResult
    }

    private struct FallbackGeometry {
        var isFullscreen: Bool
        var titleBarHeight: CGFloat
        var contentFrame: CGRect
    }

    private static func fallbackGeometry(for frame: RectValue) -> FallbackGeometry {
        let center = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        guard let mainScreen = NSScreen.screens.first else {
            return FallbackGeometry(
                isFullscreen: false,
                titleBarHeight: 28,
                contentFrame: CGRect(x: frame.x, y: frame.y + 28, width: frame.width, height: max(1, frame.height - 28))
            )
        }
        let cocoaCenter = CGPoint(x: center.x, y: mainScreen.frame.height - center.y)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) })
        let isFullscreen = screen.map { abs(frame.height - $0.frame.height) < 5 } ?? false
        let titleBarHeight: CGFloat = isFullscreen ? 0 : 28
        return FallbackGeometry(
            isFullscreen: isFullscreen,
            titleBarHeight: titleBarHeight,
            contentFrame: CGRect(
                x: frame.x,
                y: frame.y + titleBarHeight,
                width: frame.width,
                height: max(1, frame.height - titleBarHeight)
            )
        )
    }

    private static func approximatelySameSize(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.width - rhs.width) < 10 && abs(lhs.height - rhs.height) < 10
    }

    private static func extractContentElement(
        from window: AXUIElement
    ) -> CoordinateMapper.ResolvedContentFrame? {
        var childrenValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue)
        guard error == .success, let children = childrenValue as? [AXUIElement] else { return nil }

        struct Candidate {
            let element: AXUIElement
            let role: String?
            let subrole: String?
            let score: Int
            let source: CoordinateMapper.ResolvedContentFrame.Source
        }

        var candidates: [Candidate] = []
        for child in children {
            var roleValue: AnyObject?
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleValue)

            let role = roleValue as? String
            let subrole = subroleValue as? String
            let scoreAndSource: (Int, CoordinateMapper.ResolvedContentFrame.Source)?
            if role == kAXGroupRole as String, subrole == "iOSContentGroup" {
                scoreAndSource = (100, .axIOSContentGroup)
            } else if role == "AXWebArea" {
                scoreAndSource = (80, .axWebArea)
            } else if role == "AXScrollArea" {
                scoreAndSource = (60, .axScrollArea)
            } else if role == kAXGroupRole as String {
                scoreAndSource = (40, .axGroup)
            } else if role == "AXGenericElement" {
                scoreAndSource = (20, .axGenericElement)
            } else {
                scoreAndSource = nil
            }

            if let scoreAndSource {
                candidates.append(Candidate(
                    element: child,
                    role: role,
                    subrole: subrole,
                    score: scoreAndSource.0,
                    source: scoreAndSource.1
                ))
            }
        }

        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let frame = frameOfAXElement(candidate.element) else { continue }
            return CoordinateMapper.ResolvedContentFrame(
                frame: frame,
                source: candidate.source,
                role: candidate.role,
                subrole: candidate.subrole,
                confidence: Double(candidate.score)
            )
        }
        return nil
    }

    private static func frameOfAXElement(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        let positionError = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeError = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard positionError == .success,
              sizeError == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }

        let positionAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionAX, .cgPoint, &point)
        AXValueGetValue(sizeAX, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

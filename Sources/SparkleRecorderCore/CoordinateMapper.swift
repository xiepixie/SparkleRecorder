import Cocoa

public struct CoordinateMapper {
    public init() {}
    
    public func resolveWindowLocalPoint(_ localPoint: CGPoint, in frame: RectValue) -> CGPoint {
        return CGPoint(x: frame.x + localPoint.x, y: frame.y + localPoint.y)
    }
    
    public func resolveNormalizedPoint(_ normalizedPoint: CGPoint, in frame: RectValue) -> CGPoint {
        return CGPoint(
            x: frame.x + (normalizedPoint.x * frame.width),
            y: frame.y + (normalizedPoint.y * frame.height)
        )
    }
    
    public func assertPointIsInsideWindow(_ point: CGPoint, in frame: RectValue, tolerance: CGFloat = 0) -> Bool {
        let cgFrame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        let expandedFrame = cgFrame.insetBy(dx: -tolerance, dy: -tolerance)
        return expandedFrame.contains(point)
    }
    
    public static func windowTitleBarHeight(for pid: pid_t?, frame: RectValue) -> CGFloat {
        let center = CGPoint(x: frame.x + frame.width/2, y: frame.y + frame.height/2)
        guard let mainScreen = NSScreen.screens.first else { return 28.0 }
        let cocoaCenter = CGPoint(x: center.x, y: mainScreen.frame.height - center.y)
        
        let isFullscreen: Bool
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) {
            isFullscreen = abs(frame.height - screen.frame.height) < 5.0
        } else {
            isFullscreen = false
        }
        
        guard let targetPid = pid else {
            return isFullscreen ? 0.0 : 28.0
        }
        
        let appAX = AXUIElementCreateApplication(targetPid)
        AXUIElementSetMessagingTimeout(appAX, 0.5)
        var windowsValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard err == .success, let windows = windowsValue as? [AXUIElement] else {
            return isFullscreen ? 0.0 : 28.0
        }
        
        for window in windows {
            if let winFrame = frameOfAXElement(window) {
                let dw = abs(winFrame.width - frame.width)
                let dh = abs(winFrame.height - frame.height)
                if dw < 10.0 && dh < 10.0 { // Allow minor fuzziness
                    if let content = extractContentElement(from: window) {
                        let diff = content.frame.minY - winFrame.minY
                        if diff >= 0 && diff < 100 {
                            return diff
                        }
                    }
                    break // Stop if we found the window but no iOSContentGroup
                }
            }
        }
        return isFullscreen ? 0.0 : 28.0
    }
        
    public struct ResolvedContentFrame {
        public let frame: CGRect
        public let source: Source
        public let role: String?
        public let subrole: String?
        public let confidence: Double
        
        public enum Source: String {
            case axIOSContentGroup, axWebArea, axScrollArea, axGroup, axGenericElement, fallbackTitleBar, fallbackOuterFrame
        }
    }
    
    public static func resolveContentFrame(for pid: pid_t?, outerFrame: RectValue) -> ResolvedContentFrame {
        let center = CGPoint(x: outerFrame.x + outerFrame.width/2, y: outerFrame.y + outerFrame.height/2)
        guard let mainScreen = NSScreen.screens.first else { 
            return ResolvedContentFrame(frame: CGRect(x: outerFrame.x, y: outerFrame.y + 28, width: outerFrame.width, height: max(1, outerFrame.height - 28)), source: .fallbackOuterFrame, role: nil, subrole: nil, confidence: 0.0)
        }
        let cocoaCenter = CGPoint(x: center.x, y: mainScreen.frame.height - center.y)
        
        let isFullscreen: Bool
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) {
            isFullscreen = abs(outerFrame.height - screen.frame.height) < 5.0
        } else {
            isFullscreen = false
        }
        
        let fallbackTb: CGFloat = isFullscreen ? 0.0 : 28.0
        let fallbackFrame = CGRect(x: outerFrame.x, y: outerFrame.y + fallbackTb, width: outerFrame.width, height: max(1, outerFrame.height - fallbackTb))
        
        let fallbackResult = ResolvedContentFrame(frame: fallbackFrame, source: isFullscreen ? .fallbackOuterFrame : .fallbackTitleBar, role: nil, subrole: nil, confidence: 50.0)
        
        guard let targetPid = pid else {
            return fallbackResult
        }
        
        let appAX = AXUIElementCreateApplication(targetPid)
        AXUIElementSetMessagingTimeout(appAX, 0.5)
        var windowsValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard err == .success, let windows = windowsValue as? [AXUIElement] else {
            return fallbackResult
        }
        
        for window in windows {
            if let winFrame = frameOfAXElement(window) {
                let dw = abs(winFrame.width - outerFrame.width)
                let dh = abs(winFrame.height - outerFrame.height)
                if dw < 10.0 && dh < 10.0 { // Allow minor fuzziness
                    if let content = extractContentElement(from: window) {
                        return content
                    }
                    // We found the window, but no valid content element. Use standard tb estimation.
                    break
                }
            }
        }
        
        return fallbackResult
    }
    
    private static func extractContentElement(from window: AXUIElement) -> ResolvedContentFrame? {
        var childrenValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue)
        guard err == .success, let children = childrenValue as? [AXUIElement] else { return nil }
        
        struct Candidate {
            let element: AXUIElement
            let role: String?
            let subrole: String?
            let score: Int
            let source: ResolvedContentFrame.Source
        }
        
        var candidates: [Candidate] = []
        
        for child in children {
            var roleValue: AnyObject?
            var subroleValue: AnyObject?
            
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleValue)
            
            let role = roleValue as? String
            let subrole = subroleValue as? String
            
            var score = 0
            var source: ResolvedContentFrame.Source = .axGenericElement
            if role == kAXGroupRole as String && subrole == "iOSContentGroup" {
                score = 100
                source = .axIOSContentGroup
            } else if role == "AXWebArea" {
                score = 80
                source = .axWebArea
            } else if role == "AXScrollArea" {
                score = 60
                source = .axScrollArea
            } else if role == kAXGroupRole as String {
                score = 40
                source = .axGroup
            } else if role == "AXGenericElement" {
                score = 20
                source = .axGenericElement
            }
            
            if score > 0 {
                candidates.append(Candidate(element: child, role: role, subrole: subrole, score: score, source: source))
            }
        }
        
        candidates.sort { $0.score > $1.score }
        
        for candidate in candidates {
            if let frame = frameOfAXElement(candidate.element) {
                return ResolvedContentFrame(frame: frame, source: candidate.source, role: candidate.role, subrole: candidate.subrole, confidence: Double(candidate.score))
            }
        }
        
        return nil
    }
    
    private static func frameOfAXElement(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        
        guard posErr == .success, sizeErr == .success,
              CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }
        let posAX = positionValue as! AXValue
        let sizeAX = sizeValue as! AXValue
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(posAX, .cgPoint, &point)
        AXValueGetValue(sizeAX, .cgSize, &size)
        
        return CGRect(origin: point, size: size)
    }
}

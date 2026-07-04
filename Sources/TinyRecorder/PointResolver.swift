import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

public enum CoordinateMode: String, Codable {
    /// Plays macro strictly with absolute screen coordinates.
    case screenAbsolute
    
    /// RecordedEvent.x/y remain screen-absolute coordinates captured at record time.
    /// boundWindowOffset applies delta(currentWindow.origin - recordedWindow.origin)
    /// at playback time. It does not convert events into window-relative coordinates.
    case boundWindowOffset
}

public struct RectValue: Codable, Equatable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PlaybackSurface: Codable, Equatable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var recordedFrame: RectValue
    public var capturedAt: Date
    
    public init(appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil, recordedFrame: RectValue, capturedAt: Date = Date()) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.recordedFrame = recordedFrame
        self.capturedAt = capturedAt
    }
}

public struct PlaybackContext {
    public var surface: PlaybackSurface?
    public var currentSurfaceFrame: RectValue?
    public var coordinateMode: CoordinateMode
    public var sizeTolerance: CGFloat
    
    public init(
        surface: PlaybackSurface? = nil,
        currentSurfaceFrame: RectValue? = nil,
        coordinateMode: CoordinateMode = .screenAbsolute,
        sizeTolerance: CGFloat = 50 // Matches MenuBarController's mismatch threshold
    ) {
        self.surface = surface
        self.currentSurfaceFrame = currentSurfaceFrame
        self.coordinateMode = coordinateMode
        self.sizeTolerance = sizeTolerance
    }
}

public struct PointResolver {
    public init() {}
    
    public func resolve(_ event: RecordedEvent, context: PlaybackContext) -> CGPoint {
        let original = CGPoint(x: event.x, y: event.y)
        
        var resolvedPoint = original
        if context.coordinateMode == .boundWindowOffset,
           let recordedFrame = context.surface?.recordedFrame,
           let currentFrame = context.currentSurfaceFrame {
            let dx = currentFrame.x - recordedFrame.x
            let dy = currentFrame.y - recordedFrame.y
            resolvedPoint = CGPoint(x: event.x + dx, y: event.y + dy)
        }
        
        // Clamp to current screen bounds to handle multi-monitor changes gracefully
        #if canImport(AppKit)
        if let screens = NSScreen.screens.first {
            let unionFrame = NSScreen.screens.dropFirst().reduce(screens.frame) { $0.union($1.frame) }
            let primaryHeight = screens.frame.height
            
            let minX = unionFrame.minX
            let maxX = unionFrame.maxX
            // Under Y-flip (cgY = primaryHeight - AppKitY):
            // Top of unionFrame (maxY) maps to min CG Y
            // Bottom of unionFrame (minY) maps to max CG Y
            let minY_CG = primaryHeight - unionFrame.maxY
            let maxY_CG = primaryHeight - unionFrame.minY
            
            resolvedPoint.x = max(minX, min(resolvedPoint.x, maxX))
            resolvedPoint.y = max(minY_CG, min(resolvedPoint.y, maxY_CG))
        }
        #endif
        
        return resolvedPoint
    }
}

import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

public enum CoordinateMode: String, Codable, Sendable {
    /// Plays macro strictly with absolute screen coordinates.
    case screenAbsolute
    
    /// RecordedEvent.x/y remain screen-absolute coordinates captured at record time.
    /// boundWindowOffset applies delta(currentWindow.origin - recordedWindow.origin)
    /// at playback time. It does not convert events into window-relative coordinates.
    case boundWindowOffset
}

public struct RectValue: Codable, Equatable, Sendable {
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

public struct PlaybackSurface: Codable, Equatable, Sendable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var recordedFrame: RectValue
    public var recordedContentFrame: RectValue?
    public var contentElementRole: String?
    public var contentElementSubrole: String?
    public var capturedAt: Date
    
    public var windowTitlePattern: String?
    public var recordedDisplayId: CGDirectDisplayID?
    public var recordedWindowId: CGWindowID?
    public var contentFrameSource: String?
    
    public init(appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil, windowTitlePattern: String? = nil, recordedDisplayId: CGDirectDisplayID? = nil, recordedWindowId: CGWindowID? = nil, recordedFrame: RectValue, recordedContentFrame: RectValue? = nil, contentElementRole: String? = nil, contentElementSubrole: String? = nil, contentFrameSource: String? = nil, capturedAt: Date = Date()) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.windowTitlePattern = windowTitlePattern
        self.recordedDisplayId = recordedDisplayId
        self.recordedWindowId = recordedWindowId
        self.recordedFrame = recordedFrame
        self.recordedContentFrame = recordedContentFrame
        self.contentElementRole = contentElementRole
        self.contentElementSubrole = contentElementSubrole
        self.contentFrameSource = contentFrameSource
        self.capturedAt = capturedAt
    }
}

public struct PlaybackContext: Sendable {
    public var surfaces: [String: PlaybackSurface]
    public var currentSurfaceFrames: [String: RectValue]
    public var currentContentFrames: [String: RectValue]
    public var currentTitleBarHeights: [String: CGFloat]
    public var coordinateMode: CoordinateMode
    public var sizeTolerance: CGFloat
    
    public init(
        surfaces: [String: PlaybackSurface] = [:],
        currentSurfaceFrames: [String: RectValue] = [:],
        currentContentFrames: [String: RectValue] = [:],
        currentTitleBarHeights: [String: CGFloat] = [:],
        coordinateMode: CoordinateMode = .boundWindowOffset,
        sizeTolerance: CGFloat = 50 // Matches MenuBarController's mismatch threshold
    ) {
        self.surfaces = surfaces
        self.currentSurfaceFrames = currentSurfaceFrames
        self.currentContentFrames = currentContentFrames
        self.currentTitleBarHeights = currentTitleBarHeights
        self.coordinateMode = coordinateMode
        self.sizeTolerance = sizeTolerance
    }
}

public enum PointResolveError: Error, Sendable {
    case missingSurface(String)
    case missingWindowFrame(String)
    case missingWindowLocalPoint
    case missingNormalizedPoint
    case resolvedPointOutOfBounds(CGPoint, RectValue)
    case locatorOnlyRequiresLocatorEngine
}

public struct PointResolver: Sendable {
    public init() {}
    
    public func resolve(_ event: RecordedEvent, context: PlaybackContext) -> Result<CGPoint, PointResolveError> {
        let original = CGPoint(x: event.x, y: event.y)
        let mapper = CoordinateMapper()
        
        let binding = event.coordinateBinding ?? .unbound
        var resolvedPoint = original
        
        switch binding {
        case .globalScreen:
            resolvedPoint = original
            
        case .targetWindow:
            guard context.coordinateMode == .boundWindowOffset else {
                resolvedPoint = original
                break
            }
            
            let targetSurfaceId: String
            if let sId = event.surfaceId, context.surfaces[sId] != nil {
                targetSurfaceId = sId
            } else if let firstKey = context.surfaces.keys.first {
                targetSurfaceId = firstKey
            } else {
                targetSurfaceId = event.surfaceId ?? "surface-1"
            }
            
            guard let currentFrame = context.currentSurfaceFrames[targetSurfaceId] else {
                return .failure(.missingWindowFrame(targetSurfaceId))
            }
            
            let strategy = event.coordinateStrategy ?? (event.kind.isMouse ? .normalizedPreferred : .windowLocalPreferred)
            
            let tryContentNormalized: () -> (CGPoint, RectValue)? = {
                guard let contentFrame = context.currentContentFrames[targetSurfaceId],
                      let cnx = event.contentNormalizedX, let cny = event.contentNormalizedY else { return nil }
                return (
                    CGPoint(x: contentFrame.x + cnx * contentFrame.width, y: contentFrame.y + cny * contentFrame.height),
                    contentFrame
                )
            }
            
            let tryContentLocal: () -> (CGPoint, RectValue)? = {
                guard let contentFrame = context.currentContentFrames[targetSurfaceId],
                      let cx = event.contentLocalX, let cy = event.contentLocalY else { return nil }
                return (
                    CGPoint(x: contentFrame.x + cx, y: contentFrame.y + cy),
                    contentFrame
                )
            }
            
            let tryWindowNormalized: () -> (CGPoint, RectValue)? = {
                guard let nx = event.windowNormalizedX, let ny = event.windowNormalizedY else { return nil }
                let tbHeight: CGFloat
                if let cached = context.currentTitleBarHeights[targetSurfaceId] {
                    tbHeight = cached
                } else {
                    let bid = context.surfaces[targetSurfaceId]?.bundleIdentifier
                    let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                    tbHeight = CoordinateMapper.windowTitleBarHeight(for: pid, frame: currentFrame)
                }
                let clientHeight = max(1.0, currentFrame.height - tbHeight)
                return (
                    CGPoint(x: currentFrame.x + nx * currentFrame.width, y: currentFrame.y + tbHeight + ny * clientHeight),
                    currentFrame
                )
            }
            
            let tryWindowLocal: () -> (CGPoint, RectValue)? = {
                guard let lx = event.windowLocalX, let ly = event.windowLocalY else { return nil }
                let tbHeight: CGFloat
                if let cached = context.currentTitleBarHeights[targetSurfaceId] {
                    tbHeight = cached
                } else {
                    let bid = context.surfaces[targetSurfaceId]?.bundleIdentifier
                    let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                    tbHeight = CoordinateMapper.windowTitleBarHeight(for: pid, frame: currentFrame)
                }
                return (
                    CGPoint(x: currentFrame.x + lx, y: currentFrame.y + tbHeight + ly),
                    currentFrame
                )
            }
            
            var boundsFrame = currentFrame
            
            switch strategy {
            case .windowLocalPreferred:
                if let result = tryContentLocal() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryContentNormalized() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryWindowLocal() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryWindowNormalized() { resolvedPoint = result.0; boundsFrame = result.1 }
                else { return .failure(.missingWindowLocalPoint) }
                
            case .normalizedPreferred:
                if let result = tryContentNormalized() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryContentLocal() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryWindowNormalized() { resolvedPoint = result.0; boundsFrame = result.1 }
                else if let result = tryWindowLocal() { resolvedPoint = result.0; boundsFrame = result.1 }
                else { return .failure(.missingNormalizedPoint) }
                
            case .absoluteOnly:
                resolvedPoint = original
                
            case .locatorOnly:
                return .failure(.locatorOnlyRequiresLocatorEngine)
            }
            
            guard mapper.assertPointIsInsideWindow(resolvedPoint, in: boundsFrame) else {
                return .failure(.resolvedPointOutOfBounds(resolvedPoint, boundsFrame))
            }
            
        case .unbound:
            // Fallback legacy behavior
            let targetSurfaceId: String
            if let sId = event.surfaceId, context.surfaces[sId] != nil {
                targetSurfaceId = sId
            } else if let firstKey = context.surfaces.keys.first {
                targetSurfaceId = firstKey
            } else {
                targetSurfaceId = event.surfaceId ?? "surface-1"
            }
            
            if let surface = context.surfaces[targetSurfaceId],
               let currentFrame = context.currentSurfaceFrames[targetSurfaceId] {
                
                // Prioritize content frame offsets if both recorded and current content frames exist
                if let recordedContent = surface.recordedContentFrame,
                   let currentContent = context.currentContentFrames[targetSurfaceId] {
                    let dx = currentContent.x - recordedContent.x
                    let dy = currentContent.y - recordedContent.y
                    resolvedPoint = CGPoint(x: event.x + dx, y: event.y + dy)
                } else {
                    let recordedFrame = surface.recordedFrame
                    let recTb: CGFloat
                    if let content = surface.recordedContentFrame {
                        recTb = content.y - recordedFrame.y
                    } else {
                        let bid = surface.bundleIdentifier
                        let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                        recTb = CoordinateMapper.windowTitleBarHeight(for: pid, frame: recordedFrame)
                    }
                    
                    let curTb: CGFloat
                    if let cached = context.currentTitleBarHeights[targetSurfaceId] {
                        curTb = cached
                    } else {
                        let bid = surface.bundleIdentifier
                        let pid = bid.flatMap { b in NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b })?.processIdentifier }
                        curTb = CoordinateMapper.windowTitleBarHeight(for: pid, frame: currentFrame)
                    }
                    
                    let dx = currentFrame.x - recordedFrame.x
                    let dy = (currentFrame.y + curTb) - (recordedFrame.y + recTb)
                    resolvedPoint = CGPoint(x: event.x + dx, y: event.y + dy)
                }
            }
        }
        
        // Fail safe: If point is completely outside any screen bounds, return failure instead of clamping
        var maxDisplayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &maxDisplayCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplayCount))
        var actualDisplayCount: UInt32 = 0
        let err = CGGetActiveDisplayList(maxDisplayCount, &activeDisplays, &actualDisplayCount)
        
        if err == .success && actualDisplayCount > 0 {
            var unionFrame = CGDisplayBounds(activeDisplays[0])
            for i in 1..<Int(actualDisplayCount) {
                unionFrame = unionFrame.union(CGDisplayBounds(activeDisplays[i]))
            }
            if resolvedPoint.x < unionFrame.minX || resolvedPoint.x > unionFrame.maxX || resolvedPoint.y < unionFrame.minY || resolvedPoint.y > unionFrame.maxY {
                return .failure(.resolvedPointOutOfBounds(resolvedPoint, RectValue(x: unionFrame.minX, y: unionFrame.minY, width: unionFrame.width, height: unionFrame.height)))
            }
        }
        
        return .success(resolvedPoint)
    }
}

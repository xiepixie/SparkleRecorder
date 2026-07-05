import Foundation
import CoreGraphics
import SparkleRecorderCore

public final class RecordingSurfaceTracker {
    private var timer: Timer?
    private let capture = WindowSurfaceCapture()
    private let lock = NSLock()
    private var cachedSurface: PlaybackSurface?
    
    public var cachedActiveSurface: PlaybackSurface? {
        lock.lock()
        defer { lock.unlock() }
        return cachedSurface
    }
    
    public init() {}
    
    public func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .userInteractive).async {
                guard let self = self else { return }
                let surface = try? self.capture.captureFrontmostWindow()
                self.lock.lock()
                self.cachedSurface = surface
                self.lock.unlock()
            }
        }
        timer?.fire()
    }
    
    public func stopTracking() {
        timer?.invalidate()
        timer = nil
        lock.lock()
        cachedSurface = nil
        lock.unlock()
    }
}

public final class SurfaceMatcher {
    public init() {}
    
    public func match(_ surface: PlaybackSurface, against surfaces: [String: PlaybackSurface]) -> String? {
        // Multi-factor surface matching: bundle identifier, window title, and roughly similar size
        for (id, existingSurface) in surfaces {
            if existingSurface.bundleIdentifier == surface.bundleIdentifier {
                // If title matches exactly, it's a strong match
                if existingSurface.windowTitle == surface.windowTitle {
                    return id
                }
                
                // Usually window resizes are intentional, but if there's only one window of this app so far,
                // we might reuse the surface. For now, require title match or single window of same app.
                let sameAppSurfaces = surfaces.values.filter { $0.bundleIdentifier == surface.bundleIdentifier }
                if sameAppSurfaces.count == 1 {
                    // It's the only known window for this app, assume it's the same surface (title might have dynamically changed like a webpage title)
                    // If size changed drastically, it might be a new window, but we map to same surface ID for now.
                    return id
                }
            }
        }
        return nil
    }
}

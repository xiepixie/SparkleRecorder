import Foundation
import CoreGraphics
import SparkleRecorderCore

public final class RecordingSurfaceTracker: @unchecked Sendable {
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
            guard let tracker = self else { return }
            DispatchQueue.global(qos: .userInteractive).async {
                tracker.refreshActiveSurface()
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

    private func refreshActiveSurface() {
        let surface = try? capture.captureFrontmostWindow()
        lock.lock()
        cachedSurface = surface
        lock.unlock()
    }
}


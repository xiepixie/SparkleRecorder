import Testing
@testable import SparkleRecorderCore

@Suite("RecordingSurfaceRegistry Tests")
struct RecordingSurfaceRegistryTests {
    @Test("Allocates new surface when unmatched")
    func allocatesNewSurface() {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        
        let surface = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        
        let targetId = registry.update(eventKind: .mouseMoved, trackedActiveSurface: surface, surfaceMatcher: matcher)
        
        #expect(targetId == "surface-1")
        #expect(registry.activeSurfaceId == "surface-1")
        #expect(registry.activeSurfaces.count == 1)
        #expect(registry.activeSurfaces["surface-1"]?.bundleIdentifier == "com.apple.Safari")
        #expect(registry.activeGestureSurfaceId == nil)
    }
    
    @Test("Matches existing surface")
    func matchesExistingSurface() {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        
        let surface1 = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        _ = registry.update(eventKind: .mouseMoved, trackedActiveSurface: surface1, surfaceMatcher: matcher)
        
        let surface2 = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100)) // Identical title and bundle
        let targetId = registry.update(eventKind: .leftMouseDown, trackedActiveSurface: surface2, surfaceMatcher: matcher)
        
        #expect(targetId == "surface-1") // Should match existing
        #expect(registry.activeSurfaces.count == 1)
    }
    
    @Test("Locks gesture surface on mouse down")
    func locksGestureSurface() {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        
        let surface = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        let targetId = registry.update(eventKind: .leftMouseDown, trackedActiveSurface: surface, surfaceMatcher: matcher)
        
        #expect(targetId == "surface-1")
        #expect(registry.activeGestureSurfaceId == "surface-1")
    }
    
    @Test("Maintains gesture lock during drag despite new active surface")
    func maintainsLockDuringDrag() {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        
        let surface1 = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        _ = registry.update(eventKind: .leftMouseDown, trackedActiveSurface: surface1, surfaceMatcher: matcher)
        
        let surface2 = PlaybackSurface(bundleIdentifier: "com.apple.Finder", windowTitle: "Desktop", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        let targetId = registry.update(eventKind: .leftMouseDragged, trackedActiveSurface: surface2, surfaceMatcher: matcher)
        
        #expect(targetId == "surface-1", "Should still target the locked surface-1")
        #expect(registry.activeSurfaceId == "surface-2", "But the active window is now surface-2")
        #expect(registry.activeSurfaces.count == 2)
    }
    
    @Test("Releases gesture lock on mouse up")
    func releasesGestureLock() {
        var registry = RecordingSurfaceRegistry()
        let matcher = SurfaceMatcher()
        
        let surface = PlaybackSurface(bundleIdentifier: "com.apple.Safari", windowTitle: "Google", recordedFrame: RectValue(x: 0, y: 0, width: 100, height: 100))
        _ = registry.update(eventKind: .leftMouseDown, trackedActiveSurface: surface, surfaceMatcher: matcher)
        
        let targetId = registry.update(eventKind: .leftMouseUp, trackedActiveSurface: surface, surfaceMatcher: matcher)
        
        #expect(targetId == "surface-1")
        #expect(registry.activeGestureSurfaceId == nil)
    }
}

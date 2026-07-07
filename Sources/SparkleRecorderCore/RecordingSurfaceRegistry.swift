public struct RecordingSurfaceRegistry: Sendable {
    public var activeSurfaces: [String: PlaybackSurface] = [:]
    public var activeSurfaceId: String?
    public var activeGestureSurfaceId: String?
    
    public init() {}
    
    /// Updates the registry with the latest tracked surface and event type.
    /// Returns the resolved target surface ID for the current event.
    public mutating func update(
        eventKind: RecordedEvent.Kind,
        trackedActiveSurface: PlaybackSurface?,
        surfaceMatcher: SurfaceMatcher
    ) -> String? {
        var updatedSurfaceId = activeSurfaceId
        
        if let currentFocusedWindow = trackedActiveSurface {
            if let existingId = surfaceMatcher.match(currentFocusedWindow, against: activeSurfaces) {
                updatedSurfaceId = existingId
                activeSurfaces[existingId] = currentFocusedWindow
            } else {
                let nextId = "surface-\(activeSurfaces.count + 1)"
                activeSurfaces[nextId] = currentFocusedWindow
                updatedSurfaceId = nextId
            }
        }
        
        if Self.startsGesture(eventKind) {
            activeGestureSurfaceId = updatedSurfaceId
        }
        
        let targetId = activeGestureSurfaceId ?? updatedSurfaceId
        
        if Self.endsGesture(eventKind) {
            activeGestureSurfaceId = nil
        }
        
        activeSurfaceId = updatedSurfaceId
        return targetId
    }

    private static func startsGesture(_ kind: RecordedEvent.Kind) -> Bool {
        switch kind {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private static func endsGesture(_ kind: RecordedEvent.Kind) -> Bool {
        switch kind {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}

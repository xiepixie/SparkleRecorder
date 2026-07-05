# Codebase Target Modifications Plan

This document details the exact file changes, target functions, and implementation code snippets required to construct the upgraded coordinate and window tracker systems.

---

## 1. Data Model Upgrades

### [RecordedEvent.swift](../Sources/SparkleRecorder/RecordedEvent.swift)
- **Target Changes**: Add optional flat window-relative coordinate variables, coordinate strategy, and `surfaceId` mapping to support multi-app workflows.
- **Implementation Snippet**:
  ```swift
  public enum CoordinateBinding: String, Codable {
      case targetWindow
      case globalScreen
      case unbound
  }

  public enum CoordinateStrategy: String, Codable {
      case windowLocalPreferred
      case normalizedPreferred
      case absoluteOnly
      case locatorOnly
  }

  public struct RecordedEvent: Codable, Equatable {
      // ... existing properties ...
      
      // Phase 1: Flat fields implementation
      public var windowLocalX: CGFloat?
      public var windowLocalY: CGFloat?
      public var windowNormalizedX: CGFloat?
      public var windowNormalizedY: CGFloat?
      
      public var coordinateBinding: CoordinateBinding?
      public var coordinateStrategy: CoordinateStrategy?
      
      // Multi-App workflow window surface mapping
      public var surfaceId: String?
      
      // Swift will auto-derive if no custom CodingKeys are used. If custom CodingKeys are present,
      // add coding keys and use decodeIfPresent.
  }
  ```

---

## 2. Event Capture & Coordinate Updates (Recording Phase)

### [Recorder.swift](../Sources/SparkleRecorder/Recorder.swift)
- **Target Properties**: Manage multiple active surfaces and tracks focus switches during recording. Ensure thread safety by marking `Recorder` as `@MainActor`.
  ```swift
  @MainActor
  final class Recorder: ObservableObject {
      // ... existing properties ...
      
      // Maps surfaceId to captured window metadata
      @Published var activeSurfaces: [String: PlaybackSurface] = [:]
      
      // Tracks the currently focused surface ID during recording
      private var activeSurfaceId: String? = nil
      
      // Locks the surface ID during mouse drag gestures
      private var activeGestureSurfaceId: String? = nil
  ```
- **Throttled Surface Tracker**:
  To prevent heavy cross-process AX IPC calls from blocking the high-frequency `CGEventTap` callback thread, we introduce a `RecordingSurfaceTracker` that queries window details asynchronously on a background queue every `150ms` and caches the active window details.
  ```swift
  final class RecordingSurfaceTracker {
      private var timer: Timer?
      private let capture = WindowSurfaceCapture()
      
      // Thread-safe cached active surface
      private(set) var cachedActiveSurface: PlaybackSurface?
      
      func startTracking() {
          timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
              DispatchQueue.global(qos: .userInteractive).async {
                  let surface = try? self?.capture.captureFrontmostWindow()
                  DispatchQueue.main.async {
                      self?.cachedActiveSurface = surface
                  }
              }
          }
      }
      
      func stopTracking() {
          timer?.invalidate()
          timer = nil
      }
  }
  ```
- **Target Function**: `startRecording(surface:)` and `loadEvents(_:surfaces:)`.
  ```swift
  @discardableResult
  func startRecording(surface: PlaybackSurface? = nil) -> Bool {
      // ... existing initialization ...
      self.activeSurfaces.removeAll()
      if let initialSurface = surface {
          let sId = "surface-1"
          self.activeSurfaces[sId] = initialSurface
          self.activeSurfaceId = sId
      } else {
          self.activeSurfaceId = nil
      }
      self.activeGestureSurfaceId = nil
      // ...
  }
  ```
- **Target Function**: `handle(type:event:)`. Calculate relative coordinates and map `surfaceId` safely.
  ```swift
  private func handle(type: CGEventType, event: CGEvent) {
      // ...
      let loc = event.location
      
      // Lock surfaceId during gestures (mouseDown -> mouseUp)
      if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
          activeGestureSurfaceId = activeSurfaceId
      }
      
      // Match active window using the cached surface from RecordingSurfaceTracker
      if let currentFocusedWindow = surfaceTracker.cachedActiveSurface {
          // Use multi-factor surface matcher (Scoring-based matcher) instead of raw bundleIdentifier checks
          if let existingId = surfaceMatcher.match(currentFocusedWindow, against: activeSurfaces) {
              self.activeSurfaceId = existingId
          } else {
              let nextId = "surface-\(activeSurfaces.count + 1)"
              activeSurfaces[nextId] = currentFocusedWindow
              self.activeSurfaceId = nextId
          }
      }
      
      let targetId = activeGestureSurfaceId ?? activeSurfaceId
      
      // Release gesture lock at mouseUp
      if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
          activeGestureSurfaceId = nil
      }
      
      var localX: CGFloat? = nil
      var localY: CGFloat? = nil
      var normX: CGFloat? = nil
      var normY: CGFloat? = nil
      var binding: CoordinateBinding = .unbound
      
      if let sId = targetId, let surface = activeSurfaces[sId] {
          let frame = surface.recordedFrame
          let isInsideSurface = loc.x >= frame.x && 
                                loc.x <= (frame.x + frame.width) && 
                                loc.y >= frame.y && 
                                loc.y <= (frame.y + frame.height)
          
          if isInsideSurface {
              let lx = loc.x - frame.x
              let ly = loc.y - frame.y
              localX = lx
              localY = ly
              normX = frame.width > 0 ? lx / frame.width : 0
              normY = frame.height > 0 ? ly / frame.height : 0
              binding = .targetWindow
          } else {
              binding = .globalScreen
          }
      }
      
      let recorded = RecordedEvent(
          kind: kind,
          time: elapsed,
          // ...
          windowLocalX: localX,
          windowLocalY: localY,
          windowNormalizedX: normX,
          windowNormalizedY: normY,
          coordinateBinding: binding,
          coordinateStrategy: .windowLocalPreferred,
          surfaceId: targetId
      )
      
      // UI / State updates dispatched back safely to MainActor
      DispatchQueue.main.async {
          self.pending.append(recorded)
      }
  }
  ```

---

## 3. Playback Coordinate Resolution (Replay Phase)

### [PointResolver.swift](../Sources/SparkleRecorder/PointResolver.swift)
- **Target Function**: `resolve(_:context:)`. Support multi-surface matching based on contextual bounds and fail safely.
- **Code implementation**:
  ```swift
  public enum PointResolveError: Error {
      case missingSurface(String)
      case missingWindowFrame(String)
      case missingWindowLocalPoint
      case missingNormalizedPoint
      case resolvedPointOutOfBounds(CGPoint, RectValue)
      case locatorOnlyRequiresLocatorEngine
  }

  public func resolve(_ event: RecordedEvent, context: PlaybackContext) -> Result<CGPoint, PointResolveError> {
      let original = CGPoint(x: event.x, y: event.y)
      let mapper = CoordinateMapper()
      
      // Determine binding type
      let binding = event.coordinateBinding ?? .unbound
      
      switch binding {
      case .globalScreen:
          // Keep screen-absolute coordinates completely unaltered
          return .success(original)
          
      case .targetWindow:
          guard context.coordinateMode == .boundWindowOffset else {
              return .success(original)
          }
          
          let targetSurfaceId = event.surfaceId ?? "surface-1"
          guard let currentFrame = context.currentSurfaceFrames[targetSurfaceId] else {
              return .failure(.missingWindowFrame(targetSurfaceId))
          }
          
          var resolvedPoint = original
          let strategy = event.coordinateStrategy ?? .windowLocalPreferred
          
          switch strategy {
          case .windowLocalPreferred:
              guard let lx = event.windowLocalX, let ly = event.windowLocalY else {
                  return .failure(.missingWindowLocalPoint)
              }
              resolvedPoint = mapper.resolveWindowLocalPoint(CGPoint(x: lx, y: ly), in: currentFrame)
              
          case .normalizedPreferred:
              guard let nx = event.windowNormalizedX, let ny = event.windowNormalizedY else {
                  return .failure(.missingNormalizedPoint)
              }
              resolvedPoint = mapper.resolveNormalizedPoint(CGPoint(x: nx, y: ny), in: currentFrame)
              
          case .absoluteOnly:
              resolvedPoint = original
              
          case .locatorOnly:
              // locatorOnly strictly expects LocatorEngine processing, resolver fails
              return .failure(.locatorOnlyRequiresLocatorEngine)
          }
          
          // Fail-Safe Out-Of-Bounds Check
          guard mapper.assertPointIsInsideWindow(resolvedPoint, in: currentFrame) else {
              return .failure(.resolvedPointOutOfBounds(resolvedPoint, currentFrame))
          }
          
          return .success(resolvedPoint)
          
      case .unbound:
          // Fallback legacy offset behavior for v1 macros
          if let targetSurfaceId = event.surfaceId,
             let recordedFrame = context.surfaces[targetSurfaceId]?.recordedFrame,
             let currentFrame = context.currentSurfaceFrames[targetSurfaceId] {
              let dx = currentFrame.x - recordedFrame.x
              let dy = currentFrame.y - recordedFrame.y
              return .success(CGPoint(x: event.x + dx, y: event.y + dy))
          }
          return .success(original)
      }
  }
  ```

---

## 4. Playback Context & Activation (Runner Phase)

### [MenuBarController.swift](../Sources/SparkleRecorder/MenuBarController.swift)
- **Lazy Window Resolution**:
  - `PlaybackContext` holds a reference to `WindowTracker` and the targets' metadata dictionary.
  - As the `Runner` schedules each action step, it calls `windowTracker.resolve(surfaceId:)` to lazy resolve/activate the target window *only* when the action is fired, supporting dynamic window movements.

---

## 5. SwiftUI Performance Audit & Optimization

### [MacroEditor.swift](../Sources/SparkleRecorder/MacroEditor.swift)
- **Identify Bottleneck**: Inside `TargetCrosshairView`, the `getDisplayPath(for:)` function maps and calculates complex path conformal projections (`conformPathPoint`) for every single point in the path inside the SwiftUI `body` rendering loop. During dragging, this triggers at 60Hz/120Hz, leading to CPU thrashing and frame drops.
- **Remedy**:
  - Store projected path coordinates inside a `ProjectionCacheKey` mapped dictionary in the Editor View Model.
  - When actions/zoom/window frames change, invalidate and re-project paths on-demand, allowing SwiftUI `body` to read statically.

---

## 6. Verification & Test Suite Requirements

To prevent regression bugs, the following validation test cases will be executed:

1. **Window Re-location and Replay**: Record mouse paths inside Slack window. Move the Slack window to a Sidecar iPad display or secondary monitor. Replay and verify cursor paths remain within a configurable tolerance (e.g. ±3 logical points).
2. **Window Resizing Scale Mapping**: Record a button-clicking flow in a browser window. Change the browser window scaling. Replay and verify normalized mapping works for proportional layouts; for reflowing layouts, verify LocatorEngine chooses OCR/AX before normalized fallback.
3. **Legacy Macro Persistence**: Load a v1 macro file (only absolute screen coordinate points). Verify that the `PointResolver` fallback matches screen-absolute mapping and replays properly.
4. **Targeted Disconnect Safety**: Record on an external display. Unplug the external display. Verify that the Runner pauses safely and asks the user to rebind the missing surface (does not clamp to random edges).
5. **Multiple Windows Matching**: Open two windows of Safari. Verify WindowTracker matches the correct window using the title matching regex pattern score.
6. **Multi-App Context Switching Replay**: Record a macro copying from Safari and pasting to Slack. Move both windows. Verify that the Runner successfully activates and targets the correct window for each action step during replay.

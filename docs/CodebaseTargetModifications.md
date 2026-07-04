# Codebase Target Modifications Plan

This document details the exact file changes, target functions, and implementation code snippets required to construct the upgraded coordinate and window tracker systems.

---

## 1. Data Model Upgrades

### [RecordedEvent.swift](file:///Applications/TinyTask-macOS-1.2.6/Sources/TinyRecorder/RecordedEvent.swift)
- **Target Changes**: Add optional window-relative coordinates.
- **Implementation Snippet**:
  ```swift
  public struct RecordedEvent: Codable, Equatable {
      // ... existing properties ...
      
      // New optional properties for window-bound coordinate space mapping
      public var windowLocalX: CGFloat?
      public var windowLocalY: CGFloat?
      public var windowNormalizedX: CGFloat?
      public var windowNormalizedY: CGFloat?
      
      // Ensure custom Codable decoding maps values correctly, defaulting to nil for legacy files
      // Swift will auto-derive if no custom CodingKeys are used. If custom CodingKeys are present,
      // add coding keys and use decodeIfPresent.
  }
  ```

---

## 2. Event Capture & Coordinate Updates (Recording Phase)

### [Recorder.swift](file:///Applications/TinyTask-macOS-1.2.6/Sources/TinyRecorder/Recorder.swift)
- **Target Property**: Add reference to the recording surface.
  ```swift
  final class Recorder: ObservableObject {
      // ... existing properties ...
      @Published private(set) var currentSurface: PlaybackSurface?
  ```
- **Target Function**: `startRecording(surface:)` and `loadEvents(_:surface:)`.
  ```swift
  @discardableResult
  func startRecording(surface: PlaybackSurface? = nil) -> Bool {
      // ... existing initialization ...
      self.currentSurface = surface
      // ...
  }
  
  func loadEvents(_ new: [RecordedEvent], surface: PlaybackSurface? = nil) {
      events = new
      liveDuration = new.last?.time ?? 0
      self.currentSurface = surface
  }
  ```
- **Target Function**: `handle(type:event:)`. Calculate and store window-relative parameters dynamically.
  ```swift
  private func handle(type: CGEventType, event: CGEvent) {
      // ...
      let loc = event.location
      
      var localX: CGFloat? = nil
      var localY: CGFloat? = nil
      var normX: CGFloat? = nil
      var normY: CGFloat? = nil
      
      if let surface = currentSurface {
          let lx = loc.x - surface.recordedFrame.x
          let ly = loc.y - surface.recordedFrame.y
          localX = lx
          localY = ly
          normX = surface.recordedFrame.width > 0 ? lx / surface.recordedFrame.width : 0
          normY = surface.recordedFrame.height > 0 ? ly / surface.recordedFrame.height : 0
      }
      
      let recorded = RecordedEvent(
          kind: kind,
          time: elapsed,
          x: loc.x,
          y: loc.y,
          keyCode: keyCode,
          flags: event.flags.rawValue,
          mouseButton: event.getIntegerValueField(.mouseEventButtonNumber),
          clickCount: event.getIntegerValueField(.mouseEventClickState),
          scrollDeltaY: /*...*/,
          scrollDeltaX: /*...*/,
          windowLocalX: localX,
          windowLocalY: localY,
          windowNormalizedX: normX,
          windowNormalizedY: normY
      )
      // ...
  }
  ```
- **Target Helper Function**: `updateRelativeCoordinates(for:)` to recalculate coordinates when a click/drag event is translated or inserted in the editor.
  ```swift
  private func updateRelativeCoordinates(for index: Int) {
      guard events.indices.contains(index) else { return }
      if let surface = currentSurface {
          let lx = events[index].x - surface.recordedFrame.x
          let ly = events[index].y - surface.recordedFrame.y
          events[index].windowLocalX = lx
          events[index].windowLocalY = ly
          events[index].windowNormalizedX = surface.recordedFrame.width > 0 ? lx / surface.recordedFrame.width : 0
          events[index].windowNormalizedY = surface.recordedFrame.height > 0 ? ly / surface.recordedFrame.height : 0
      }
  }
  ```
  *This helper will be called in `translateEventsLinear`, `conformPath`, `insertClick`, `insertDrag`, and `insertKeystroke`.*

---

## 3. Playback Coordinate Resolution (Replay Phase)

### [PointResolver.swift](file:///Applications/TinyTask-macOS-1.2.6/Sources/TinyRecorder/PointResolver.swift)
- **Target Function**: `resolve(_:context:)`. Integrate high-fidelity window-relative matching and multi-monitor boundaries clamping.
- **Code implementation**:
  ```swift
  public func resolve(_ event: RecordedEvent, context: PlaybackContext) -> CGPoint {
      let original = CGPoint(x: event.x, y: event.y)
      
      var resolvedPoint = original
      
      if context.coordinateMode == .boundWindowOffset,
         let currentFrame = context.currentSurfaceFrame {
          
          if let localX = event.windowLocalX, let localY = event.windowLocalY {
              // 1. Resolve relative window local points
              resolvedPoint = CGPoint(x: currentFrame.x + localX, y: currentFrame.y + localY)
              
              // 2. Responsive scale check if window width/height changed significantly
              if let recordedFrame = context.surface?.recordedFrame,
                 (abs(recordedFrame.width - currentFrame.width) > 5.0 || 
                  abs(recordedFrame.height - currentFrame.height) > 5.0) {
                  
                  if let normX = event.windowNormalizedX, let normY = event.windowNormalizedY {
                      resolvedPoint = CGPoint(
                          x: currentFrame.x + (normX * currentFrame.width),
                          y: currentFrame.y + (normY * currentFrame.height)
                      )
                  }
              }
          } else if let recordedFrame = context.surface?.recordedFrame {
              // Fallback for legacy absolute coordinate macros
              let dx = currentFrame.x - recordedFrame.x
              let dy = currentFrame.y - recordedFrame.y
              resolvedPoint = CGPoint(x: event.x + dx, y: event.y + dy)
          }
      }
      
      // Bounding Box Clamping across MacBook display + Sidecar + secondary monitors
      #if canImport(AppKit)
      if let screens = NSScreen.screens.first {
          let unionFrame = NSScreen.screens.dropFirst().reduce(screens.frame) { $0.union($1.frame) }
          let primaryHeight = screens.frame.height
          
          let minX = unionFrame.minX
          let maxX = unionFrame.maxX
          let minY_CG = primaryHeight - unionFrame.maxY
          let maxY_CG = primaryHeight - unionFrame.minY
          
          resolvedPoint.x = max(minX, min(resolvedPoint.x, maxX))
          resolvedPoint.y = max(minY_CG, min(resolvedPoint.y, maxY_CG))
      }
      #endif
      
      return resolvedPoint
  }
  ```

---

## 4. UI View & Controller Modifications

### [MenuBarController.swift](file:///Applications/TinyTask-macOS-1.2.6/Sources/TinyRecorder/MenuBarController.swift)
- **Target Function**: `actuallyStartRecording()`.
  - Pass the resolved initial surface to `recorder.startRecording(surface:)`:
    ```swift
    let capture = WindowSurfaceCapture()
    self.recordedSurface = try? capture.captureFrontmostWindow()
    let ok = recorder.startRecording(surface: self.recordedSurface)
    ```
- **Target Function**: `selectMacro(_:)` & `persistCurrentMacroIfNeeded()`.
  - Pass surface details when loading events:
    ```swift
    recorder.loadEvents(m.events, surface: m.surface)
    ```
- **Target Function**: `preparePlaybackContext(for:completion:)`.
  - Replace frontmost application query with scoring loop.
  - Implement scoring check:
    ```swift
    // Loop through windows, calculate scoring weights:
    // bundleIdentifier matching: +100
    // windowTitlePattern regex match: +80
    // recordedDisplayId matching: +20
    // Select the highest scoring window as the PlaybackContext target.
    ```

---

## 5. Verification & Test Suite Requirements

To prevent regression bugs, the following validation test cases will be executed:

1. **Window Re-location and Replay**: Record mouse paths inside Slack window. Move the Slack window to a Sidecar iPad display or secondary monitor. Replay and verify cursor paths remain perfectly positioned relative to the window.
2. **Window Resizing Scale Mapping**: Record a button-clicking flow in a browser window. Change the browser window scaling (e.g. dragging bounds to change width/height). Replay and verify click locations map correctly using the `windowNormalized` ratio.
3. **Legacy Macro Persistence**: Load a v1 macro file (only absolute screen coordinate points). Verify that the `PointResolver` fallback matches screen-absolute mapping and replays properly.
4. **Targeted Disconnect Safety**: Record on an external display. Unplug the external display. Verify that resolved points clamp correctly within the MacBook built-in monitor limits.

# SparkleRecorder Window-Bound Automation Architecture
## Architecture Draft v0.9
### From Screen-Coordinate Replay to Window-Relative, Visual, and Semantic Automation

This document defines the high-level architecture, security permissions, and coordinate mappings required to transition SparkleRecorder from simple screen clicker playback to robust, target-bound automation.

---

## 1. Security & System Permissions

Due to macOS Transparency, Consent, and Control (TCC) security restrictions, the automation engine requires specific system privileges. 

> [刻] All permission checks and API calls must be availability-gated by macOS version (using `#available`). APIs like `SCScreenshotConfiguration` or ScreenCaptureKit still require explicit runtime checks to handle OS updates gracefully.

| Feature Area | Required System Permission | API Constants & Functions | Purpose |
| :--- | :--- | :--- | :--- |
| **Semantic Control** | **Accessibility** | `AXIsProcessTrustedWithOptions`, `kAXTrustedCheckOptionPrompt` | Programmatic UI element queries and actions via `AXUIElement`. |
| **Event Recording** | **Input Monitoring / Listen Events** | `CGPreflightListenEventAccess()`, `CGRequestListenEventAccess()` | Capturing keyboard/mouse events system-wide using `CGEventTap`. |
| **Event Playback** | **Post Event Access** | `CGPreflightPostEventAccess()`, `CGRequestPostEventAccess()` | Injecting keyboard and mouse events to the WindowServer queue using `CGEvent.post(tap:)`. |
| **Visual Analysis** | **Screen Recording** | `CGPreflightScreenCaptureAccess()`, `CGRequestScreenCaptureAccess()` | Using `ScreenCaptureKit` and fetching titles via `CGWindowListCopyWindowInfo`. |
| **App Automation** | **Automation / AppleEvents** | `NSAppleEventDescriptor`, `NSAppleScript` | Sending AppleEvents to control scriptable system apps (Safari, Finder, etc.). |

---

## 2. Core System Modules

The target architecture consists of the following components:

```
DisplayManager  <-->  WindowTracker  <-->  CaptureService
                                                 |
                                                 v
                                           VisionDetector
                                                 |
                                                 v
Executor        <--   LocatorEngine  <--   CoordinateMapper
  |
  +-> AXPressBackend
  +-> CGEventBackend
  +-> KeyboardBackend
  +-> AppleEventBackend
```

### A. DisplayManager
- Maps the layout of active screens (MacBook Screen, external monitors, Sidecar iPad).
- Identifies display bounds, Retina scale factors (`backingScaleFactor`), and tracks display changes using `NSApplicationDidChangeScreenParametersNotification`.
- **Key APIs**: `NSScreen.screens`, `NSScreen.deviceDescription`, `CGDisplayBounds`.

### B. WindowTracker
- Finds target windows across currently discoverable windows and active display configurations (does NOT promise tracking across virtual Spaces as they are not stable background environments).
- Resolves target window candidates using a **weighted scoring system**:
  1. `bundleIdentifier`: Strong Match (100 pts)
  2. `windowTitlePattern` (Regex matching): Strong Match (80 pts)
  3. Window size bounds comparison: Medium Match (40 pts)
  4. `recordedDisplayId`: Low Match (20 pts)
  5. `recordedWindowId` (from `CGWindowListCopyWindowInfo`): Secondary helper for current session only.
- **Key APIs**: `AXUIElement`, `CGWindowListCopyWindowInfo`, `SCShareableContent`.

### C. CaptureService
- Captures frames from the target window using `ScreenCaptureKit`.
- **Visible-Window Automation Constraints**:
  - For coordinate-based `CGEvent` playback, the target window must be visible, not minimized, and preferably frontmost/active.
  - For `AXPress` or `AppleEvent` execution, the target app may not always need physical mouse focus.
- **Key APIs**: `SCStream` (for real-time tracking), `SCScreenshotManager` (for single-frame snapshots).

### D. VisionDetector
- Processes captured window frames to extract visual anchors:
  - **OCR**: `Vision` framework (`VNRecognizeTextRequest`, `VNImageRequestHandler`) to extract labels and text zones.
  - **Template Matching**: Image-matching via `Accelerate` framework or custom pixel-matching (instead of heavy OpenCV dependencies).
  - **Color/State Detection**: Uses `CoreImage` / `vImage` for status colors, red-dot notifications, or modal popups.

### E. CoordinateMapper
- Coordinates translation across multiple bounds in a single canonical coordinate space:
  - `Screen Point` ↔ `Window Local Point` (relative to window frame)
  - `Window Local Point` ↔ `Normalized Point` (0.0 to 1.0)
  - `Capture Frame Pixel` ↔ `Window Point` (accounting for Retina backing scales)
  - `Vision Bounding Box` ↔ `Capture Frame Pixel`
- **Fail-Safe Policy**: If a point is resolved outside the active window frame bounds, execution asserts a failure instead of clamping coordinates to screen edges to prevent destructive out-of-window misclicks.

### F. LocatorEngine
- Matches target coordinates using a prioritized chain:
  `AX Element` ➜ `Image Template` ➜ `OCR Text` ➜ `Window Local Point` ➜ `Window Normalized` ➜ `Absolute Screen Point (Fallback)`.

### G. Executor (Multi-Backend)
- **AXPressBackend**: Sends clicks directly to native buttons without moving the physical cursor using `AXUIElementPerformAction`.
- **CGEventBackend**: Simulates coordinate-based mouse inputs for custom-drawn UI, games, and web apps.
- **Experimental postToPid**: Process-targeted event posting will be treated as an experimental optimization and not a guaranteed background operation.
- **KeyboardBackend**: Simulates key inputs and keystroke groups.
- **AppleEventBackend**: Interacts with script-enabled apps directly.
- **User Conflict Monitor**: Uses `CGEventTap` listening to check if the user is moving the mouse or typing during playback, automatically pausing execution to prevent cursor fighting.

---

## 3. Upgraded Data Schemas (Schema Version 2 - Multi-App Compatible)

To support automation scripts that span across multiple distinct applications (e.g., copying text from Safari and pasting it into Slack), the macro schema organizes windows into a `surfaces` lookup table. Individual events reference their specific target window by `surfaceId`.

### PlaybackSurface Schema
```json
{
  "schemaVersion": 2,
  "surfaceId": "slack-main-window",
  "surfaceKind": "window",
  "bundleIdentifier": "com.tinyspeck.slack",
  "appName": "Slack",
  "windowTitle": "general - Slack",
  "windowTitlePattern": ".* - Slack",
  "recordedWindowId": 98765,
  "recordedDisplayId": 2,
  "recordedFrame": { "x": 100, "y": 100, "width": 800, "height": 600 },
  "recordedScale": 2.0,
  "coordinateSpace": "windowLocalPoint",
  "requiresVisibleWindow": true
}
```

### Macro Schema (With Multi-App Surface Lookup)
```json
{
  "schemaVersion": 2,
  "id": "workflow-macro-1",
  "name": "Browser to Chat Workflow",
  "surfaces": {
    "safari-1": {
      "surfaceId": "safari-1",
      "surfaceKind": "window",
      "bundleIdentifier": "com.apple.Safari",
      "appName": "Safari",
      "windowTitle": "GitHub",
      "recordedFrame": { "x": 50, "y": 50, "width": 900, "height": 700 },
      "recordedScale": 2.0
    },
    "slack-1": {
      "surfaceId": "slack-1",
      "surfaceKind": "window",
      "bundleIdentifier": "com.tinyspeck.slack",
      "appName": "Slack",
      "windowTitle": "general - Slack",
      "recordedFrame": { "x": 1000, "y": 50, "width": 600, "height": 700 },
      "recordedScale": 2.0
    }
  },
  "events": [
    {
      "type": "click",
      "time": 1.245,
      "surfaceId": "safari-1",
      "point": {
        "absoluteScreenPoint": { "x": 300, "y": 250 },
        "windowLocalPoint": { "x": 250, "y": 200 },
        "windowNormalized": { "x": 0.27, "y": 0.28 }
      },
      "coordinateBinding": "targetWindow",
      "coordinateStrategy": "windowLocalPreferred"
    },
    {
      "type": "click",
      "time": 3.822,
      "surfaceId": "slack-1",
      "point": {
        "absoluteScreenPoint": { "x": 1150, "y": 450 },
        "windowLocalPoint": { "x": 150, "y": 400 },
        "windowNormalized": { "x": 0.25, "y": 0.57 }
      },
      "coordinateBinding": "targetWindow",
      "coordinateStrategy": "windowLocalPreferred"
    }
  ]
}
```

---

## 4. Multi-App Recording & Playback Orchestration

### A. Recording Multi-App Steps
During recording:
1. To avoid blocking the low-level `CGEventTap` callback thread, window tracking runs on a throttled background query (`RecordingSurfaceTracker`) refreshing focused window details at `150ms`.
2. When a mouse event occurs:
   - If the event is a `mouseDown` / `mouseMoved`, the active surface mapping is checked against the cached surface.
   - For drag gestures, the `surfaceId` is locked to the `mouseDown` origin window for the entire duration of the drag until `mouseUp`.
3. If the focused window shifts to a new application or distinct window (using the multi-factor scoring matching instead of simple bundle IDs):
   - A new `PlaybackSurface` is generated and added to `surfaces` with a unique ID (e.g. `slack-1`).
4. Subsequent events are stamped with `surfaceId` mapping to the active surface. If the coordinate falls outside the target window frame, it is marked with `coordinateBinding = .globalScreen`.

### B. Playback Multi-App Steps
During playback, for each event in the queue:
1. Read the `surfaceId`. Rather than activating all target apps at the start, window resolution is lazy:
   - When the `Runner` approaches an event matching a target `surfaceId`, it calls `WindowTracker` to lazy resolve the active window bounds.
   - If the target app is not focused/frontmost and requires mouse event playback, the `Runner` executes `app.activate()` immediately before dispatching the event.
2. Resolve coordinates using `PointResolver` which returns a `Result<CGPoint, PointResolveError>`.
   - If the coordinate is out of bounds or the display is disconnected, the runner fails safely, pauses playback, and prompts the user (no clamping, no absolute coordinate fallback).
3. If the `surfaceId` is null or `coordinateBinding` is `.globalScreen`, the coordinates are treated as global coordinates.

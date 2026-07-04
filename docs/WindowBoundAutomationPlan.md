# TinyTask Window-Bound Automation Architecture
## From Screen-Coordinate Replay to Window-Relative, Visual, and Semantic Automation

This document defines the high-level architecture, security permissions, and coordinate mappings required to transition TinyTask from simple screen clicker playback to robust, target-bound automation.

---

## 1. Security & System Permissions

Due to macOS Transparency, Consent, and Control (TCC) security restrictions, the automation engine requires specific system privileges. The following table maps the features to their required API permissions and detection APIs:

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
- Maps the layout of connected displays (MacBook Screen, external monitors, Sidecar iPad).
- Identifies display bounds, Retina scale factors (`backingScaleFactor`), and tracks display changes using `NSApplicationDidChangeScreenParametersNotification`.
- **Key APIs**: `NSScreen.screens`, `NSScreen.deviceDescription`, `CGDisplayBounds`.

### B. WindowTracker
- Finds target windows across spaces and active screen configurations.
- Resolves target window candidates using a **weighted scoring system**:
  1. `bundleIdentifier`: Strong Match (100 pts)
  2. `windowTitlePattern` (Regex matching): Strong Match (80 pts)
  3. Window size bounds comparison: Medium Match (40 pts)
  4. `recordedDisplayId`: Low Match (20 pts)
  5. `recordedWindowId` (from `CGWindowListCopyWindowInfo`): Secondary helper for current session only.
- **Key APIs**: `AXUIElement`, `CGWindowListCopyWindowInfo`, `SCShareableContent`.

### C. CaptureService
- Captures frames from the target window using `ScreenCaptureKit`.
- **Constraints**: Focuses on **Visible-Window Automation**. The target window must be active, visible, and not minimized. Capturing hidden/minimized windows is not guaranteed by macOS.
- **Key APIs**: `SCStream` (for real-time tracking), `SCScreenshotManager` (for single-frame snapshots).

### D. VisionDetector
- Processes captured window frames to extract visual anchors:
  - **OCR**: `Vision` framework (`VNRecognizeTextRequest`, `VNImageRequestHandler`) to extract labels and text zones.
  - **Template Matching**: Image-matching via `Accelerate` framework or custom pixel-matching (instead of heavy OpenCV dependencies).
  - **Color/State Detection**: Uses `CoreImage` / `vImage` for status colors, red-dot notifications, or modal popups.

### E. CoordinateMapper
- Translate between coordinates across multiple bounds:
  - `Screen Point` ↔ `Window Local Point` (relative to window frame)
  - `Window Local Point` ↔ `Normalized Point` (0.0 to 1.0)
  - `Capture Frame Pixel` ↔ `Window Point` (accounting for Retina backing scales)
  - `Vision Bounding Box` ↔ `Capture Frame Pixel`

### F. LocatorEngine
- Matches target coordinates using a prioritized chain:
  `AX Element` ➜ `Image Template` ➜ `OCR Text` ➜ `Window Local Point` ➜ `Window Normalized` ➜ `Absolute Screen Point (Fallback)`.

### G. Executor (Multi-Backend)
- **AXPressBackend**: Sends clicks directly to native buttons without moving the physical cursor using `AXUIElementPerformAction`.
- **CGEventBackend**: Moves the cursor and clicks for custom-drawn UI, games, and web apps.
- **KeyboardBackend**: Simulates key inputs and keystroke groups.
- **AppleEventBackend**: Interacts with script-enabled apps directly.
- **User Conflict Monitor**: Uses `CGEventTap` listening to check if the user is moving the mouse or typing during playback, automatically pausing execution to prevent cursor fighting.

---

## 3. Upgraded Data Schemas (Schema Version 2)

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

### RecordedEvent Action Schema
```json
{
  "schemaVersion": 2,
  "type": "click",
  "time": 5.245,
  "point": {
    "absoluteScreenPoint": { "x": 420, "y": 280 },
    "windowLocalPoint": { "x": 320, "y": 180 },
    "windowNormalized": { "x": 0.40, "y": 0.30 },
    "capturePixelPoint": { "x": 640, "y": 360 }
  },
  "target": {
    "locatorChain": [
      { "type": "axElement", "axIdentifier": "submit-btn", "axRole": "AXButton" },
      { "type": "image", "templateId": "submit_btn_image", "threshold": 0.85 },
      { "type": "windowLocalPoint" },
      { "type": "windowNormalized" }
    ]
  },
  "execution": {
    "preferredBackend": "auto",
    "timeoutMs": 3000,
    "retry": { "maxAttempts": 3, "intervalMs": 300 }
  },
  "verify": {
    "type": "imageDisappears",
    "templateId": "submit_btn_image",
    "timeoutMs": 2000
  },
  "onFail": {
    "strategy": "runRecoveryFlow",
    "flowId": "close-popups-and-return"
  }
}
```

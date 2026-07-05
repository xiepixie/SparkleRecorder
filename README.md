# SparkleRecorder

SparkleRecorder is a native macOS macro recorder. It records mouse, keyboard, scroll, wait, window, and text-anchor actions, stores them in a searchable macro library, and replays them from the Dock, menu bar, global hotkeys, or the command line.

The app is built with Swift, SwiftUI, AppKit, Carbon hotkeys, `CGEventTap`, and `CGEvent` playback. It does not use Electron and it does not require an account or telemetry.

## What It Does

- Records clicks, drags, scrolls, keyboard events, modifier changes, and waits.
- Groups low-level events into readable action groups for the editor timeline.
- Saves macros with loops, speed, notes, tags, favorites, icons, hotkeys, play stats, window bindings, and optional chained playback.
- Replays against absolute screen coordinates, recorded window offsets, or OCR/text anchors when available.
- Imports native `.tinyrec` JSON, legacy Windows `.rec` files, and editable `.txt` / `.trm` text macros.
- Exports native `.tinyrec`, editable text, and self-running `.command` scripts.
- Provides a full library window, menu-bar popover, recording HUD, countdown overlay, welcome flow, and preferences.

## User Flow

1. Launch SparkleRecorder and grant Accessibility plus Input Monitoring permissions.
2. Press Record from the library, menu bar, menu item, or hotkey.
3. After the countdown, perform the workflow you want to automate.
4. Stop recording. The macro is saved into the library.
5. Play the macro, assign a per-macro hotkey, edit its timeline, bind it to a window, or export it.

The default global hotkeys are:

| Action | Default |
| --- | --- |
| Record / stop recording | F6 |
| Stop everything | F7 |
| Play current macro | F8 |
| New recording | Command-R |
| Play | Command-P |
| Stop | Command-. |
| Import | Command-O |
| Export | Command-E |
| Settings | Command-, |
| Library window | Command-0 |

## Data Model

The native `.tinyrec` file is JSON. A saved macro contains metadata plus a list of `RecordedEvent` values:

```json
{
  "version": 3,
  "name": "Daily workflow",
  "loops": 1,
  "speed": 1.0,
  "tags": ["work"],
  "favorite": false,
  "hotkey": { "keyCode": 97, "name": "F6" },
  "surfaces": {},
  "followWindowOffset": true,
  "events": [
    {
      "kind": 5,
      "time": 0.012,
      "x": 412.0,
      "y": 188.0,
      "keyCode": 0,
      "flags": 256,
      "mouseButton": 0,
      "clickCount": 0,
      "scrollDeltaY": 0,
      "scrollDeltaX": 0
    }
  ]
}
```

The live library is stored at:

```text
~/Library/Application Support/SparkleRecorder/library.json
```

On first launch after the rename, SparkleRecorder copies any existing pre-rename library file into the new support folder if the new file does not already exist.

## Import And Export

SparkleRecorder accepts these formats:

| Format | Purpose |
| --- | --- |
| `.tinyrec` / `.json` | Native macro with full metadata |
| `.rec` | Legacy Windows macro recorder event stream |
| `.txt` / `.trm` | Line-oriented text macro format |
| `.command` | Self-running exported script |

Text macro exports use this header:

```text
SPARKLERECORDER 1
# move, click, type Command-Space, scroll
@0.000  MOVE 640 400
@0.100  DOWN 640 400 L
@0.160  UP 640 400 L
@0.300  FLAGS CMD 0x100000
@0.310  KEYDOWN SPACE +CMD
@0.380  KEYUP SPACE +CMD
@0.700  SCROLL -3 0
```

Older text macros from before the rename are still accepted on import.

Command-line conversion:

```bash
SparkleRecorder.app/Contents/MacOS/SparkleRecorder --convert macro.rec macro.tinyrec
SparkleRecorder.app/Contents/MacOS/SparkleRecorder --convert macro.tinyrec macro.txt
```

Command-line playback:

```bash
SparkleRecorder.app/Contents/MacOS/SparkleRecorder --play macro.tinyrec
```

## Development

Build and install locally:

```bash
./build.sh
```

Useful environment variables:

```bash
SPARKLERECORDER_INSTALL_DIR="$HOME/Desktop" ./build.sh
SPARKLERECORDER_SWIFT_FLAGS="-Xswiftc -DHIDE_PERMISSION_BANNER" ./build.sh
SPARKLERECORDER_SIGN_ID="Developer ID Application: Name (TEAMID)" ./build.sh
```

Run tests:

```bash
swift test
```

Notarization uses `notarize.sh` after a Developer ID signed build.

## Architecture

The detailed architecture document is in [docs/SparkleRecorderArchitecture.md](docs/SparkleRecorderArchitecture.md). The 2026 modernization plan is in [docs/ArchitectureAndTestingModernizationPlan2026.md](docs/ArchitectureAndTestingModernizationPlan2026.md).

Key areas:

| Area | Main Files |
| --- | --- |
| App shell | `AppDelegate.swift`, `main.swift`, `MainWindowController.swift` |
| Library and settings | `MacroLibrary.swift`, `SavedMacro.swift`, `AppState.swift` |
| Recording | `Recorder.swift`, `EventTapThread.swift`, `RecordingSurfaceTracker.swift` |
| Playback | `Player.swift`, `MouseKeyboardSynthesizer.swift`, `PointResolver.swift` |
| Window and OCR targeting | `WindowTracker.swift`, `CoordinateMapper.swift`, `ScreenCaptureService.swift`, `VisionDetector.swift`, `LocatorEngine.swift` |
| Editing | `MacroEditor.swift`, `MacroTransformer.swift`, `Components/Editor/*` |
| Import/export | `MacroImport.swift`, `TextMacroFormat.swift` |

## Known Limits

- Secure input fields and hardened apps may reject synthetic input.
- OCR text anchors depend on screen content, language quality, and Screen Recording permission.
- Legacy `.rec` import is best-effort for non-US keyboard layouts and unusual wheel data.
- Moving or resizing target windows can still affect playback when no window binding or text anchor is available.

## License

[Apache-2.0](LICENSE).

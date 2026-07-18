# Settings Experience

Updated: 2026-07-14

## Current State

- The dedicated Settings window renders every section in one long column.
- Control widths vary by row, which makes labels and controls drift and can push the recording mode segmented control against the card edge.
- Supporting copy often uses tertiary contrast and is difficult to read in dark mode.
- SparkleRecorder has English and Simplified Chinese catalogs but exposes no app-language preference.

## Target State

- The dedicated window uses a balanced two-column layout for application, recording, replay, hotkey, and permission settings. Visual Evidence remains full width because its enabled state contains detailed diagnostics and retention controls.
- The compact popover layout remains a single column.
- Rows use stable control widths, descriptions use secondary contrast, and headers can wrap their status badges without overlap.
- Language offers System Default, English, and Simplified Chinese. A changed preference is applied only through an explicit Apply and Relaunch action so SwiftUI `Text` and imperative `String(localized:)` calls change together on the next process launch.

## Boundaries

- Language selection is an app-edge preference stored in `UserDefaults`; it does not belong in `SparkleRecorderCore`.
- `build.sh` compiles every checked-in domain String Catalog into the packaged app's `Contents/Resources`; generated `.lproj` output remains build-only and `.xcstrings` remain the sole localization source of truth.
- System Default removes the app override instead of copying the current macOS language.
- Relaunch is initiated only by direct user action. Merely opening Settings or changing the picker does not quit the app.
- No existing recording, playback, permission, retention, or hotkey semantics change.

## Verification

- Unit tests cover language preference persistence and `AppleLanguages` mapping using an isolated defaults suite.
- Swift 6 build and targeted tests pass.
- Product screenshots are checked at the default Settings window size and a narrower supported width for clipping, overlap, readable descriptions, and stable control alignment.

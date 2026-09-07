# Robust Reconstruction Evidence Audit

Updated: 2026-09-06

Status: Current implementation audit; automated verification complete, live Screen Recording acceptance blocked

This audit reviews whether recording evidence and AI-assisted reconstruction can produce a robust playable macro across real user scenarios. Code and direct tests remain the implementation source of truth.

## 1. Current evidence and playback capability

The recording stack already has five distinct evidence layers:

1. deterministic playable events, including window/content-relative coordinates;
2. bounded high-resolution mechanical input evidence plus playable-to-evidence provenance;
3. ScreenCaptureKit video recording;
4. PNG keyframes with OCR, window, and Accessibility observations;
5. reconstruction coverage, uncertainty, testing, acceptance, and rollback.

The default semantic capture implementation records a 30 fps H.264 MOV and event-aligned PNG keyframes when Screen Recording permission is available. Action-only recording remains supported when visual evidence is intentionally disabled.

The candidate playback Interface is narrower than the evidence Interface. It currently supports coordinate replay, text locators, bounded text waits, and text verification. It does not yet support an executable image/template locator even though recorded frames can provide image evidence.

## 2. User-facing parameters with real leverage

Do not expose every low-level capture constant. Keep sampling, codec, OCR, scroll compaction, and keyframe scheduling behind deep Modules unless product evidence shows users need direct control.

The high-leverage parameters are:

### Evidence intensity

- `videoAndKeyframes` — default balanced mode; continuous video plus sparse high-value keyframes.
- `keyframesOnly` — no movie; useful when video storage is undesirable but visual checkpoints are still needed.
- `diagnosticRich` — continuous video plus dense event keyframes for difficult reconstruction/debugging.

### Capture scope

- frontmost window — best privacy/locality for normal single-window workflows;
- display — needed for cross-app, system-dialog, popup, and multi-window workflows on one display.

Application-wide and arbitrary region capture are not product-ready merely because enum cases exist; they need real ScreenCaptureKit implementations before being exposed.

### Reconstruction objective

- faithful — preserve timing, path-sensitive gestures, and coordinate semantics unless evidence proves a safer equivalent;
- robust — prefer evidence-backed text locators, bounded waits/verification, normalized/window-relative coordinates, content-normalized text-anchor geometry, and explicit fallback policy.

Mechanical transformations such as scroll compaction remain deterministic Core behavior and are not AI parameters.

## 3. Implemented repairs and remaining gaps

### Implemented — stable window identity

Keyframe and window-metadata re-resolution now prefer stable `windowID`, retain bundle identity as a safety check, and use the original title only as a fallback when no window ID was recorded. Browser navigation or document-title changes no longer invalidate the same OS window.

### Implemented — capture intensity and scope are real product settings

`videoAndKeyframes`, `keyframesOnly`, and `diagnosticRich` now flow through AppState, semantic preflight, Recorder, and the live capture configuration. Settings exposes the three evidence modes plus `Current window` / `Entire display` capture scope.

Balanced `videoAndKeyframes` keeps continuous video but uses sparse high-value PNG checkpoints. Discrete wheel bursts stay in the movie instead of creating one screenshot/OCR checkpoint per wheel event; if movie startup fails, the session falls back to keyframe-only scroll evidence. `keyframesOnly` and `diagnosticRich` retain dense event checkpoints, so the modes now have distinct runtime semantics rather than being dormant enum values.

### Implemented — reconstruction receives aligned mechanical evidence

When source identity matches the recording, reconstruction export includes `input-evidence.json` plus the existing `alignment.playableEvidenceLinks`. Edited/stale sources do not receive that evidence. This lets an external author understand the high-resolution mouse/scroll trajectory without re-expanding compact playable events.

### Implemented — visual evidence degrades instead of failing as one monolith

Movie start/finish, individual keyframe capture, and frame indexing failures are recorded as `captureIssues`. Successfully captured video, frames, timeline events, and observations survive independently. Bundle readiness surfaces degraded capture explicitly.

### Implemented — explicit AI optimization objective

Reconstruction export now stores the `faithful` / `robust` optimization policy once inside `authoring-contract.json`; the small `harness.json` only records the selected objective and staged reading plan. The policy cannot grant capabilities beyond the same authoring contract's `macro-candidate/v4` capability: robust mode may prefer evidence-backed text locators, bounded waits, verification, window/content-relative coordinates, and `preferContentNormalizedTextGeometry`; faithful mode preserves demonstrated timing and targeting unless correction is required. Robust authoring rules prefer `observedContentNormalizedFrame`, `searchContentNormalizedRegion`, and `coordinateFallbackContentNormalized` for surface-bound text actions when aligned evidence supports them. Absolute anchor geometry remains a compatibility fallback rather than the preferred robust targeting representation.

Playback uses the same geometry semantics for AI-authored and manually taught text targets. `TextAnchorGeometryProjection` resolves normalized anchor geometry against the current content frame, so target-window movement and resizing update OCR search regions and coordinate fallback without rewriting the candidate. Candidate authoring now requires an explicit `surfaceId` for every text-backed mouse action, `waitForText`, and `verifyText`, not only normalized geometry. Multi-surface runtime never inherits an arbitrary first-surface fallback; legacy accepted macros may use the sole Playback Surface only when exactly one exists. Locator-backed mouse input also requires target-window binding plus locator-only strategy, and a pointer gesture keeps one surface/anchor/fallback/timeout identity from mouse-down through mouse-up. `PlaybackTextTargetResolver` owns stable window capture and OCR crop, while `TextAnchorMatchRanking` owns exact/contains, fuzzy tolerance, observed-position scoring and occurrence selection in pure Core for both text-click location and wait/verify presence checks.

External AI authoring treats Playback Surface identity as Source Revision-owned context. New v4 candidate JSON omits `macro.surfaces`; authors choose among existing surfaces only through `event.surfaceId`. `source-context.json` v2 and `reconstruction.json` v2 expose minimized read-only Surface summaries together with each Reconstruction Action's `surfaceID`, source/global points, available content-normalized points and text semantics, so an external author does not have to infer the target window from event indices or receive local WindowServer/display identity. App-owned Candidate Draft editing retains an explicit trusted rebinding path for user-selected live windows; rebinding creates a new Candidate and requires a fresh test.

The coordinate/runtime cleanup also restores the intended Core/App layering. `SparkleRecorderCore` no longer queries `NSWorkspace`, `NSScreen`, or Accessibility for content geometry. The App-edge `WindowContentFrameResolver` resolves the live content frame and supplies it through `PlaybackContext`; `PointResolver` and `PlaybackLocatorFallback` remain pure consumers of current/persisted geometry. This keeps window movement/resizing support shared without hiding platform side effects inside Core.

The old public `RecordingCapturePolicy.localOnly` / `allowsAIFrameExport` values were also removed from the current product Interface because they never enforced sharing. Their JSON keys remain private wire-compatibility fields so existing bundles continue to decode and round-trip; explicit `Video & images` reconstruction export is the user-owned sharing decision.

### Remaining — capture follows one initial target

The current movie session targets the window/display resolved at recording start. A true cross-app recording needs either display capture or multi-segment target handoff. Exposing display scope is the safe first product slice; automatic multi-window segmentation should be implemented only with explicit provenance tests.

### Remaining — image evidence cannot yet become an executable visual locator

Candidate capabilities expose only text locators. The old unused `LocatorEngine.template` / always-unavailable template matcher stubs were removed so the code no longer advertises a hypothetical capability. Frames/video can improve semantic understanding, but icon-only/canvas/image targets still fall back to coordinates. Do not claim image-locator robustness until a deterministic visual matcher, persisted template asset, fallback semantics, and playback tests exist.

## 4. Remaining implementation order

1. Live-accept window and display capture with Screen Recording permission enabled.
2. Add automatic multi-window/multi-display segmentation only after provenance tests define target handoff semantics.
3. Build executable image/template locators as a separate capability workstream; do not fake them through AI-authored coordinates.
4. Profile video/keyframe/OCR storage and CPU cost on representative long recordings before exposing lower-level sampling knobs.

## 5. Acceptance

Automated tests must prove:

- a stable window ID survives title drift;
- capture mode reaches preflight and the live semantic session;
- balanced video mode does not capture dense per-keystroke/per-drag PNGs;
- diagnostic mode retains dense event keyframes;
- aligned input evidence is present in reconstruction packages and withheld when source identity is unverified;
- optional OCR/keyframe failures cannot silently invalidate a valid movie;
- candidate capabilities still reject unsupported image/pixel event kinds.

Live acceptance remains required for Screen Recording permission, real browser title changes, cross-app display capture, movie/keyframe artifact existence, and reconstruction against an actual recorded workflow.

## 6. Verification evidence

Automated verification on 2026-09-06 completed with:

- 1,023 Swift Testing tests across 148 suites passed;
- targeted text-target, locator-fallback, surface-binding, and pure geometry/ranking suites passed;
- Swift 6 Debug and Release builds passed;
- `git diff --check` passed;
- `SparkleRecorderCore` contains no AppKit/Cocoa/Vision/ScreenCaptureKit/IOKit/SwiftUI imports;
- obsolete locator-strategy, duplicated geometry/fallback, and template-locator seams were removed from current source.

The installed app preflight was also run directly. Input Monitoring and Accessibility were authorized, while Screen Recording remained denied. The installed app therefore correctly reported visual capture as blocked with zero frames and zero video segments. This verifies the permission gate, but it does not substitute for live movie/keyframe acceptance: a new recording must still be exercised after Screen Recording is granted and the current source build is installed.

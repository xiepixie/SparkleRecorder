# Playback and presentation reliability audit

Updated: 2026-09-06
Role: Active bugfix ledger; live user-reported playback failure is not yet declared resolved.

Evidence: selected macro has 23 keyboard/flags events, one Chrome surface and an empty runs directory. The editor and Review can decode its actions. Manual playback only closes NSPopover, does not hide the standalone library, bypasses the shared target application preparation client, and never saves successful run evidence. Aborted completion returns without replacing the Playing status. Post-event permission is defined in PermissionCenter but unused by playback. Installed CLI preflight reports denied Accessibility/Input Monitoring; this is supporting evidence, not proof of the GUI process's effective post-event permission.

Fix boundary: use shared prepared playback for manual runs, preserve stop/cancellation and chaining, check post-event permission before preparation/execution through an injected app-edge client, and surface rejected/failed outcomes. Record successful manual runs through existing evidence persistence. Preserve source buffers across selection/loading. UI work removes measured structural main-thread IO/decoding and prevents loading from trapping dismissal.

Validation: fake permission/target/player clients; shared playback/runtime and recording pipeline suites; full Swift Testing and Release packaging. Actual target-app behavior requires a controlled live replay; do not run arbitrary recorded shortcuts into the user's application to manufacture a pass.


Implemented: manual playback now uses AutomationScheduledMacroPreviewClient/AutomationPlayerClient target preparation, receipts and success evidence. It hides the library before activating/launching the target, announces Playing only after startup is accepted, exposes failure, supports cancellation during preparation, and preserves chain-cycle detection. Review trials hide then restore the app. GUI Player/automation and CLI entrypoints check post-event permission. Selected-macro history opens that macro’s latest run; workflow-wide history remains in automation. Buffered events are persisted only when owned by the selected macro and not loading.

Performance: review bundle validation and file scans now run detached; image previews decode/downsample off main to at most 1024 pixels. Initial Review loading retains an available Close/Esc action and cancels publication after dismissal. No arbitrary animation delay or global FPS claim is introduced.

Validation before final packaging: 843 tests / 106 suites passed. Permission rejection and rejected-start presentation have explicit fake-client tests; existing cancellation/reservation/target preparation, recording pipelines and complete regression suites also pass. No arbitrary user macro was replayed against Chrome during diagnosis.

GUI observation: the installed app’s Settings > System permissions showed Accessibility, Input Monitoring and Screen Recording all authorized. The CLI denial must not be represented as proof that GUI playback lacked permission. Missing hide/target-preparation and outcome handling are independently confirmed code defects.

## Foreground correction after build 103

User confirmed hiding worked but Chrome was not raised. The old preparation only called `activate()` and checked window existence. Apple documents activation as a request, not a guarantee. The revised path yields activation before hiding, restores and raises the resolved bound AX window, and waits for both active application and matching focused window before allowing playback. Failure is explicit and no playback starts. Manual and Review hide only after the prepared handoff; unbound playback keeps its prior behavior. Platform handles remain MainActor-owned; bounded readiness/cancellation sequencing has pure fake-client tests.

Reference: [Apple cooperative activation](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation).

## Foreground follow-up and playback feedback (2026-09-05)

The first AX foreground guard was tested with an isolated one-mouse-move macro
bound to Chrome. It rejected preparation, proving no input was sent, but did
**not** establish successful foreground activation. The follow-up activates and
unhides the application before attempting AX enumeration and retries the window
lookup rather than failing before the activation request. Live acceptance is
still required; unit success must not be treated as foreground evidence.

Accepted app/core callback contract: async and synchronous playback clients append
an optional, default-noop `stepStarted(PlaybackActionFeedback)` callback before
execution. Feedback contains step/loop counts, kind, and safe shortcut/control-key
labels; it omits printable typing, Unicode, anchors, coordinates and titles.
Player coalesces updates into one pending main-queue snapshot. The app-owned
nonactivating HUD observes this separate state and hides at termination. It never
becomes key/main and ignores mouse events. Direct fake-engine tests cover callback
ordering, conflict rejection and input privacy.

Before an action-only recording is started for the first time, the GUI now asks
whether to preserve local video and keyframes or intentionally record actions
only. The choice is remembered; Settings continues to control later recordings.
The existing visual preflight and capture pipeline remain authoritative. Missing
images from older action-only recordings cannot be reconstructed. The standalone
library also hides before capture, with a run-loop handoff even at zero countdown,
so it does not become the captured target itself. AI receives visual files only
when the user explicitly includes them in an export.

Verification before the final recording handoff adjustment: 849 tests in 108
suites passed. Release compilation and live foreground verification pending.

Live follow-up isolated a more specific compatibility issue: Chrome was active
but AX returned no match throughout 20 checks. Window-server observations showed
two Chrome windows, with the recorded 2056×1290 rectangle first. Foreground
preparation now falls back to a pure window-server-order check when AX has no
usable target: the app must be active, exactly one of its visible windows must
match the resolved rectangle, and that exact window ID must be the first normal
window globally. A different Chrome window, another app in front, and coincident
ambiguous windows are rejected. Direct tests: `PlaybackForegroundWindowVerificationTests`.
This does not bypass failed AX focus verification when an AX target exists.

Visual-capture live check: choosing video/keyframes produced a finalized 18.84s
MOV (2,450,354 bytes), two PNG keyframes and their manifest/index locally. The
AX-only start/stop interactions produced no physical action events, so this check
validates capture artifacts, not a complete event-aligned AI reconstruction.
Temporary capture artifacts are removed after inspection. Visual capture remains
enabled as requested. Phase logs contain no titles, typed text or coordinates.

Review correction: the fallback must not validate a candidate against a rectangle
returned by the permissive runtime matcher. It now uses the original recorded
window ID (when present), otherwise the original recorded rectangle. A missing
recorded ID is rejected; legacy recordings without IDs must have a unique exact
rectangle match. A moved legacy window with unusable AX may require restoring
its recorded geometry. This conservative limitation prevents an unrelated
remaining window from being accepted merely because it is the only candidate.

Root cause found by cross-checking process IDs: the machine runs two
`com.google.Chrome` application processes. The original `.first` selected the
process without the recorded windows; both visible Chrome windows belonged to
the other process. Bundle-level frontmost checks concealed this mismatch.
Preparation now resolves the owning process from recorded window ID/geometry
before activation when several processes share a bundle identifier. Ambiguous
ownership is rejected. A direct test reproduces first-process/wrong-owner,
missing-owner and ambiguous-owner cases.

Successful live playback after owner selection: the isolated two-mouse-move,
5-second Chrome macro logged target ready → engine started → engine completed →
success evidence saved. Its persisted play count became 1 and a run report was
created. No clicks or text input were used. Full tests: 852/109 suites; subsequent
AX binding hardening targeted checks: 43/4 suites. AX matching now requires
recorded geometry or an exact nonempty legacy title; a recorded ID is resolved
before raising and rechecked against the window server after AX focus. Process
selection includes off-screen windows so hidden owners can be unhidden.

HUD live verification found that NSApp.hide also suppresses newly ordered panels.
The shared HUD presentation helper explicitly orders the app's existing windows
out before unhideWithoutActivation, then shows only the nonactivating HUD. Both
recording and playback use it. This preserves target activation while making
feedback visible. Swift 6 build passed after this adjustment; panel visibility
and target focus are checked on the installed build before delivery.

## Window identity, manual visibility, and operation feedback follow-up

A later user report reproduced a bound Chrome failure with production-shaped data. The saved
macro had no `recordedWindowId`, two processes shared `com.google.Chrome`, and the selected
process currently exposed two AX windows with the same 2056×1290 geometry while both titles
had changed since recording. Refusing to guess between those windows is intentional: no input
is posted when the target is ambiguous. The failure copy now points users to **Bind Active
Window** when the intended window has changed.

New captures and manual rebinding now resolve the focused surface to the frontmost matching
layer-zero window-server ID and persist it in `PlaybackSurface.recordedWindowId`. Window-server
parsing is shared by recording and playback through `WindowServerObservationAdapter`. During
playback a still-live recorded ID remains strong identity. If multiple AX windows share the
same geometry, foreground preparation cycles eligible AX candidates and verifies the exact
recorded ID at the window-server Seam before any macro input may start. If a recorded ID is no
longer present, Core falls back to the recorded geometry; ambiguity still fails closed.

User-initiated playback now owns one `ManualPlaybackVisibilitySession` across the entire chain.
The original SparkleRecorder visibility/focus snapshot is restored on normal completion,
preparation failure, playback failure, chain-cycle termination, chain-load failure, and Stop.
Scheduled/background automation keeps its separate visibility semantics and is not forced to
open the SparkleRecorder window after every background run.

The old untyped `statusMessage` surface was replaced by `AppStatusFeedback` with semantic
info/success/warning/error/progress tones, tone-owned dismissal policy, multiline presentation,
and explicit dismissal. The same bottom-center presentation Seam is mounted on the main
window/menu popover, Settings, and Editor. Progress feedback persists until replaced, and
errors remain visible until the user dismisses them or a later operation replaces them; long
messages are no longer truncated into a single-line black capsule. Library mutations now route
through `MenuBarController` instead of SwiftUI writing `MacroLibrary` directly, so rename,
duplicate, delete, favorite/tag, shortcut, repeat/speed, notes, chain and reorder operations all
share the same interaction lock and feedback path. Duplicate waits for the full repository event
snapshot before reporting success, and chain mutation reports self/cycle/missing-target rejection
instead of silently ignoring it. Direct regression coverage includes status lifecycle, Library
mutation ordering/results, manual visibility ownership, stale-window-ID fallback, frontmost
capture identity, and existing target-preparation fail-closed behavior. Live replay of an
arbitrary user macro remains outside automated verification.

## Text-locator window identity correction (2026-09-06)

A reconstruction trial exposed a separate locator seam after the candidate correctly used an
exact `New chat` text anchor. `WindowTracker` could resolve the intended Chrome window while
`ScreenCaptureService` independently required the *recorded title* to still match. Browser titles
are mutable, so OCR capture could select another same-bundle window with the stale title or fail
entirely; `LivePlaybackRunStepClient` would then use the coordinate fallback. The candidate still
looked like an exact text click even though the posted point came from the old recorded coordinate.

Locator capture now receives the surface's recorded WindowServer ID and the already-resolved
current window frame. A still-live recorded ID is strongest identity; if that ID is gone, the
resolved current frame is preferred before historical title matching. `WindowTracker` likewise
weights a still-live recorded window ID above title/size heuristics. Pure matcher regressions cover
title drift with a live recorded ID, stale ID plus current-frame recovery, stale old-title windows,
and legacy title-only capture. Locator-cache and playback-engine regressions remain green. No
arbitrary click macro is replayed as automated verification.

### Unified text-target resolution follow-up

The same audit found that runtime semantics were already closer than the old naming suggested:
`waitForText` and `verifyText` called `LocatorEngine` for OCR, so they inherited the same stable
window capture fix. The remaining architecture problem was that presence checks were expressed
through a point-returning locator Interface, while normalized anchor geometry was independently
reimplemented by playback fallback and Macro Editor preview code.

`PlaybackTextTargetResolver` now owns the live meaning of a `TextAnchor`: explicit Playback Surface
selection, stable WindowServer identity, current content-frame geometry, OCR capture/cropping and
conversion of Vision output into Core candidates. `TextAnchorMatchRanking` owns exact/contains,
fuzzy tolerance, observed-position scoring and occurrence selection in pure Core. `LocatorEngine`
now has one narrow job: bounded polling for a text-backed mouse target; `LivePlaybackTextObservation`
consumes the same resolver as a presence observation. The old unused locator strategy array and
coordinate branch were removed.

`TextAnchorGeometryProjection` is the shared Core Module for content-normalized observed/search/
fallback geometry. `PlaybackLocatorFallback` owns coordinate fallback for both async and synchronous
live playback, and Macro Editor preview uses the same geometry projection. A content-normalized
`TextAnchor` now requires an explicit `surfaceId` at candidate validation and fails closed at runtime,
so a multi-window macro never guesses an arbitrary surface. Legacy surface fallback remains only for
legacy/non-content-relative input and is deterministic by surface ID.

The same cleanup moved macOS Accessibility/screen content-frame resolution out of
`SparkleRecorderCore`. Core no longer imports AppKit/Cocoa for coordinate resolution;
`WindowContentFrameResolver` is the App-edge Adapter that supplies live content geometry to
`PlaybackContext`. `PointResolver` uses only context and persisted geometry, including recorded
content insets for compatibility when live content metadata is unavailable. This also fixes
normalized-only AI search regions being executable but previously missing from Editor preview when
no absolute `searchRegion` was stored.

### Text-picker display-fallback geometry correction

A later trial exposed a different source of vertical drift in locally edited Candidates. When
`TextPickerOverlay` could not capture the intended window, it fell back to a full-display screenshot
but still wrote `observedContentNormalizedFrame`, `searchContentNormalizedRegion`, and
`coordinateFallbackContentNormalized`. Those values were normalized against the display frame even
though playback interprets them relative to the event's Playback Surface content frame. On the
reproducing Chrome macro, an absolute fallback near y=203 became normalized y≈0.1528 against the
1329-point display; replaying that value against the 1290-point window beginning at y=39 produced a
point near y=236, matching the reported downward offset.

Display fallback now preserves only absolute Text Anchor geometry. Content-normalized fields are
written only when the picker actually has a window/content normalization frame. Window capture from
the picker also supplies the recorded WindowServer ID and resolved current frame, so browser title
drift no longer unnecessarily forces display fallback. `MacroCandidateValidator` additionally
rejects simultaneous absolute/content-normalized Text Anchor geometry when both forms disagree with
the Candidate's recorded content frame beyond a small pixel tolerance. Direct regressions cover the
real failing geometry and verify that ordinary full-window normalized Chrome coordinates still
round-trip without vertical drift.

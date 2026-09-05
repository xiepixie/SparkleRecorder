# Playback and presentation reliability audit

Updated: 2026-09-05
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

# Scheduled Run Hardening

Updated: 2026-07-18

## Current Problems

- Quick Schedule preview countdown is root view state. Every tick invalidates the whole form and recomputes schedule occurrences, validation, and target labels.
- Library refresh stores a full macro-to-schedule dictionary in the root view. Any refresh rebuilds all card and context-menu subtrees.
- Macro cards animate material, gradient, shadow, focus, selection, hover, and drag state across the complete card hierarchy. Opening a context menu changes focus/hover and can trigger expensive rendering work.
- Target cleanup stores only bundle identifiers, sends one asynchronous `terminate()` request, ignores its result, and marks the run complete without confirming process exit.

## Accepted Lifecycle Contract

1. Preparation records the exact process identifier for each target application launched by this run.
2. Applications already running before preparation are never cleanup candidates.
3. Cleanup modes remain user-controlled:
   - Keep open.
   - Close normally and wait for a configurable grace period.
   - Close normally, then force quit the exact run-launched process if the grace period expires.
4. New Quick Schedule tasks default to the reliable third mode with a five-second grace period.
5. Evidence capture completes before cleanup begins. A run is not reported terminal until cleanup has finished or exhausted its configured policy.
6. Cleanup logs request acceptance, graceful exit, force-quit fallback, and unresolved processes without exposing user content.

## Performance Contract

- Countdown ticks invalidate only the preview control, not the complete schedule form.
- Schedule preview and validation are derived only when draft values change.
- Periodic runtime refresh publishes only changed summaries.
- Card hover/focus changes animate lightweight strokes or opacity only; material, menu content, and full layout do not receive implicit animations.
- The right-click menu contains frequent actions only and does not construct library-wide speed, color, or chain customization lists. Those complete controls remain in the card's ellipsis menu.
- Library/Automation workspace changes do not apply implicit animation to the root content tree. Native windows and sheets keep their system presentation animation; run filters animate only their count and selection indicators.
- Run history polls silently after its initial load. An unchanged projection does not publish a new generated timestamp or loading state, and dismissing the sheet cancels polling.

## Tests

- Exact PID selection and pre-existing application exclusion.
- Graceful termination success.
- Grace timeout without force quit.
- Grace timeout followed by force quit.
- Quick Schedule persistence/restoration of cleanup timeout and force fallback.
- Countdown state machine uses an injected sleep/clock and does not wait on wall-clock time.
- Existing reducer/effect-runner handoff tests cover the new cleanup configuration.

## Acceptance

- [x] Quick Schedule countdown state is isolated to the preview control; the form derives occurrences and validation only when its draft changes.
- [x] Right-clicking cards does not animate the full card and does not construct the advanced customization submenus.
- [x] Right-click and scheduled-run strings have English and Simplified Chinese catalog coverage; Chinese scheduled-run terminology is consistent.
- [x] Automation workspace and run-history open/close paths avoid full-tree custom animation.
- [x] A run-launched application is addressed by exact PID, waits for the selected grace period, and uses force quit only when enabled.
- [x] A pre-existing application is excluded from the cleanup session.
- [x] Targeted tests and Swift 6 build pass.
- [x] Full Swift Testing suite (660 tests), Swift 6 debug build, release install, string-catalog validation, and whitespace checks pass.

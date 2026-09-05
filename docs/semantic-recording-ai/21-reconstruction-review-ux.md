# Reconstruction Review: user flow and verification

Updated: 2026-09-04
Status: implemented; installed-app live acceptance pending permissions.

## Enter after recording

The saved macro stays playable. The library provides **Refine** for its selected macro, plus reconstruction actions on cards and compact rows. Recording is never silently replaced by a candidate. Existing visual-evidence recording settings remain the capture opt-in. A recording without video explains how to enable it for the next recording.

## Prepare, compare, test

1. Export a local AI package. Visual bytes require the explicit inclusion checkbox; suppressed video is withheld unless its clock/redaction evidence can be trusted. Export errors are visible and package copying does not block the main thread. The app does not invoke an external model or upload files.
2. Import a complete candidate. Validation either retains a separate immutable version or explains why it was rejected. Review shows current/candidate action counts, readable action labels, coverage by step, and the author's uncertainty. Selecting a text target lets the user correct its label; saving creates a new candidate requiring another test.
3. Test once. The same Player runs the complete candidate events once at the saved speed, without chained macros. This avoids an infinite-source macro making trial completion impossible. The receipt binds both accepted executable content and the single-iteration execution snapshot/policy. Accepting preserves saved repeat and chain settings.
4. Check the result in the target application, then accept the tested version. Unresolved actions also need acknowledgement. Acceptance is a recoverable atomic macro revision change; it does not reverse external application effects. Restore original recovers the macro events/settings.

## State and interruption rules

Import/correction invalidates the visible test result. Starting a retest invalidates its old success receipt. Failure or cancellation cannot enable acceptance, including cancellation while preparing the target app. Other playback clients share a Player reservation until preparation/playback/cleanup has finished. A stale cancel cannot stop a later run. Recording entry is guarded while a candidate test is preparing or executing.

Publishing a version while recording/playing is disallowed in the UI boundary. Errors after atomic publication refresh the complete stored snapshot. A source edit after export/import fails the stale-revision gate rather than attaching a candidate to a changed macro.

## Video and layout

Two columns separate current actions and the candidate. The original evidence video is local, with explicit unavailable alignment when provenance is absent or source content changed. Action selection seeks only validated clock ranges. Playback highlights a corresponding action; measured endpoint markers appear only near their real mapped times. No interpolated cursor path or guessed clock is presented.

The three-stage header, human step coverage, descriptive empty state, visible test result, cancellation text and persistent restore action guide the next action. Domain strings live in EditorUX.xcstrings (English/Simplified Chinese). Internal revision IDs stay out of routine coverage rows.

## Evidence and remaining gates

- Full tests: 829 tests, 102 suites passed; Swift 6 and Release builds passed. The compiled CLI inspect entry returned valid candidate IDs for a local fixture.
- Model tests cover import→test→accept→restore, failure/retest, and cancellation during preparation even when an adapter returns success afterward.
- Repository tests cover single-iteration testing of continuous/chained source settings, capability/policy-bound receipts, stale revisions and atomic publication faults.
- Shared-player tests cover competing clients, startup cancellation and cleanup reservation retention, without live input.
- Optional `SPARKLE_RECONSTRUCTION_SNAPSHOT_DIR=/tmp/sparkle-reconstruction-visual swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter renderReviewFixturesWhenRequested` renders only local fixture data into an offscreen AppKit host. This is layout evidence, not live capture/playback proof.
- Local `semantic-recording debug-smoke --preflight-only --json` is blocked by missing Input Monitoring permission. Real timed recording, window movement/scaling, long-gesture playback, external model output and installed-app click-through remain product acceptance work; no such gate is closed by the fixture tests.

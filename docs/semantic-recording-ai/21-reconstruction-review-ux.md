# Reconstruction Review: user flow and verification

Updated: 2026-09-06
Status: implemented; installed-app live acceptance pending permissions.

## Enter after recording

The saved macro stays playable. The library provides **Refine** for its selected macro, plus reconstruction actions on cards and compact rows. Recording is never silently replaced by a candidate. Existing visual-evidence recording settings remain the capture opt-in. A recording without video explains how to enable it for the next recording.

## Prepare, compare, test

1. Export a local AI package. Visual bytes require the explicit inclusion checkbox; suppressed video is withheld unless its clock/redaction evidence can be trusted. Export errors are visible and package copying does not block the main thread. The app does not invoke an external model or upload files.
2. Import a complete **Candidate**. Validation either retains a separate immutable version or explains why it was rejected. Review shows current/candidate action counts, readable action labels, coverage by step, and the author's uncertainty. The Candidate can also be opened in Macro Editor as a separate **Candidate Draft**; this editor uses its own event buffer and never autosaves into the accepted Macro.
3. Adjust the Candidate Draft when needed. Action timing, coordinates, text anchors, target surface, enabled state, grouping, and other candidate-owned event content remain editable. Editor previews are adjustment tools only; they do not create an acceptance receipt. Library-owned operations such as exporting the accepted Macro or creating a Repeat-Until behavior Macro are not exposed from Candidate Draft mode. Saving a changed draft creates a new immutable Candidate. Coverage mappings that still identify the same candidate actions are preserved; structurally invalidated mappings become unresolved rather than being guessed.
4. Test once. The same Player runs the selected Candidate once at the saved speed, without chained macros. This avoids an infinite-source macro making trial completion impossible. The receipt binds the exact Candidate digest and the single-iteration execution snapshot/policy. A successful test is shown explicitly as **Test passed**, and that exact version can be accepted directly. If the user opens the tested version in the editor but makes no changes, its Candidate identity and test eligibility are preserved. Any saved edit creates a new Candidate and therefore requires a new test.
5. Check the result in the target application, then choose **Accept this version**. If acceptance is blocked, Review reports the real remaining gate: stale source, missing successful test, unresolved-action acknowledgement, or active recording/playback. Acceptance preserves saved repeat and chain settings and performs a recoverable atomic Macro revision change; it does not reverse external application effects. Restore original recovers the Macro events/settings.

## State and interruption rules

Importing a different Candidate or saving a changed Candidate Draft invalidates the visible test result for the new version. Returning from an unchanged Candidate Draft does not manufacture a replacement Candidate and therefore preserves the exact version's existing test eligibility. Starting a retest invalidates its old success receipt. Failure or cancellation cannot enable acceptance, including cancellation while preparing the target app. Other playback clients share a Player reservation until preparation/playback/cleanup has finished. A stale cancel cannot stop a later run. Recording entry is guarded while a candidate test is preparing or executing.

Publishing a version while recording/playing is disallowed in the UI boundary. Errors after atomic publication refresh the complete stored snapshot. A source edit after export/import fails the stale-revision gate rather than attaching a candidate to a changed macro.

## Video and layout

Two columns separate current actions and the candidate. The original evidence video is local. Video alignment is owned by a source-revision lineage rather than by the currently accepted event array: exact source actions use verified recording provenance directly, while edited Candidate actions may inherit a video range only through explicit Candidate coverage that can be composed back to that recorded source. Added, unresolved, removed, cross-segment, or otherwise unprovable mappings stay unaligned individually instead of disabling the entire movie. Action selection seeks only validated ranges. Playback highlights the currently mapped action; measured endpoint markers appear only near mapped source endpoints. No interpolated cursor path, guessed clock, or timestamp-only fallback is presented.

The implementation boundary for this work is a pure Core lineage/alignment projector plus App-edge loading of retained source revisions. Review must not scan arbitrary Library files or infer lineage from action text. Candidate coverage and immutable retained source revisions are the only authoring provenance used for partial alignment.

The staged header, human step coverage, descriptive empty state, explicit **Edit candidate / Edit tested version**, visible **Test passed** state, truthful acceptance blocker, cancellation text and persistent restore action guide the next action. Domain strings live in EditorUX.xcstrings (English/Simplified Chinese). Internal revision IDs stay out of routine coverage rows.

## Evidence and remaining gates

- Full tests: 829 tests, 102 suites passed; Swift 6 and Release builds passed. The compiled CLI inspect entry returned valid candidate IDs for a local fixture.
- Model tests cover import→test→accept→restore, failure/retest, and cancellation during preparation even when an adapter returns success afterward.
- Repository tests cover single-iteration testing of continuous/chained source settings, capability/policy-bound receipts, stale revisions and atomic publication faults.
- Shared-player tests cover competing clients, startup cancellation and cleanup reservation retention, without live input.
- Optional `SPARKLE_RECONSTRUCTION_SNAPSHOT_DIR=/tmp/sparkle-reconstruction-visual swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter renderReviewFixturesWhenRequested` renders only local fixture data into an offscreen AppKit host. This is layout evidence, not live capture/playback proof.
- Local `semantic-recording debug-smoke --preflight-only --json` is blocked by missing Input Monitoring permission. Real timed recording, window movement/scaling, long-gesture playback, external model output and installed-app click-through remain product acceptance work; no such gate is closed by the fixture tests.

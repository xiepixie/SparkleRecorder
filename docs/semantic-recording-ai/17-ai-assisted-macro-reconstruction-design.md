# AI-Assisted Macro Reconstruction From Recorded Video

Updated: 2026-09-04

Status: Accepted design; product implementation and automated verification complete; live acceptance open

Owners: Recording/Video Alignment, Macro Core, AI Collaboration, Macro Review

Implementation ledger: [19-reconstruction-product-implementation-plan.md](19-reconstruction-product-implementation-plan.md) records current capture provenance, candidate validation, revision repository, playback observation, package/CLI and Review work plus direct test mappings. [18-reconstruction-foundation-implementation-plan.md](18-reconstruction-foundation-implementation-plan.md) remains the prior pure-foundation evidence. The current product slice passes 964 Swift Testing tests across 134 suites and the Swift 6 build. Live-product acceptance remains open because installed-app permission and representative live evidence still require explicit product verification. Review user flows are documented in [21-reconstruction-review-ux.md](21-reconstruction-review-ux.md).

## 1. Decision Summary

SparkleRecorder will treat one user recording as two synchronized sources of truth:

- the cleaned playable macro records **what the user did**;
- the captured MP4 records **what the user saw and what changed**.

After recording, AI may inspect both sources and produce a complete replacement candidate for the macro file. AI is not limited to additive suggestions or small patches. It may remove noise, merge low-level events into semantic actions, simplify drag paths, replace fixed delays with state waits, replace coordinate clicks with stable locators, and add result verification.

The candidate remains separate from the accepted library version until it passes local structural validation and the user tests it. SparkleRecorder, not AI, continues to own playback, scheduling, permissions, persistence promotion, rollback, and run evidence.

This design optimizes for lower maintenance cost and higher script quality. It deliberately allows broad AI edits because the original recording is retained and the user validates the reconstructed macro by running it.

## 2. User Problem

The current recording path captures enough information to replay a demonstration, but the saved result remains sensitive to timing and UI movement:

- a click may still depend on a coordinate even when the visible target has stable text;
- a wait may be the recorded delay rather than a condition that describes readiness;
- a hand-drawn drag may contain dozens of jitter samples even when the intent was a straight drag;
- network or application latency can make a previously sufficient delay fail;
- users must manually understand OCR, locator, timeout, and condition editors to repair these issues.

The desired user flow is simpler:

1. Record the task normally.
2. Let SparkleRecorder retain the playable script and MP4.
3. Ask AI to reconstruct the user's intent from the synchronized evidence.
4. Read a short explanation of the reconstructed flow.
5. Test the optimized candidate.
6. Fix only the small number of uncertain labels or regions, then accept it.

The product should make a misidentified label cheap to correct. If AI calls a button “Start Game” instead of “Log In,” the user should edit one locator value rather than re-record the macro or rebuild its timing.

## 3. Current Repository Evidence

The existing code already provides much of the required foundation:

- `RecordedEvent.time` stores seconds since recording start.
- `RecordingEventPipeline` filters disabled mouse movement, ignores recorder hotkeys, samples drags, binds events to `surfaceId`, and stores global, window-local, window-normalized, content-local, and content-normalized coordinates.
- `EventGrouper` projects low-level events into click, double-click, drag, scroll, text input, shortcut, wait, and other action groups.
- `SavedMacro` stores the complete playable event stream and surface metadata.
- `MacroSemanticRecordingReference` links a saved macro to its semantic recording bundle.
- `RecordingTimelineEvent` stores `recordingTime`, `recordedEventIndex`, frame IDs, video segment IDs, and surface IDs.
- `RecordingFrameReference` stores `recordingTime`, `videoTime`, image size, window bounds, display scale, surface ID, and related event IDs.
- `RecordingVideoSegment` stores the MP4 artifact, recording range, capture target, codec, and frame size.

The missing product layer is not basic recording. It is a reliable clock mapping, a reconstructable operation overlay, and an AI-facing full-file rewrite contract.

### 3.1 Architecture review: implementation constraints

The following are current code observations, not completed reconstruction features:

| Boundary | Current evidence | Required response |
| --- | --- | --- |
| Recording origin | `RecordingTimeline.eventTime` uses the first input; `Recorder` starts live duration at session start. | Separate session time from trimmed playback time. |
| Recording end | `Recorder.stopRecording` passes the last event time to semantic finish. | Preserve the observation interval after the final input. |
| Frame timing | `SemanticRecordingCaptureSession.captureFrame` labels requested frames with event time and uses `videoTime = recordingTime`. | Store actual sample time; delayed screenshots are not before frames. |
| Input evidence | `RecordingEventPipeline` filters moves and samples drags; `RecordingSessionProcessor` now separates compact playable events from bounded privacy-safe mechanical evidence and persists playable-to-evidence provenance. | Extend the evidence policy to richer hover/drag intent only when direct reconstruction evidence justifies it; do not collapse the two tracks again. |
| Macro capabilities | `RecordedEvent.Kind` has text waits/verification; richer visual conditions are in `AutomationContract`. | Export an executable capability manifest, not the combined vocabulary of unrelated layers. |
| Observation outcome | Live playback text waits catch locator failures as not found. | Distinguish non-match from unavailable observation. |
| Persistence | `MacroRepository` saves metadata and events in separate atomic writes. | Add revision-level transactions. |

The current movie adapter writes H.264 in a `.mov` container. References to MP4 here mean the canonical video evidence; packages must declare the actual container/codec and must not simply rename MOV bytes as MP4.

## 4. Product Boundary

### 4.1 AI may do

AI may:

- read the complete candidate macro representation;
- inspect the complete local MP4 when the user starts optimization;
- inspect event-centered clips and extracted frames;
- replace the entire candidate event array and choose explicit existing Playback Surface references per event;
- remove unintentional mouse movement and redundant input pairs;
- merge low-level events into semantic actions;
- simplify drag trajectories;
- convert coordinate actions to text, image, region, pixel, or other supported locators;
- convert fixed delays to bounded state waits;
- add bounded state waits and completion checks using supported macro event fields;
- reorder or remove actions when the synchronized evidence supports the change;
- choose a best-effort interpretation and mark uncertain fields for lightweight correction.

### 4.2 AI may not do

AI may not:

- replace the accepted library version without a local promotion step;
- execute or schedule a candidate by itself;
- bypass decoding, schema, timeline, input-balance, artifact, or timeout validation;
- destroy the source recording or prior accepted macro revision;
- silently omit a meaningful source action without an explicit coverage disposition;
- expose suppressed video, text, or frame evidence outside the existing privacy policy.

### 4.3 Important distinction

“AI edits the whole file” means AI produces a complete candidate macro file. It does not mean AI writes directly into an in-use library asset with no recovery path. Full-file generation is the authoring contract; version promotion is an app-owned transaction.

## 5. End-to-End Architecture

```text
Ordinary recording
  -> cleaned RecordedEvent stream
  -> SavedMacro source revision
  -> synchronized MP4 + keyframes + observations
  -> deterministic action reconstruction
  -> AI receives full macro + MP4 + reconstruction metadata
  -> AI writes complete candidate macro
  -> local validation and source-action coverage audit
  -> natural-language review
  -> user tests candidate
  -> accept candidate or restore source revision
```

The deterministic reconstruction layer explains the files to AI; it does not constrain AI to patch operations. The output remains a full macro.

## 6. Frame-Accurate Clock Alignment

### 6.1 Problem with equality-based alignment

The current semantic capture contract often assigns the same numeric value to `recordingTime` and `videoTime`. That is sufficient for fixtures but not necessarily frame-accurate in a live recording:

- event capture and `SCRecordingOutput` start asynchronously;
- the first encoded video frame can arrive after event recording begins;
- a recording may contain multiple video segments;
- pause/resume or capture restart can introduce discontinuities;
- long recordings may accumulate measurable drift.

### 6.2 Shared mapping contract

Each video segment must store a clock mapping from recorder monotonic time to video presentation time:

```json
{
  "segmentID": "...",
  "videoStartedAtRecordingTime": 0.184,
  "firstVideoPTS": 1582.431,
  "anchors": [
    { "recordingTime": 0.184, "videoTime": 0.000 },
    { "recordingTime": 31.622, "videoTime": 31.437 }
  ]
}
```

The mapping resolves:

```text
(videoSegmentID, recordingTime) -> videoTime
(videoSegmentID, videoTime) -> recordingTime
```

The first accepted implementation may use offset mapping when two anchors prove that drift is negligible. It must use piecewise-linear interpolation when drift exceeds the accepted tolerance.

### 6.3 Alignment evidence

Alignment anchors should come from actual sample-buffer presentation timestamps associated with the same monotonic clock used by event capture. Keyframe capture may add verification anchors, but screenshot request time alone is not the video clock.

Acceptance target:

- typical event-to-frame error at or below one video frame;
- hard tolerance of 50 milliseconds for supported capture modes;
- explicit degraded status when the mapping cannot meet tolerance;
- no silent fallback to `videoTime == recordingTime` in a live AI optimization run.

### 6.4 Time domains and evidence coverage

The clock contract distinguishes:

- **Session time:** monotonic elapsed time from session start, including initial idle and final observation intervals.
- **Source playback time:** cleaned event time with an explicit mapping to session time and stable source event identity.
- **Video time:** segment-local presentation time mapped from actual samples.
- **Candidate playback time:** rewritten execution timing; candidate edits never overwrite source alignment.

Store the session origin, actual capture start/end, source event mapping, segment anchors, and observation coverage. Pause/resume and capture restarts create explicit discontinuities. Reject non-finite/non-monotonic anchors and ambiguous segments. Out-of-range queries return unavailable; never interpolate across an uncovered interval.

Stopping captures actual session stop time independently of the final input. Playback can trim idle time while evidence retains it. A final result frame must use its actual capture time, not the last event timestamp.

Store actual sample time separately from triggering event/request time. Prefer stream frames or indexed movie frames for before/after selection. A screenshot taken after a click cannot prove the pre-click state. Alignment quality includes local residual error, dropped frames, and timestamp uncertainty; two distant anchors alone do not prove accuracy throughout a segment.

## 7. Operation Reconstruction Layer

The operation reconstruction layer turns the cleaned macro and aligned video into a synchronized explanation that AI and users can inspect.

### 7.1 Reconstruction output

Each reconstructed action contains:

```json
{
  "actionID": "action-12",
  "kind": "drag",
  "sourceEventIndices": [42, 43, 44, 45],
  "recordingRange": [14.200, 14.830],
  "videoSegmentID": "...",
  "videoRange": [14.016, 14.646],
  "surfaceID": "game-window-1",
  "startPoint": { "x": 421, "y": 516 },
  "endPoint": { "x": 735, "y": 518 },
  "contentNormalizedStart": { "x": 0.32, "y": 0.58 },
  "contentNormalizedEnd": { "x": 0.71, "y": 0.58 },
  "maxDeviationFromLine": 4.8,
  "beforeFrameID": "...",
  "afterFrameID": "..."
}
```

The representation is derived from `SavedMacro`, `EventGrouper`, surface metadata, frame geometry, and the clock mapping. It is generated locally and is reproducible from the same source bundle.

### 7.2 Visual operation overlay

The review player overlays the reconstructed operation track on the MP4:

- cursor position interpolated from recorded samples;
- click pulse, button, click count, and action number;
- original and simplified drag trajectories;
- scroll direction and magnitude;
- redacted or safe keyboard input labels;
- action names and ordinary wait ranges;
- window/surface changes;
- before/after frame markers.

Selecting an action seeks the MP4 to its aligned time range. Selecting a point in the video highlights the nearest reconstructed action.

### 7.3 Coordinate-to-video mapping

An event point must be mapped through the capture geometry that existed at the event time:

```text
global/window/content coordinate
  -> event-time surface geometry
  -> captured window/display region
  -> video frame pixels
```

Current frame and surface fields are close to sufficient, but the implementation must preserve geometry history when a window moves or resizes. A single final `PlaybackSurface.recordedFrame` is not sufficient for reconstruction of a moving window. Geometry snapshots should be attached to alignment anchors, relevant timeline events, or the nearest frame reference.

### 7.4 Stable actions and evidence retention

Freeze reconstruction policy/version and derive stable action IDs from source revision and event identity. Editor grouping preferences and localized summaries must not change coverage identity. Derived waits carry source time ranges even without event indices.

The playable/evidence Seam is now implemented for bounded privacy-safe mechanical mouse and scroll samples: continuous scroll is compacted deterministically for playback while `input-evidence.jsonl` retains the denser source trajectory plus playable-to-evidence links. Richer hover intervals and drag-intent evidence remain an extension of this Interface rather than a reason to merge the tracks. Overlay points must still distinguish measured from interpolated evidence. Missing intermediate samples cannot establish a straight drag. Path-sensitive simplification considers pauses, direction changes, and speed as well as geometry.

Geometry history includes surface identity, window/content bounds, capture region, scale, and effective session time. Missing history produces degraded reconstruction, not reuse of the final window geometry.

## 8. AI Input Package

The AI optimization session receives one local package:

```text
ai-macro-reconstruction/
  harness.json               # small index, versions, file roles, staged reading plan
  authoring-contract.json    # complete executable vocabulary/enums/rules/policy
  source-context.json        # lightweight Macro/Surface overview; no raw events
  reconstruction.json        # primary action-level inventory and compact semantics
  candidate-template.json    # single raw-event baseline and output shape
  manifest.json              # evidence availability, warnings and artifact hashes
  alignment.json             # only when source-event identity is verified
  input-evidence.json        # when bounded mechanical evidence is available
  visual-inspection.json     # when aligned visual bytes are exported
  video/                     # explicit visual inclusion only
  frames/                    # explicit visual inclusion only
  candidate.json             # only external-author output
```

`harness.json` is the compact package entry point and version ledger; it tells the external author what to read and when rather than duplicating the full authoring rules. `authoring-contract.json` is the single machine-readable source for executable event codes/names, Reconstruction Action representations, string enums, numeric limits, faithful/robust policy and validator-facing rules. `source-context.json` is a versioned lightweight execution overview, not the complete Library `SavedMacro`; it exposes source identity, Playback Surfaces and protected playback facts while withholding raw events, Library personalization, notes, hotkeys, statistics, local evidence references and chained Macro identity. `candidate-template.json` is the single exported raw-event baseline. `reconstruction.json` is the default action-first working set and colocates each Reconstruction Action with its Playback Surface, geometry and compact pointer/keyboard/scroll/text semantics. Video and frames remain local evidence and are exported only when the user explicitly includes permitted visual evidence.

The AI adapter may extract event-centered clips to reduce model context, but the full MP4 remains available when the user authorizes optimization. The adapter must not claim that the model inspected the complete video when it only inspected selected frames or clips.

The machine-readable Harness must include:

- supported `SavedMacro` / candidate capability versions;
- every executable event code together with its enum name and meaning;
- every Reconstruction Action kind together with its executable candidate representation;
- supported locator/condition fields and all accepted string enum values;
- transformation and validator-facing invariants;
- a staged reading plan so action understanding precedes raw-event/media inspection;
- the output path for the complete candidate document;
- prohibited unsupported fields/capabilities and uncertainty/coverage requirements.

### 8.1 Executable capabilities and evidence access

Include an app-generated, versioned manifest of schema versions, event kinds, locator fields, condition semantics, timeout/polling limits, and artifact types. Validation uses the same definition and explicitly rejects unsupported fields instead of allowing decoding to silently discard them.

The first complete product slice supports text locators, bounded text waits, text verification, ordinary input cleanup, and conservative drag simplification. Text grouping may compile into existing balanced key events; it does not authorize an invented text-input event kind. Image, pixel, region-change, and window-ready conditions become available only after macro persistence and playback adapters are accepted and directly tested. Reuse existing visual evaluators through shared client contracts where appropriate.

Full-file macro candidate authoring and existing Workflow draft authoring have separate contracts. Writing a candidate does not authorize editing an accepted macro or an internal Workflow package. Existing metadata-only CLI commands remain metadata-only.

Materialization resolves permitted redacted artifacts and sanitized readable event fields. Complete source structure does not bypass suppression. Record evidence actually supplied/inspected separately from locally available evidence, including missing ranges.

## 9. Full-File Rewrite Contract

### 9.1 Output

AI writes a complete candidate authoring document with an entire event array. Source Revision Playback Surface bodies are not copied into new external candidate JSON; each event may choose an existing surface through `event.surfaceId`, while external authoring does not invent/remove/rewrite Playback Surface identity or geometry. Live window rebinding is an App-owned Candidate Editor operation. The output does not require a mandatory patch list.

The app should normalize volatile metadata after decoding:

- candidate ID and source revision identity are app-owned;
- creation and modification timestamps are app-owned;
- play counts and run statistics are preserved from the accepted macro;
- hotkey, chain, scheduling references, and semantic recording links are preserved unless the user explicitly changes them;
- event caches are recomputed from candidate events.

### 9.2 Candidate provenance

The app stores a separate reconstruction result beside the candidate:

```json
{
  "sourceMacroID": "...",
  "sourceRevision": 7,
  "recordingID": "...",
  "model": "...",
  "createdAt": "...",
  "summary": "...",
  "uncertainActions": ["action-8"],
  "coverage": []
}
```

This metadata explains the rewrite but does not require AI to express every file change as a patch.

### 9.3 Source-action coverage

Broad rewriting is allowed, but each meaningful reconstructed source action must have one disposition:

- preserved;
- merged into a candidate action;
- replaced by a locator-driven action;
- replaced by a state wait or verification;
- intentionally removed as recording noise;
- unresolved and requiring user attention.

Coverage is a quality audit, not an editing mechanism. The user does not need to review every mapping. The coverage gate blocks promotion for unexplained loss, nonexistent candidate targets, or unresolved actions without explicit user correction or acceptance. Structural and test gates apply independently. A disposition explains a transformation but does not prove equivalence. Meaningful deletions, reorderings, and changed input values appear in the default summary; routine movement cleanup can be collapsed. Noise-removal claims retain source ranges and reasons.

## 10. Initial Transformation Vocabulary

### 10.1 Mouse move plus click

Ordinary cursor travel preceding a click may collapse into one click action. Preserve explicit movement only when video evidence shows hover-dependent UI, drawing, selection, or another intermediate effect.

### 10.2 Click locator reconstruction

For each click, AI may inspect:

- the click point mapped into the before frame;
- OCR text intersecting or surrounding the point;
- visible button or icon boundaries;
- the after frame and resulting state change;
- the active surface and content-normalized coordinate.

The candidate may use a text or visual locator and retain the original content-normalized point as fallback.

### 10.3 Drag simplification

A sampled drag may become a straight line when:

- the button-down and button-up pair is balanced;
- start and end points remain equivalent;
- maximum perpendicular deviation is below a scale-aware threshold;
- there is no material direction reversal or intentional pause;
- video shows no required intermediate interaction.

A non-linear drag may be simplified to a small set of significant corners. Drawing, freehand, game aiming, path-sensitive controls, and hover-sensitive drags must preserve sufficient trajectory detail.

### 10.4 Text input

Balanced key events may collapse into a semantic text-input action when the existing readable text is safe and the video/context supports the field. Shortcuts and navigation keys remain distinct.

### 10.5 Fixed delay to state wait

AI may replace a recorded time gap with a bounded condition when the video demonstrates a meaningful transition:

- text appears or disappears;
- an image or icon appears or disappears;
- a region changes from its recorded baseline;
- a pixel/color state changes;
- the target window appears or becomes ready.

Every generated wait has a finite timeout and polling policy. The original observed duration may inform the timeout but must not be treated as the readiness condition.

### 10.6 Result verification

AI may add a bounded verification after a high-value action when the MP4 shows an observable result. Verification should describe the resulting state rather than duplicate the click target.

## 11. Candidate Validation

Local validation protects file integrity without preventing large semantic edits.

Required checks:

- candidate decodes as a supported `SavedMacro` version;
- event times are finite, non-negative, and non-decreasing after normalization;
- mouse and keyboard state transitions are balanced where required;
- drag actions have valid start, path, and end semantics;
- surfaces referenced by events exist or have an accepted fallback;
- locator fields and visual artifact references are valid;
- waits and verifications have finite timeouts;
- candidate duration and event count are internally consistent;
- protected macro metadata is preserved by app-owned normalization;
- meaningful source actions pass the coverage audit;
- no suppressed evidence is reintroduced into readable fields.

Validation does not reject a candidate solely because it differs substantially from the source.

## 12. Review And Test Experience

The default review should minimize user judgment:

```text
AI reconstructed 14 recorded actions into 9 stable actions.
• Replaced 3 coordinate clicks with text locators.
• Replaced 2 fixed waits with state waits.
• Simplified 1 drag to a straight path.
• Removed 6 cursor-movement samples.
• One target label may need confirmation.

[Test Optimized Version]
```

The detailed review has two synchronized panes:

- MP4 with operation overlay;
- reconstructed natural-language action list.

If a label is wrong, the user edits that action's locator text. If a visual target is wrong, the user selects the correct region from the recorded frame. The user should not need to understand the complete event file.

Testing runs the candidate through the normal playback engine and produces ordinary run evidence. It does not imply success merely because playback did not crash; observable candidate verifications and user confirmation determine acceptance.

### 12.1 Recording and correction flow

Show capture readiness before recording without requiring locator/timeout configuration. Input capture stays independent of OCR/model latency. Stop saves the playable macro and shows asynchronous evidence-finalization status. Missing video limits optimization, not recovery of recorded input.

During a candidate test, display the current action and wait condition. On failure, show the action, recorded reference, runtime sample or observation-unavailable reason, and a focused text/region correction. Editing creates a new candidate identity and invalidates prior test eligibility.

### 12.2 Execution semantics

- Observations distinguish **matched**, **not matched**, and **unavailable** with a reason. Capture, permission, missing-window, and detector errors do not establish absence. Retry unavailable observations only within the deadline; they never satisfy disappearance waits.
- Waits require valid observations under an explicit bounded polling/stability policy. A transient match must not be described as sustained readiness. Cancellation and timeout are distinct from success; polling responds to cancellation.
- Replacing a gap also rewrites candidate event deltas. The next action follows condition completion plus an explicit settling interval, without replaying the removed delay. Playback speed must not unintentionally scale observation deadlines.
- Text presence does not prove that a control is enabled or the task completed. Current single-observation text verification must not be advertised as bounded stability verification without adapter work.
- Disambiguate targets by supported surface/region/context constraints. Coordinate fallback is explicit, requires valid geometry/context, and is recorded as degraded execution.
- Scope locator reuse to a gesture/action with valid observation and geometry context. Preserve down/up consistency but invalidate across navigation, scrolling, surface changes, and relevant layout changes. Nearby source timestamps alone are insufficient.
- Retry observation/localization within a deadline. Do not automatically repeat posted input whose outcome is unknown; repetition requires an accepted action-specific recovery policy or user choice.

### 12.3 Test identity and result meaning

Bind test evidence to source revision, normalized candidate digest, referenced artifact digests, capability version, and execution-affecting settings. Changes require a new test. Display execution finished, observable checks passed, and user accepted separately. A candidate without a result check may be accepted after a completed test and explicit user confirmation, but remains labeled as lacking automated result verification.

Resume at a failed action only after its preconditions are verified; otherwise restart from an established checkpoint. Restoring a macro revision does not undo operations already performed in another application.

## 13. Versioning, Promotion, And Recovery

The source revision remains immutable during optimization.

```text
accepted revision N
  -> AI candidate N+1
  -> local validation
  -> test run
  -> user accepts
  -> atomic promotion to accepted revision N+1
```

If generation, decoding, validation, testing, or promotion fails:

- the accepted revision remains unchanged;
- the candidate and diagnostics may be retained for inspection;
- the user can retry generation or edit the candidate;
- rollback does not depend on reconstructing the source from AI output.

Promotion must atomically update the macro event file and metadata manifest or use an equivalent repository transaction. Existing schedules and workflow references continue to target the same macro identity.

### 13.1 Revision transaction and concurrent runs

Stage immutable normalized events, metadata, and revision-owned artifacts, then atomically publish an accepted-revision pointer or an equivalent crash-recoverable transaction. Schema version and content revision are separate identities.

Compare the accepted revision with the candidate base at promotion. Concurrent edits produce a stale-candidate conflict, not overwrite. Preserve current app-owned statistics/protected metadata at commit time. Running tasks pin their selected revision; later runs resolve the newly accepted revision. Retention cannot remove artifacts still required by retained revisions or active runs.

A crash before publication leaves the old revision authoritative. After publication, the new revision must be complete and loadable. Failure-injection tests cover both boundaries, stale-source rejection, and preservation of macro identity.

## 14. Privacy And Model Access

The existing semantic recording suppression and redaction rules remain authoritative.

- MP4 and extracted visual evidence remain local by default.
- The user explicitly starts AI optimization for a recording.
- The app clearly states whether full video, clips, frames, or metadata will be provided to the selected model.
- Password, Secure Input, excluded targets, private regions, and redacted intervals remain unavailable to AI.
- If suppression removes evidence needed to understand an action, AI may still produce a best-effort candidate but must mark that action uncertain.
- The source macro remains playable even when visual evidence has expired, subject to existing sanitization policy.

## 15. Ownership And Layer Boundaries

### Core

Owns pure value types and algorithms for:

- clock mappings and alignment validation;
- action reconstruction;
- geometry projection;
- trajectory simplification metrics;
- source-action coverage;
- candidate normalization plans;
- structural validation;
- deterministic fixtures and tests.

Core must not import ScreenCaptureKit, AVFoundation, Vision, SwiftUI, AppKit, or perform file mutation.

### App adapters

Own:

- actual sample-buffer timestamp capture;
- MP4 and frame access;
- geometry snapshots;
- OCR/visual indexing;
- AI package materialization;
- model invocation adapter;
- candidate file decoding and repository transaction;
- test-run launch and evidence collection.

### UI

Owns projections and intents for:

- synchronized video and operation overlay;
- natural-language reconstruction summary;
- uncertain action correction;
- test, accept, retry, and restore actions.

SwiftUI views do not call the recorder, model adapter, repository, or player directly.

## 16. Testing Strategy

### Pure tests

- event time maps to expected video time for offset, multi-segment, and drift cases;
- alignment outside tolerance becomes degraded rather than silently accepted;
- action reconstruction groups click, text, wait, scroll, and drag deterministically;
- window movement and resize use event-time geometry;
- near-linear drag simplifies to a line;
- path-sensitive drag retains significant corners;
- hover-dependent movement remains explicit;
- coverage accepts preserved/merged/replaced/noise dispositions and rejects unexplained loss;
- candidate normalization preserves protected metadata;
- malformed candidate files fail without changing the accepted revision.

### Fake-adapter tests

- synthetic MP4 PTS and event clocks produce frame-accurate mapping;
- AI package contains the complete macro, MP4 reference, reconstruction, alignment, and permitted evidence;
- full candidate rewrite decodes and validates;
- failed generation, validation, or test leaves the source revision unchanged;
- accepted candidate promotion preserves macro identity and external references.

### Product evidence

- installed App records a live macro with MP4 and alignment anchors;
- operation overlay visually follows cursor, click, and drag within tolerance;
- AI converts at least one coordinate click to a locator;
- AI converts at least one fixed delay to a state wait;
- AI simplifies one jittered drag without changing observed outcome;
- a deliberately incorrect label can be repaired by editing only that action;
- failed candidate test restores or retains the source revision;
- successful candidate test and user acceptance promote the candidate atomically.

Tests must not post real input or depend on wall-clock time. Live product evidence is a separately authorized acceptance activity.

### Architecture-review regression matrix

| Scenario | Required result |
| --- | --- |
| Idle before first input and after final click | Real session alignment and final result evidence survive playback trimming. |
| Fast clicks with slow screenshot/OCR | No post-click frame is labeled as pre-click evidence. |
| Window move/resize or capture restart | Correct historical geometry/segment, or explicit unavailable coverage. |
| Hover menu or path-sensitive drag | Required intermediate behavior survives; unknown paths are not simplified. |
| Variable loading time | State wait adapts within bounds; replaced delay is not paid again. |
| Capture error during disappearance wait | Unavailable/timeout/failure, never false disappearance success. |
| Duplicate labels or scrolling | Ambiguity is explicit; stale coordinates are not reused across actions. |
| Unsupported field or dangling coverage target | Validation fails before execution. |
| Candidate changes after a test | Fresh test evidence is required. |
| Concurrent edit or interrupted promotion | Accepted revision remains consistent; stale overwrite is rejected. |

Pure/fake tests establish semantics; authorized installed-app evidence proves alignment, moved-window execution, variable latency, cancellation, one-action correction, and recovery. Fixture tests do not close live gates.

## 17. Delivery Slices

### Slice 1: Alignment and reconstruction truth

- freeze session/source/candidate/video time mapping, actual frame time, and geometry history contracts;
- add deterministic operation reconstruction;
- prove frame-accurate event/video mapping with fixtures;
- render a local operation overlay without AI.

### Slice 2: AI package and full-file candidate

- materialize complete macro, MP4, reconstruction, alignment, and evidence package;
- define full candidate output, executable capability manifest, and app-owned metadata normalization;
- decode and validate complete AI rewrites;
- implement source-action coverage audit.

### Slice 3: Test and promotion

- add candidate revision storage;
- run candidate through existing playback/evidence boundaries;
- bind tests to candidate/artifact digests; add stale-source-safe atomic accept and restore behavior;
- preserve schedules and workflow references.

### Slice 4: Product optimization loop

- add synchronized video/action review;
- add natural-language summary and uncertain action correction;
- first prove text locator, text wait, and conservative drag simplification with live evidence; enable broader visual conditions only after macro capability contracts are implemented;
- tune prompts and transformation policy from accepted/rejected candidate outcomes.

### Delivery ownership and verification

| Slice | Requesting / implementing boundaries | Exit evidence |
| --- | --- | --- |
| 1 | S1 Core defines timing/action/geometry values; S2 Capture provides actual timestamps and evidence; S3 projects the overlay. | Pure mapping/reconstruction tests, fake timestamp adapters, authorized aligned overlay evidence. |
| 2 | S1 Core owns capability/coverage/normalization validation; S4 AI owns candidate generation; S2 App owns permitted package materialization. | Full-file candidate fixtures, unsupported-field and coverage failures, suppression-safe package tests. |
| 3 | Macro repository and playback adapters implement revision/test transactions; Automation Owner B integrates run identity, with Owner A accepting any reducer contract change; S3 renders accepted projections. | Digest invalidation, stale-base and crash-injection tests, normal runtime/evidence handoff. |
| 4 | S3 owns correction/test UX; S2 and S4 provide live evidence and candidate services. | Installed-app text-target/wait/drag demonstration, one-action correction, failure and acceptance evidence. |

These are planned handoffs, not implemented API signatures. Before changing an interface, record the request and accepted contract in affected workstreams and `08-parallel-workstreams.md`; Automation A/B/C changes also update `../automation-engine/02-parallel-workstreams.md` and affected owner files. Do not add reconstruction side effects to SwiftUI or enlarge Recorder/Player with reusable core policy.

Run focused Swift Testing suites for each changed boundary first. When implementation crosses Core/App/runtime, run:

```sh
swift test --scratch-path .build-test --enable-swift-testing --disable-xctest
swift build -Xswiftc -swift-version -Xswiftc 6
git diff --check
```

Implementation acceptance remains unchecked in `acceptance-checklist.md` until direct tests and required live evidence exist. Documentation-only design updates do not establish build or product readiness.

## 18. Alternatives Considered

### Suggestion-only or patch-only AI output

Rejected as the product contract. It unnecessarily constrains transformations and makes large cleanup operations verbose. A coverage record may resemble a mapping, but AI output remains a complete candidate file.

### Video-only reconstruction

Rejected for the first version. Video alone makes keyboard details, event ordering, button state, and exact interaction timing harder to recover. The cleaned macro provides the operation skeleton; MP4 provides meaning and state.

### Event-only cleanup

Rejected. Coordinates and delays do not reveal the label that was clicked or the visual transition that ended a wait.

### Immediate overwrite of the accepted macro

Rejected. Full-file AI editing does not require sacrificing recoverability. Candidate revision plus atomic promotion provides broad editing with negligible additional user interaction.

### Require the user to confirm every inferred action

Rejected. It recreates the maintenance burden the feature is intended to remove. The default flow is summary plus test; detailed correction is available only when needed.

## 19. Acceptance Definition

This design is implemented only when all of the following are true:

- an ordinary SparkleRecorder recording retains a playable macro and MP4;
- live event/video alignment meets the stated tolerance or reports degraded alignment;
- the App can reconstruct and display the recorded operations over the MP4;
- AI can receive the complete authorized macro/video evidence and produce a complete candidate macro;
- local validation permits broad edits but prevents malformed files and unexplained action loss;
- the candidate can simplify movement/drag, introduce stable locators, and replace fixed waits with state waits;
- the user can understand the reconstructed flow, test it, and correct an uncertain target cheaply;
- the accepted source revision survives every failure before promotion;
- successful user acceptance promotes the candidate without breaking schedules or workflow references;
- docs and live product evidence distinguish implemented behavior from this accepted design.

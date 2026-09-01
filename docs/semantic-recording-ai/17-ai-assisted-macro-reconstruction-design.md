# AI-Assisted Macro Reconstruction From Recorded Video

Updated: 2026-09-01

Status: Accepted design; implementation not started

Owners: Recording/Video Alignment, Macro Core, AI Collaboration, Macro Review

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

## 4. Product Boundary

### 4.1 AI may do

AI may:

- read the complete candidate macro representation;
- inspect the complete local MP4 when the user starts optimization;
- inspect event-centered clips and extracted frames;
- replace the entire candidate event array;
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

## 8. AI Input Package

The AI optimization session receives one local package:

```text
ai-macro-reconstruction/
  source-macro.json
  reconstruction.json
  alignment.json
  recording.mov
  frames/
  clips/
  observations.json
  instructions.json
```

`source-macro.json` is the complete source `SavedMacro`, not a lossy text export. `reconstruction.json` provides grouped actions and source-event coverage. `recording.mov` is the canonical visual record. Frames, clips, and observations are indexes and acceleration aids, not replacements for the MP4.

The AI adapter may extract event-centered clips to reduce model context, but the full MP4 remains available when the user authorizes optimization. The adapter must not claim that the model inspected the complete video when it only inspected selected frames or clips.

The optimization instructions must include:

- supported `SavedMacro` schema version;
- supported locator and condition fields;
- transformation guidance;
- output path for the complete candidate macro;
- prohibited unsupported fields;
- instruction to retain candidate provenance and uncertainty annotations outside playback-critical fields.

## 9. Full-File Rewrite Contract

### 9.1 Output

AI writes a complete candidate `SavedMacro`, including metadata, surfaces, and an entire event array. It may make broad changes. It does not return a mandatory patch list.

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

Coverage is a quality audit, not an editing mechanism. The user does not need to review every mapping. The app blocks promotion only when meaningful source actions disappear without any disposition.

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

## 17. Delivery Slices

### Slice 1: Alignment and reconstruction truth

- freeze clock mapping and geometry snapshot contracts;
- add deterministic operation reconstruction;
- prove frame-accurate event/video mapping with fixtures;
- render a local operation overlay without AI.

### Slice 2: AI package and full-file candidate

- materialize complete macro, MP4, reconstruction, alignment, and evidence package;
- define full candidate output and app-owned metadata normalization;
- decode and validate complete AI rewrites;
- implement source-action coverage audit.

### Slice 3: Test and promotion

- add candidate revision storage;
- run candidate through existing playback/evidence boundaries;
- add atomic accept and restore behavior;
- preserve schedules and workflow references.

### Slice 4: Product optimization loop

- add synchronized video/action review;
- add natural-language summary and uncertain action correction;
- prove click locator, state wait, and drag simplification with live evidence;
- tune prompts and transformation policy from accepted/rejected candidate outcomes.

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

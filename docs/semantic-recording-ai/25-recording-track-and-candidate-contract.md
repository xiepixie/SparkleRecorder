# Recording Track Separation and Candidate Authoring Contract

Updated: 2026-09-07

Status: Current implementation contract; automated verification complete, live acceptance open

This document records the accepted product and architecture changes discovered from a real Library reconstruction candidate. The Core/App implementation and direct tests now realize this contract; installed-app recording and representative live-scroll acceptance remain separate gates.

## 1. Problems confirmed in production-shaped data

### Candidate template contract drift

The previous `MacroReconstructionPackage.export()` implementation built `candidate-template.json` by encoding a `MacroCandidateDocument` whose `macro` was the full Library `SavedMacro`. A Library macro may contain `libraryOrder`, statistics, preview caches, semantic evidence references, and other app-owned metadata. Those fields are not part of the AI authoring Interface, and `libraryOrder` was rejected by the strict candidate validator. A real Library macro therefore exposed a package that SparkleRecorder itself could not strictly decode.

### High-density continuous scroll playback

The previous recording pipeline sampled drags but retained essentially every continuous scroll event. Short trackpad gestures could therefore produce hundreds of playable scroll events. Playback still posts each final playable event individually and intentionally performs target-hit-testing stabilization at the App Adapter edge, so playable density must be reduced before that Adapter rather than hidden inside it.

### Playable and evidence tracks are conflated

The previous `Recorder.flushPending()` appended the same event batch to the saved playable macro and to semantic recording. That prevented deterministic playable compaction while retaining denser trajectory evidence, and made later cleanup liable to invalidate `sourceEventsMatchRecording`. The current Recording Session Interface now returns separate playable and evidence tracks.

## 2. Accepted architecture

### P0 — Candidate authoring projection Module

`MacroCandidateAuthoringProjection` is the Core Module that projects a full `MacroCandidateDocument` into the strict JSON shape used by `candidate-template.json` and external `candidate.json` input.

Its Interface exposes only candidate-authoring fields required to reconstruct executable events. Source-owned Playback Surface bodies are deliberately omitted from external candidate JSON; authors choose among existing Source Revision surfaces only through `event.surfaceId`. The external source input is separately projected through `MacroReconstructionSourceContext` v2, whose minimized Surface description preserves semantic identity and recorded geometry while withholding local WindowServer/display IDs and capture timestamps. Library ordering, personalization, playback statistics, preview caches, local evidence references, hotkeys, notes, and chained Macro identity do not leave the App merely because a reconstruction package is exported. Live target-window rebinding remains an App-owned Candidate Editor operation.

The strict validator remains authoritative. The fix is not to allow `libraryOrder` or other app-owned fields. Contract versions are centralized in `MacroReconstructionContractVersions`; package v4 exports a small `harness.json` ledger/read plan plus `authoring-contract.json` as the canonical machine-readable contract for `macro-candidate/v4`, the faithful/robust policy, source-context v3, action-context v3 and candidate-action revision. The authoring contract expands every executable event code into its enum name/meaning, every Reconstruction Action into its candidate representation, accepted string enums, strict macro/event/anchor allowlists, limits, `surfaceAuthoringPolicy`, `textOperationPolicy`, and validator-facing rules. Capability v4 publishes `capabilities.requiredEventFields`: every candidate event must retain the ten non-optional `RecordedEvent` Codable fields (`kind`, `time`, `x`, `y`, `keyCode`, `flags`, `mouseButton`, `clickCount`, `scrollDeltaY`, `scrollDeltaX`). Candidate compaction may omit genuinely optional fields when their semantics are unused, but it must never remove those decoder-required fields. All candidate text operations require an explicit Playback Surface; locator-backed mouse input uses target-window binding plus locator-only strategy, and one pointer gesture must retain one surface/anchor/fallback/timeout identity from mouse-down through mouse-up. Older v3 standalone candidates that copied unchanged Source Revision surfaces remain readable for compatibility, and a dedicated v3 package adapter reads the prior `contract.json`/`capabilities.json`/`authoring-policy.json` layout; new v4 exports omit Source Revision surface bodies from candidate JSON. Older full-`SavedMacro` candidates are recognized at the App import seam and receive a re-export/regenerate message rather than a generic unsupported-field error; they are not silently normalized into the new contract.

Acceptance:

- a source with `libraryOrder != nil` exports a template that `MacroCandidateValidator.decode` accepts;
- export -> strict inspect/decode -> normalize/import works;
- template JSON does not contain Library order, personalization, protected execution policy, statistics, or preview cache fields;
- `authoring-contract.json` explicitly declares the ten decoder-required event fields so external authors cannot accidentally compact them away;
- old candidates that still carry known app-owned macro fields are identified as an older package format, while genuinely unknown execution fields remain strict validation failures.

### P1 — ScrollGestureCompactor Core Module

`ScrollGestureCompactor` is the deterministic Core Module that compacts only continuous scroll input into final playable events.

The Module treats recorded deltas as a cumulative curve and resamples it on a fixed time grid. It must preserve total scroll displacement and must split/resample segments at semantic/mechanical boundaries:

- gesture phase changes;
- momentum phase changes;
- direction reversal;
- surface change;
- coordinate/binding or cursor target change;
- modifier flag change;
- continuous/non-continuous mode change;
- long pause;
- beginning and end of a gesture.

Non-continuous wheel input remains one-to-one. `EventGrouper.scrollSegmentGap` remains unchanged. `CGEventPoster` / `MouseKeyboardSynthesizer` does not perform hidden compaction.

Acceptance:

- cumulative X/Y displacement is preserved exactly for integer playback deltas;
- first reverse-direction sample is not delayed into a later count-based chunk;
- phase/momentum/surface/flags changes are never merged across;
- a dense continuous fixture is materially smaller while retaining start/end time and monotonic ordering.

### P1 — Playable/evidence track Seam

Recording Session processing now produces two explicit tracks:

- `playableEvents`: deterministic execution events after mechanical compaction;
- `evidenceSamples`: privacy-safe input trajectory evidence before playable compaction;
- `playableEvidenceLinks`: mapping from each playable event to the evidence sample span that produced it.

The session processor owns the stateful scroll compactor so 30 Hz UI drain cadence never becomes a gesture boundary. Open scroll segments can survive ordinary drains and are finalized by a semantic boundary, sufficient idle gap, or recording stop.

Semantic recording receives playable events for source identity and timeline/frame alignment, and receives privacy-safe mechanical evidence samples separately for reconstruction analysis. The evidence track is bounded, omits readable keyboard/text fields, and persists in `input-evidence.jsonl` rather than inflating the manifest. `RecordingReconstructionProvenance.playableEvidenceLinks` records the playable-to-evidence mapping.

Stopping finalizes the playable event sequence, including the last partial scroll bucket and recorder-hotkey tail cleanup, before semantic capture computes its source digest. The digest is therefore bound to the exact final saved playable sequence rather than an earlier capture copy.

### P1 — AI visual inspection navigation Module

`MacroVisualInspectionGuideProjector` converts verified reconstruction provenance into `visual-inspection.json` when aligned visual bytes are explicitly exported. The Module does not perform screenshots, OCR, or icon recognition. Its Interface gives external AI tools a deterministic navigation map so they can use their own image/video tools correctly:

- action-linked recording/session ranges and verified segment-local video seek ranges;
- exported key-image candidates near each action;
- the observed interaction point projected into aligned frame pixels;
- a primary search/crop region for small labels/icons and a larger context region for disambiguation;
- both `framePixels` and portable `normalizedFrame` regions with a top-left origin;
- the policy parameters that define pre-roll/post-roll and search-region size.

`focus.framePoint` is evidence of where the input occurred, not a claim that a label or icon is centered there. The AI searches within `primaryRegion` first and expands to `contextRegion` when necessary. `framePixels` are valid only for the measured aligned video `frameSize`; when an exported key image has a different `imageSize`, callers use `normalizedFrame` rather than reusing video pixel coordinates.

The guide is emitted only when source-event identity is verified and at least one permitted visual artifact is actually exported. Unaligned video/frames never receive action-to-image navigation. The prompt explicitly tells external authors to use their own seek/screenshot/crop/zoom tools and forbids turning icon appearance into an unsupported image locator.

## 3. Explicit non-goals

This change does not:

- change `MacroActionReconstructor` or `EventGrouper.scrollSegmentGap`;
- perform hidden scroll dropping in the playback App Adapter;
- invent text locators, `waitForText`, or verification without aligned visual evidence;
- let AI own deterministic mechanical cleanup that Core can prove;
- require every pointer/hover evidence policy to be solved in the first scroll-compaction slice. The new evidence-track Interface must permit future bounded hover/drag evidence without changing the playable contract.

## 4. Verification

Focused tests cover the candidate projection, strict external authoring Interface, scroll compactor, session dual-track ordering, bounded privacy-safe evidence, evidence sidecar persistence, bundle reference validation, source-event identity, stop-hotkey finalization ordering, and AI visual-inspection seek/crop coordinate guidance. Central automated verification passes 990 Swift Testing tests across 140 suites and the Swift 6 build; `git diff --check` passes. Installed-app live capture remains a separate product gate.

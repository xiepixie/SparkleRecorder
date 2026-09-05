# Macro Reconstruction Foundation Implementation Plan

Updated: 2026-09-04
Status: Foundation batch complete; live integration remains future work

> **For agentic workers:** Use parallel independent tasks with Swift Testing, followed by integration review. Do not delegate further, commit, or edit another owner's files.

**Goal:** Implement the deterministic first boundary of Slice 1: validated video clock mapping, historical geometry projection, stable source actions, and a combined review projection.

**Architecture:** Add pure, additive Core types without changing existing recording bundle decoding or the live Recorder/Player lifecycle. Three owners work in disjoint files; the coordinator integrates their outputs after direct tests. New values describe evidence quality and missing coverage explicitly.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing; Foundation/CoreGraphics value types only.

**Spec:** [17-ai-assisted-macro-reconstruction-design.md](17-ai-assisted-macro-reconstruction-design.md), especially sections 6, 7, 16, and 17.

## Global constraints

- No live keyboard/mouse input, Vision, wall-clock waits, or Application Support access in tests.
- No SwiftUI/AppKit/AVFoundation/ScreenCaptureKit imports in Core; no file mutation.
- No changes to existing bundle schema, recording timestamp behavior, or production rollout in this batch.
- Preserve legacy APIs and existing tests; invalid evidence must not become apparently aligned output.
- All owners use the shared isolated worktree. Each owns only its listed files. Coordinator owns docs and integration files.
- SwiftPM builds share `.build-test`; coordinator serializes build/test runs to avoid redundant builds. Owners write tests first and request a targeted run before implementing.

## Accepted interface handoff

Request: S3 needs reproducible action/geometry/video projections; S2 needs a strict mapping boundary before supplying live timestamps. S1 provides the pure contracts below. Accepted for this foundation batch; this does not close any S2 live gate or accept a persistence schema change.

### Task A: Video clock mapping

Files: create `Sources/SparkleRecorderCore/RecordingVideoClock.swift`, `Tests/SparkleRecorderTests/RecordingVideoClockTests.swift`.

Public interface (all values Sendable/Equatable; persisted input structs Codable):

- `RecordingVideoClockAnchor(recordingTime: Double, videoTime: Double)`.
- `RecordingVideoClockSegment(id: String, anchors: [RecordingVideoClockAnchor], maximumError: Double)`; each segment is one continuous covered interval; at least two anchors required. Multiple discontinuous intervals use distinct IDs.
- `RecordingVideoClockMapping(segments: [RecordingVideoClockSegment], tolerance: Double = 0.05) throws` validates nonempty unique IDs, finite nonnegative anchors/error/tolerance, strictly increasing times in both domains, and nonoverlapping recording intervals (touching endpoints allowed but unqualified query there is ambiguous).
- `videoTime(forRecordingTime: Double, segmentID: String) -> Double?` and `recordingTime(forVideoTime: Double, segmentID: String) -> Double?`: piecewise-linear interpolation, endpoints included, no extrapolation. Invalid query, missing segment, or segment error above tolerance returns nil.
- `segmentID(forRecordingTime: Double) -> String?`: only unique covered usable segment; ambiguous/unavailable yields nil.

Maximum error is provider-supplied evidence uncertainty, not proof inferred from anchors. Mapping must not claim measured live alignment. Invalid containers throw typed errors; valid degraded segments remain representable but cannot return usable mapping. Test offset/drift/inverse/multiple segments/gaps/endpoints/invalid data/degraded and touching ambiguity.

- [x] Write and run failing Swift tests.
- [x] Implement validated mapping and run focused tests.
- [x] Review edge cases and report exact public interfaces.

### Task B: Historical geometry

Files: create `Sources/SparkleRecorderCore/RecordingGeometryProjection.swift`, `Tests/SparkleRecorderTests/RecordingGeometryProjectionTests.swift`.

Public interface:

- `RecordingGeometrySnapshot(surfaceID: String, recordingTime: Double, validUntil: Double, captureBounds: RectValue, frameSize: RecordingImageSize)` Codable/Equatable/Sendable. Bounds are global screen points, frame size is pixels; mapping uses top-left convention. Validity is half-open `[recordingTime, validUntil)`.
- `RecordingGeometryHistory(snapshots: [RecordingGeometrySnapshot]) throws` validates finite positive bounds/dimensions, nonempty surface, nonnegative ordered intervals and no overlap for same surface; input may be unsorted. Immutable validated history.
- `framePoint(forGlobalPoint: PointValue, surfaceID: String, recordingTime: Double) -> PointValue?`: historical selection then affine point-to-pixel mapping; missing/expired history or out-of-capture points return nil. Bounds edges included for point projection. Never use final snapshot as fallback.

No inferred titlebar conversion: caller supplies global point and actual capture bounds. Future adapter owns window/content coordinate conversion. Test move/resize, scaling, multiple surfaces, unsorted history, gaps/boundaries, invalid dimensions, and out-of-capture points.

- [x] Write and run failing Swift tests.
- [x] Implement validated history and run focused tests.
- [x] Review edge cases and report exact public interfaces.

### Task C: Deterministic source actions

Files: create `Sources/SparkleRecorderCore/MacroActionReconstruction.swift`, `Tests/SparkleRecorderTests/MacroActionReconstructionTests.swift`.

Public interface:

- `MacroReconstructedAction` Equatable/Sendable: `id: String`, `kind: ActionGroupKind`, `sourceEventIndices: [Int]`, `startTime: Double`, `endTime: Double`, `surfaceID: String?`, `startPoint: PointValue?`, `endPoint: PointValue?`.
- `MacroActionReconstructor.reconstruct(events: [RecordedEvent], sourceRevision: String) throws -> [MacroReconstructedAction]`.

Use frozen `EventGroupingOptions()` internally with `EventGrouper`; do not expose editor grouping knobs or use summaries/UUID defaults as identity. IDs include policy version, source revision and source identity/range using locale-independent representation. Validate finite nonnegative nondecreasing times and nonempty revision. Every source event index must appear exactly once across non-wait actions, and derived waits carry ranges even without event indices. If a group spans surfaces, split conservatively into raw event actions rather than invent one surface. Do not simplify/delete input or change original events. Single-event mouse down/up groups are source evidence, not guaranteed executable actions. Never claim text grouping changes event kinds.

Test click/drag/key/text/scroll/derived wait coverage, identical reconstruction, revision distinction, localized-summary independence, equal-time events, multiple surfaces, and invalid timelines. Existing EventGrouper behavior is reused, not rewritten.

- [x] Write and run failing Swift tests.
- [x] Implement reconstruction and run focused tests.
- [x] Review coverage invariants and report exact public interfaces.

### Task D: Integration and acceptance ledger (coordinator)

Files: create `Sources/SparkleRecorderCore/MacroReconstructionProjection.swift`, `Tests/SparkleRecorderTests/MacroReconstructionProjectionTests.swift`; update this plan, semantic workstreams, status index and acceptance audit tests as needed.

Consume A/B/C. Explicit per-event source-to-session times and gap ranges must map action bounds without assuming playback time equals session time. Emit action ID, source range, optional aligned segment/video range, optional pixel points and typed unavailability reasons. No live UI wiring in this batch. Tests prove initial idle offsets, missing mappings, segment gaps and missing historical geometry remain visible. Review the whole diff; run focused tests, full Swift Testing and Swift 6 build.

- [x] Baseline audit verified: no documentation mismatch to repair; live gates remain open.
- [x] Write/run integration tests first, implement projection, verify owner handoffs.
- [x] Run full tests, Swift 6 build and `git diff --check`.
- [x] Update factual status and remaining delivery dependencies.

## Next serial boundary (not implemented by this batch)

After these contracts pass, S2 integrates actual session origins/sample PTS, capture end and geometry production into the ordinary Recorder and bundle persistence with backward compatibility. S3 then attaches the projection to video review using accepted live bundles. S4 candidate generation and repository promotion remain later slices. A pure fixture foundation does not demonstrate live frame accuracy or product-ready AI reconstruction.

## Execution evidence

- Baseline: 15 tests in RecordingTimelineTests, RecordingCoordinateBinderTests and SemanticRecordingAcceptanceChecklistTests passed; no pre-existing audit repair needed.
- Test-first builds confirmed absent APIs. Focused regressions reproduced click-count overflow, lost cross-surface waits, mixed-shortcut pointer loss, incorrect scroll endpoints, and missing interior timestamp misclassification before fixes.
- Focused verification: 46 tests in four new suites passed.
- Full verification: 770 tests in 93 suites passed with `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest`.
- Swift 6 verification: `swift build -Xswiftc -swift-version -Xswiftc 6` passed.
- Independent review: A/B clean; C and integration findings fixed and re-reviewed with no remaining actionable findings. `git diff --check` passed.

## Accepted implementation clarifications

- Empty video mappings represent unavailable evidence. Only usable segments participate in touching-endpoint ambiguity; explicit segment queries still disambiguate endpoints.
- Editor behavior annotations are stripped on a temporary copy. Mixed-surface and mixed-keyboard/pointer groups split into raw evidence, restoring internal waits. Original events are unchanged.
- Numeric overflow-risk input retains singleton source evidence instead of duplicating EventGrouper's aggregation policy. Nonfinite mouse points and invalid timelines are rejected.
- Source-derived mouse endpoints match their source timestamps, including merged scroll bursts.
- All constituent event timestamps are required for an aligned action; missing interior timestamps produce `missingSourceTime`.

The first batch is additive Core infrastructure with no production capture or UI wiring. All AI reconstruction product gates remain open; no claim of live frame accuracy, AI candidate generation, or atomic promotion is made.

# S1 Contract And Core Schema

更新时间：2026-07-06
状态：Core schema v0 first pass done; live producers/consumers pending
Owner：S1, Contract And Core Schema
并行对象：S0 Workflow Evidence Closure, S2 App Capture And Visual Index

S1 的任务是冻结 semantic recording 的可共享事实层：App 负责生产，Review UI 负责展示，CLI/AI 负责查询，但三者都不能各自发明一套 frame、artifact、comparison 或 suppression 结构。

## 1. Scope

S1 owns:

- `SemanticRecordingBundle`
- video segment、keyframe、timeline event、AI-safe semantic event、visual observation value models
- safe relative `RecordingArtifactRef`
- source preview、runtime sample、preview comparison refs
- suppression records
- pure alignment/query helpers
- CLI/UI 可复用的 query result 和 suggestion value types
- fixture shape and unit tests

S1 does not own:

- live ScreenCaptureKit / Vision / AX implementation
- bundle filesystem layout or retention deletion behavior
- SwiftUI review screens
- natural-language model calls
- workflow mutation or execution

## 2. Current Contract

Implementation:

- Core file: `Sources/SparkleRecorder/SemanticRecordingBundle.swift`
- Shared fixture: `Sources/SparkleRecorder/SemanticRecordingFixture.swift`
- Tests: `Tests/SparkleRecorderTests/SemanticRecordingBundleTests.swift`
- SwiftPM inclusion: `Package.swift`

Accepted v0 types:

| Contract Area | Type(s) | Notes |
| --- | --- | --- |
| schema/version | `SemanticRecordingSchema`, `SemanticRecordingSchemaVersion` | Current v0 is `0.1`; unsupported major versions validate as issues |
| safe refs | `RecordingArtifactRef` | Rejects absolute paths, schemes, `..`, `~`, backslashes and drive-style paths |
| video | `RecordingVideoSegment`, `RecordingCaptureTarget`, `RecordingCapturePolicy` | Supports default video+keyframes and future keyframe-only mode |
| frames | `RecordingFrameReference` | Carries recording time, video segment/time, surface id, image ref, bounds and related event ids |
| private timeline | `RecordingTimelineEvent` | Maps to internal `timeline.jsonl` |
| AI-safe events | `RecordingSemanticEvent` | Maps to filtered `events.jsonl`; accessible through `SemanticRecordingBundle.aiSafeEvents` |
| observations | `RecordingVisualObservation` | Stores OCR/AX/window/pixel/template/baseline/pattern observations without running providers in core |
| S0 preview refs | `RecordingSourcePreviewReference`, `RecordingRuntimeSampleReference`, `RecordingPreviewComparison` | Accepted source-frame/runtime-sample/decision shape |
| suppression | `RecordingSuppressionRecord` | Maps to `suppressed.jsonl`; keeps reason/count/redacted refs first-class |
| CLI/UI payloads | `RecordingQueryResult`, `RecordingSuggestion`, `RecordingEvidenceReference` | Stable evidence refs for later low-token queries and reviewable suggestions |
| shared fixtures | `SemanticRecordingFixture.checkoutBundle`, `checkoutQueryResults`, `checkoutSuggestions` | Deterministic checkout recording bundle for S2/S3/S4 prototypes |

Pure helpers accepted in v0:

- `videoSegment(containing:)`
- `nearestFrame(to:within:)`
- `frames(relatedToEventID:)`
- `observations(frameID:)`
- `previewComparisons(sourcePreviewRefID:)`
- `validate()`

## 3. S0 Request Response

S1 accepts the S0 request in [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md) as a first-pass core contract.

Mapping:

| S0 Need | S1 Type / Field |
| --- | --- |
| stable source ref id | `RecordingSourcePreviewReference.id` |
| `ocrRegion`, `imageTemplate`, `regionBaseline`, `pixelSample` | `RecordingVisualReferenceKind` |
| recording/frame/event/surface identity | `recordingID`, `frameID`, `eventID`, `surfaceID` |
| safe source artifact path | `RecordingSourcePreviewReference.artifactRef` |
| crop/search bounds and image size | `RecordingBounds`, `RecordingImageSize` |
| optional content identity | `RecordingContentDigest` |
| runtime run/task/condition sample | `RecordingRuntimeSampleReference` |
| matcher kind/version/provider | `RecordingMatcherDescriptor` |
| matched/changed/missing/unreadable states | `RecordingPreviewComparisonOutcome` |
| diff/fallback reason | `diffArtifactRef`, `reason` |

Deferred from S1:

- actual screenshot/template/baseline file creation belongs to S2/S3 app-edge code
- actual matcher implementation and score production belongs to S2 adapters
- UI rendering of source/runtime/diff previews belongs to S3
- copying frame crops into `AutomationWorkflowDraftVisualAssets` still needs a separate asset-mapping slice
- privacy retention, deletion and exclusion UI remain App/product work

## 4. Verification

Current S1 verification:

```bash
swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'SemanticRecordingBundleTests'
```

Result on 2026-07-06: passed, 6 tests.

Covered:

- safe artifact refs normalize relative paths and reject unsafe paths
- bundle video/frame/event alignment helpers
- source preview/runtime sample/preview comparison round trip
- deterministic checkout fixture bundle, query result and suggestion shape for next workstreams
- dangling comparison refs report explicit validation issues
- duplicate ids and unsupported schema versions report validation issues

## 5. Interfaces For Next Owners

S2 can now spike live capture against this contract:

- write one `RecordingVideoSegment` for `.mov`
- write event-aligned `RecordingFrameReference` records
- produce `RecordingVisualObservation` values from Vision/AX adapters
- produce `RecordingSuppressionRecord` when evidence is withheld

S3 can build fixture Review UI without waiting for live capture:

- load `SemanticRecordingFixture.checkoutBundle()`
- render frame strip and selected event/frame
- render source/runtime/comparison preview refs
- keep missing/unreadable states visible instead of empty UI

S4 can start CLI fixtures:

- `recording show` can summarize `SemanticRecordingFixture.checkoutBundle()`
- `recording frames` can list the fixture `RecordingFrameReference` records
- `recording ocr/search` and `recording suggest` can begin with `checkoutQueryResults` and `checkoutSuggestions`

## 6. Implementation Log

- 2026-07-06: Added S1 core schema v0 in `SemanticRecordingBundle.swift`, added unit tests, accepted S0 preview-ref semantics as first-pass contract. No live ScreenCaptureKit, Vision, Review UI, CLI command, retention policy or asset-copy behavior is claimed complete.
- 2026-07-06: Added `SemanticRecordingFixture` with deterministic checkout bundle, query result and suggestion fixtures for S2/S3/S4. `SemanticRecordingBundleTests` now verifies the shared fixture validates, round-trips and cites stable evidence refs.

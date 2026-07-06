# S0 Workflow Evidence Closure

更新时间：2026-07-06
状态：Active workstream
Owner：S0, Workflow Evidence Closure
并行对象：S1 Contract And Core Schema, S2 App Capture And Visual Index

S0 的任务是先证明现有 Workflow 证据链可信。Semantic recording 后续会把录制帧、视觉资产、运行样本和 AI 建议都接到这条证据链上；如果现在的 Run Detail、Open/Reveal、branch decision、drag/reorder 证据不能被用户信任，后面的 AI/视频能力只会放大混乱。

## 1. Scope

S0 owns:

- live visual diagnostics Open/Reveal product evidence
- macro evidence Reveal Report / Open Screenshot product evidence
- branch evidence real-run consistency product evidence
- real drag/reorder or drag-link WYSIWYG product evidence
- template/baseline preview refs product contract request to S1
- fixture-vs-live evidence labeling rules

S0 does not own:

- `SemanticRecordingBundle` schema implementation
- ScreenCaptureKit `.mov` capture
- Vision/OCR observation production
- Review UI timeline implementation
- Recording CLI or AI draft-from-recording

## 2. Current Status

| Evidence Area | Current State | S0 Gap |
| --- | --- | --- |
| Idle/running Workflow surface | Fixture screenshots exist in `workflow-page-productization/product-evidence/` | No additional S0 action unless Owner 2 changes layout |
| Visual diagnostics drill-in | Fixture screenshot proves `AutomationTaskRun.conditionEvidence` rendering, artifact previews and action feedback | Need live recording that proves actual App Support artifacts open/reveal through presenter |
| Macro failure evidence | Fixture screenshots prove per-run manifest/report/screenshot binding and preview unavailable fallback | Need live playback failure recording for Reveal Report / Open Screenshot |
| Branch evidence drill-in | Fixture screenshot proves durable `AutomationTaskRun.branchEvidence` UI path | Need real run showing FlowGraph edge, selected run row and Run Detail agree |
| Drag/link and task reorder | Fixture screenshots prove visible authoring states | Need real `.mov` / `.mp4` proving indicator, mutation and final graph/list position match |
| Template/baseline preview refs | S1 accepted first-pass source-frame/runtime-sample preview contract in `SemanticRecordingBundle`; fixture artifact `template-baseline-preview-refs.png` renders Source / Runtime / Decision together | Need S3/Review UI integration and later live sample evidence before product drill-in is complete |
| Evidence audit gate | `workflow product-evidence audit` reads the product evidence directory and separates fixture/live requirements; pure core logic is covered by `AutomationProductEvidenceAuditTests` | Current audit is 9/13 required items present; all four live S0 items are missing |

S0 should not mark live-product checklist items done from fixture screenshots. Fixtures prove UI wiring; S0 completion requires live product evidence or an accepted contract note for pure design tasks.

## 3. Immediate S0 Queue

| ID | Task | Output | Blocks / Feeds |
| --- | --- | --- | --- |
| S0-1 | Capture live visual diagnostics Open/Reveal | `live-visual-diagnostics-open-reveal.mov` or `.mp4` + `.md` sidecar | Proves artifact presenter path before semantic runtime samples reuse it |
| S0-2 | Capture live macro evidence Open Screenshot / Reveal Report | `live-macro-evidence-open-reveal.mov` or `.mp4` + `.md` sidecar | Proves failed run evidence path before recording bundle failure comparisons |
| S0-3 | Capture branch evidence real-run consistency | `live-branch-evidence-consistency.mov` or `.mp4` + `.md` sidecar | Proves durable branch payload is not only fixture-correct |
| S0-4 | Capture drag/reorder WYSIWYG mutation | `live-task-reorder-wysiwyg.mov` / `.mp4` or `live-drag-link-wysiwyg.mov` / `.mp4` + `.md` sidecar | Gives S3 a baseline for future recording review interactions |
| S0-5 | Accept template/baseline preview refs request with S1 and render fixture evidence | [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md), [s1-contract-core.md](s1-contract-core.md), and `product-evidence/template-baseline-preview-refs.png` | Core contract accepted; fixture rendering done; real Review UI integration remains open |

Recommended order: S0-5 core contract is accepted. S0-1 and S0-3 remain the highest-risk live evidence gates.

## 4. Interface Request To S1

S0 requests S1 to reserve value-model support for source-frame/runtime-sample preview comparisons. The detailed request lives in [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md).

Minimum S1 fields S0 needs:

- stable recording/source ids: `recordingID`, `frameID`, optional `eventID`, optional `surfaceID`
- safe relative artifact refs for source template/baseline and runtime sample/crop
- crop/search bounds plus coordinate space and image size
- ref kind: OCR region, image template, region baseline, pixel sample, runtime display sample, runtime watched-region sample
- digest or content identity for stale/missing asset diagnostics
- comparison payload: score, threshold, matcher kind/version, outcome, fallback reason, optional diff artifact ref

S1 accepted the first-pass core contract in [s1-contract-core.md](s1-contract-core.md). S0 accepts the naming/mapping there:

- source previews: `RecordingSourcePreviewReference`
- runtime samples: `RecordingRuntimeSampleReference`
- decisions/comparisons: `RecordingPreviewComparison`
- matcher identity: `RecordingMatcherDescriptor`
- explicit outcomes: `RecordingPreviewComparisonOutcome`
- safe paths: `RecordingArtifactRef`

This closes the S0 -> S1 contract wait. It does not close the UI/product evidence requirement: S0 still needs a future artifact showing source reference, runtime sample and decision/comparison rendered together without SwiftUI constructing raw paths.

## 4.1 Coordination With S2

S0 and S2 now run in parallel:

- S0 owns Workflow product trust: live visual diagnostics Open/Reveal, macro evidence Open/Reveal, branch evidence consistency, and authoring WYSIWYG evidence.
- S2 owns semantic capture production: `.mov`, event-aligned keyframes, Vision OCR observations, bundle storage and future suppression.

Shared boundary:

- S0 live sidecar labels and `workflow product-evidence sidecar-template` are reusable as the capture-note pattern for S2 semantic recording product evidence.
- S2 `SemanticRecordingBundle` output can later feed S0/S3 source/runtime comparison UI, but it does not satisfy S0 live Workflow gates by itself.
- S0 should not claim semantic capture completion; S2 should not claim product trust while S0 live Workflow evidence gates remain open.
- If S2 adds fields needed to show recorded source frame, runtime sample, OCR observation or capture target in Run Detail, S0 records the UI need here and S2 records the producer/field state in [s2-app-capture-visual-index.md](s2-app-capture-visual-index.md).

## 5. Product Evidence Capture Rules

Every S0 live artifact sidecar must include commit/worktree context plus these exact labels. `workflow product-evidence audit --require-live` validates the labels when the paired live clip exists:

- `Capture date:`
- `App build/run source:`
- `Workflow/package:`
- `User action:`
- `Checklist item:`
- `Known gaps:`
- `Evidence source:`

The sidecar text can include more detail, but those labels must remain stable so the audit gate can distinguish a real review note from an empty placeholder.

Suggested filenames under `docs/workflow-page-productization/product-evidence/`:

- `live-visual-diagnostics-open-reveal.mov`
- `live-visual-diagnostics-open-reveal.mp4`
- `live-macro-evidence-open-reveal.mov`
- `live-macro-evidence-open-reveal.mp4`
- `live-branch-evidence-consistency.mov`
- `live-branch-evidence-consistency.mp4`
- `live-task-reorder-wysiwyg.mov`
- `live-task-reorder-wysiwyg.mp4`
- `live-drag-link-wysiwyg.mov`
- `live-drag-link-wysiwyg.mp4`

If a capture is impossible in a given environment, S0 should leave the checklist unchecked and record the blocker in this file instead of replacing live evidence with another fixture.

## 6. Live Capture Runbook

Fixture refresh, when UI changes but live evidence is not being claimed:

```bash
swift run SparkleRecorder workflow product-evidence snapshot visual-diagnostics-drill-in
swift run SparkleRecorder workflow product-evidence snapshot branch-evidence
swift run SparkleRecorder workflow product-evidence snapshot failed-run-detail
swift run SparkleRecorder workflow product-evidence snapshot task-reorder-authoring
```

Evidence audit:

```bash
swift run SparkleRecorder workflow product-evidence audit --json
swift run SparkleRecorder workflow product-evidence audit --require-live --json
```

The first command reports current status without failing the shell. The second is the strict S0 closure gate and must fail until live artifacts are present.

Live sidecar template, before recording or immediately after naming the clip:

```bash
swift run SparkleRecorder workflow product-evidence sidecar-template live-visual-diagnostics-open-reveal
swift run SparkleRecorder workflow product-evidence sidecar-template live-macro-evidence-open-reveal
swift run SparkleRecorder workflow product-evidence sidecar-template live-branch-evidence-consistency
swift run SparkleRecorder workflow product-evidence sidecar-template live-authoring-wysiwyg --sidecar live-drag-link-wysiwyg.md
swift run SparkleRecorder workflow product-evidence sidecar-template live-authoring-wysiwyg --sidecar live-task-reorder-wysiwyg.md
```

The template intentionally contains angle-bracket placeholders. Fill them before saving the sidecar; strict audit treats placeholders as incomplete.

Live capture, when closing S0 gates:

1. Build or launch the same App binary being reviewed.
2. Use a real repository/workflow package, not only `AutomationRunState.ownerCFixture`.
3. Trigger the relevant workflow or authoring action.
4. Capture the full App surface and the external Open/Reveal result when relevant.
5. Save the video under `docs/workflow-page-productization/product-evidence/`.
6. Generate a same-name `.md` sidecar template with `workflow product-evidence sidecar-template`, fill every placeholder, and keep it beside the clip.
7. Update this workstream, `06-current-work-and-next-tasks.md`, product evidence README and `acceptance-checklist.md`.

S0 should prefer short clips over long demos: the artifact only needs to prove the exact gate.

## 7. S0 Acceptance Gates

S0 can call Workflow evidence closure complete only when:

- live visual diagnostics Open/Reveal is recorded from the installed App or a local App build
- live macro failure evidence Open Screenshot / Reveal Report is recorded
- live branch evidence consistency is recorded
- at least one real authoring WYSIWYG mutation recording exists for drag/reorder or drag-link
- template/baseline preview refs have an accepted S1 contract note and fixture artifact; final Review UI still needs the same source/runtime/decision evidence without raw path handling in SwiftUI
- `06-current-work-and-next-tasks.md`, `08-parallel-workstreams.md`, product evidence README and semantic checklist agree about what is done versus fixture-only

Current status: not complete. The fixture foundation is strong, S1 preview-ref acceptance is done, and the preview-ref fixture artifact is present, but live Workflow evidence remains open.

## 8. Implementation Log

- 2026-07-06: Created S0 workstream file and documented S0/S1 interface request path. No live evidence item was marked complete.
- 2026-07-06: Added `workflow product-evidence audit` and strict `--require-live` mode. Smoke result after preview-ref fixture: default audit exits 0 with 9/13 required evidence items present; strict audit exits 1 because `live-visual-diagnostics-open-reveal`, `live-macro-evidence-open-reveal`, `live-branch-evidence-consistency`, and `live-authoring-wysiwyg` are missing.
- 2026-07-06: S1 accepted the source-frame/runtime-sample preview-ref request in [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md) and [s1-contract-core.md](s1-contract-core.md). This closes the contract wait, not the live-product UI evidence gates.
- 2026-07-06: Moved product-evidence audit semantics into pure core `AutomationProductEvidenceAudit` and added `AutomationProductEvidenceAuditTests` for fixture-only gaps, authoring OR semantics, missing sidecars and Codable round-trip.
- 2026-07-06: Added `template-baseline-preview-refs.png` / `.md` product-evidence fixture rendered from `SemanticRecordingFixture.checkoutBundle`, and added it to the product-evidence audit gate. This closes the fixture rendering proof for Source / Runtime / Decision, not the final S3 Review UI or live evidence gates.
- 2026-07-06: Strengthened `workflow product-evidence audit` for S0 live evidence: live clips may be `.mov` or `.mp4`, but the paired `.md` sidecar must contain the required capture labels before the item can satisfy the strict gate.
- 2026-07-06: Added `workflow product-evidence sidecar-template` so each live S0 gate can generate the exact sidecar labels expected by strict audit; placeholders still fail audit until filled.

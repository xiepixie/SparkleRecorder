# S0 Workflow Evidence Closure

更新时间：2026-07-06
状态：Active workstream
Owner：S0, Workflow Evidence Closure
并行对象：S1 Contract And Core Schema

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
| Template/baseline preview refs | Visual asset refs exist, runtime sample artifacts exist | Need accepted source-frame/runtime-sample preview contract with S1 |

S0 should not mark live-product checklist items done from fixture screenshots. Fixtures prove UI wiring; S0 completion requires live product evidence or an accepted contract note for pure design tasks.

## 3. Immediate S0 Queue

| ID | Task | Output | Blocks / Feeds |
| --- | --- | --- | --- |
| S0-1 | Capture live visual diagnostics Open/Reveal | `live-visual-diagnostics-open-reveal.mov` + `.md` sidecar | Proves artifact presenter path before semantic runtime samples reuse it |
| S0-2 | Capture live macro evidence Open Screenshot / Reveal Report | `live-macro-evidence-open-reveal.mov` + `.md` sidecar | Proves failed run evidence path before recording bundle failure comparisons |
| S0-3 | Capture branch evidence real-run consistency | `live-branch-evidence-consistency.mov` + `.md` sidecar | Proves durable branch payload is not only fixture-correct |
| S0-4 | Capture drag/reorder WYSIWYG mutation | `live-task-reorder-wysiwyg.mov` or `live-drag-link-wysiwyg.mov` + `.md` sidecar | Gives S3 a baseline for future recording review interactions |
| S0-5 | Draft template/baseline preview refs request to S1 | [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md) | Lets S1 design bundle refs without guessing UI evidence needs |

Recommended order: S0-5 can run in parallel with S1 now; S0-1 and S0-3 are the highest-risk live evidence gates.

## 4. Interface Request To S1

S0 requests S1 to reserve value-model support for source-frame/runtime-sample preview comparisons. The detailed request lives in [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md).

Minimum S1 fields S0 needs:

- stable recording/source ids: `recordingID`, `frameID`, optional `eventID`, optional `surfaceID`
- safe relative artifact refs for source template/baseline and runtime sample/crop
- crop/search bounds plus coordinate space and image size
- ref kind: OCR region, image template, region baseline, pixel sample, runtime display sample, runtime watched-region sample
- digest or content identity for stale/missing asset diagnostics
- comparison payload: score, threshold, matcher kind/version, outcome, fallback reason, optional diff artifact ref

S0 accepts S1 defining names differently, but the semantics above must survive round trip through bundle fixtures, run evidence and UI presenter results.

## 5. Product Evidence Capture Rules

Every S0 live artifact sidecar must include:

- capture date and commit/worktree note
- App build/run source
- fixture or real workflow package used
- exact user action
- checklist item proved
- known gaps
- whether artifacts came from fixture files or App Support live paths

Suggested filenames under `docs/workflow-page-productization/product-evidence/`:

- `live-visual-diagnostics-open-reveal.mov`
- `live-macro-evidence-open-reveal.mov`
- `live-branch-evidence-consistency.mov`
- `live-task-reorder-wysiwyg.mov`
- `live-drag-link-wysiwyg.mov`

If a capture is impossible in a given environment, S0 should leave the checklist unchecked and record the blocker in this file instead of replacing live evidence with another fixture.

## 6. Live Capture Runbook

Fixture refresh, when UI changes but live evidence is not being claimed:

```bash
swift run SparkleRecorder workflow product-evidence snapshot visual-diagnostics-drill-in
swift run SparkleRecorder workflow product-evidence snapshot branch-evidence
swift run SparkleRecorder workflow product-evidence snapshot failed-run-detail
swift run SparkleRecorder workflow product-evidence snapshot task-reorder-authoring
```

Live capture, when closing S0 gates:

1. Build or launch the same App binary being reviewed.
2. Use a real repository/workflow package, not only `AutomationRunState.ownerCFixture`.
3. Trigger the relevant workflow or authoring action.
4. Capture the full App surface and the external Open/Reveal result when relevant.
5. Save the video under `docs/workflow-page-productization/product-evidence/`.
6. Add a same-name `.md` sidecar using the capture rules above.
7. Update this workstream, `06-current-work-and-next-tasks.md`, product evidence README and `acceptance-checklist.md`.

S0 should prefer short clips over long demos: the artifact only needs to prove the exact gate.

## 7. S0 Acceptance Gates

S0 can call Workflow evidence closure complete only when:

- live visual diagnostics Open/Reveal is recorded from the installed App or a local App build
- live macro failure evidence Open Screenshot / Reveal Report is recorded
- live branch evidence consistency is recorded
- at least one real authoring WYSIWYG mutation recording exists for drag/reorder or drag-link
- template/baseline preview refs have an accepted S1 contract note
- `06-current-work-and-next-tasks.md`, `08-parallel-workstreams.md`, product evidence README and semantic checklist agree about what is done versus fixture-only

Current status: not complete. The fixture foundation is strong, but live evidence and S1 preview-ref acceptance remain open.

## 8. Implementation Log

- 2026-07-06: Created S0 workstream file and documented S0/S1 interface request path. No live evidence item was marked complete.

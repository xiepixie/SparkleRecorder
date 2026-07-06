# Workflow Product Evidence

状态：验收目录；idle/running/drag-link/task-reorder/failed-run/preview-unavailable/branch/visual diagnostics/template-baseline preview refs/semantic review timeline fixture PNG 已补齐，真实 task reorder live clip 已补齐，visual diagnostics/macro evidence/branch consistency live capture 和真实 Macro Review 录屏仍缺。
Owner：Owner 2, Product UI And Workflow UX

Semantic recording S0 现在使用本目录作为 Workflow Evidence Closure 的产品证据落点。S0 当前工作台在 `docs/semantic-recording-ai/workstreams/s0-workflow-evidence.md`；live-product 条目未录到真实 App 截图/录屏前不能在 semantic checklist 中打勾。

本目录用于收集 Workflow 页面产品验收截图和短录屏。它不是设计稿目录，也不是展示用素材目录；它是 checklist 能不能打勾的证据目录。

## Required Artifact Set

每个可声明为产品级完成的 Workflow UI slice 至少要提交以下三类 artifact：

| Artifact | Required State | Must Prove |
| --- | --- | --- |
| `idle-workflow.png` | 静止态 | 页面主视觉是 workflow data、graph、timeline、run evidence；普通控件退到背景，不靠大面积高饱和底色撑界面。 |
| `drag-link-authoring.png` / `.mov` / `.mp4` | 拉线态 | Connector drag link、target preview、trigger choice 与真实连线结果一致。 |
| `task-reorder-authoring.png` / `.mov` / `.mp4` | 任务重排态 | Existing task reorder 的 moving row、insertion line、非拖拽上下移动按钮和提交后的 graph/list position 语义一致。 |
| `running-workflow.png` 或 `running-workflow.mov` | 运行态 | 当前 task、触发边、等待资源/条件、timeout/retry 或 failure evidence 在 graph、timeline、inspector 中由同一 projection 表达，不互相矛盾。 |

可选但推荐：

| Artifact | Required State | Must Prove |
| --- | --- | --- |
| `failed-run-detail.png` / `failed-run-preview-unavailable.png` | 失败排查态 | Run Detail 能显示 per-run evidence binding、report summary、screenshot preview 或 preview unavailable fallback，并清楚告诉用户下一步检查什么。 |
| `visual-diagnostics-drill-in.png` | 视觉条件排查态 | 一次 OCR/visual condition 运行能展示 watched region、last sample、threshold/score、region crop/template/baseline 或 pixel sample，并能通过 Run Detail 安全预览、打开或 Reveal artifact。当前已有 `AutomationTaskRun.conditionEvidence`、live sample artifact refs 和 `AutomationConditionEvidenceArtifactPresenter` first pass；fixture artifact 可证明 UI 接线，真实 live capture 录屏仍是后续证据。 |
| `branch-evidence-drill-in.png` | 分支决策排查态 | 一次 run 的 Then/Else/Timeout decision 能在 Run Detail 中解释 source outcome、dependency trigger、target run、delay、join policy 和 skipped/triggered reason。当前 fixture artifact 已补齐。 |
| `template-baseline-preview-refs.png` | 语义录制 preview-ref 态 | S1 接受的 source reference、runtime sample、preview comparison 合同能以用户可读的 Source / Runtime / Decision 三段式渲染。当前 artifact 是 fixture evidence；真正 Review UI 接线仍属 S3。 |
| `semantic-review-timeline.png` | 语义录制 Review timeline fixture 态 | S3 Review UI 能展示 event row -> before/after frame navigation、selected-frame OCR/source region overlay、frame-to-condition draft patch / Draft Preview affordance、source/runtime decision、suggestion evidence refs、S4-aligned Review Actions contract 和 Accept Patch / Reject review controls。当前 artifact 是 fixture evidence；Run Detail/live bundle presenter/Draft Preview handoff、pixel color picking、suggestion review 和 package-local materialization first passes 已在代码/fixture 证据中完成，但 live frame-to-condition clip、自动 run->bundle 绑定和 installed-app product evidence 仍属后续验收。 |
| `semantic-review-stored-bundle.png` | 语义录制 stored bundle Review 态 | S3 Review UI 能从落盘 manifest、PNG artifact refs 和 artifact status map 渲染 Available source/runtime/diff thumbnails、候选 artifact 操作和 review-only Draft Patch。当前 artifact 是 stored fixture evidence，不包含 fake `.mov`；真实 installed-app live bundle 录屏仍属后续验收。 |
| `semantic-review-missing-artifacts.png` | 语义录制 missing artifact Review 态 | S3 Review UI 能在 stored bundle 中 frame PNG 仍存在、source/runtime/diff/candidate artifacts 被 retention 或 sidecar 缺失影响时，把证据 ref 显示为 `Missing file`，解释 Open/Reveal 不可用，而不是静默隐藏证据。当前 artifact 是 stored fixture evidence；真实 retention/live capture 录屏仍属后续验收。 |
| `semantic-review-pixel-color.png` | 语义录制 pixel Review fixture 态 | S3 Review UI 能展示 `pixelMatched` candidate、颜色选择器、reviewed target color 和 review-only Draft Patch 状态。当前 artifact 是 fixture evidence；真实 installed-app pixel sample 录屏和 confirmed import 仍属后续验收。 |
| `semantic-review-materialized-actions.png` | 语义录制 materialized action evidence 态 | S3 Review UI 能在 Draft Preview handoff 后把 `review.previewDraft` / `review.importDraft` action rows 从 source artifact 对齐到 package-local artifact path、SHA-256、draft task/condition 和 visual asset key。当前 artifact 是 fixture evidence；真实 installed-app confirmed import 录屏仍属后续验收。 |

## Capture Rules

每个 artifact 附近应保留一段同名 `.md` 说明，至少包含：

- Capture date and local commit/worktree note.
- Fixture or workflow package used.
- Window size or screen scale.
- What the user action was.
- Which checklist item this proves.
- Known gaps that remain after the artifact.

截图或录屏必须来自真实 App 状态或稳定 fixture。不能用静态 mock 图片、只读设计稿、或手工拼接 UI 当验收证据。

## Current Missing Evidence

- idle screenshot: present as `idle-workflow.png` with `idle-workflow.md`.
- drag/link evidence: connector-link fixture screenshot present as `drag-link-authoring.png` with `drag-link-authoring.md`.
- task reorder evidence: existing-task reorder fixture screenshot present as `task-reorder-authoring.png` with `task-reorder-authoring.md`; real task reorder recording is present as `live-task-reorder-wysiwyg.mov` with `live-task-reorder-wysiwyg.md`.
- running/waiting screenshot: present as `running-workflow.png` with `running-workflow.md`.
- failed-run detail artifact: present as `failed-run-detail.png` with `failed-run-detail.md`. The fixture writes per-run `manifest.json`, `report.json`, and `failure.png` under `fixture-macros/.../runs/<evidenceID>/` and proves verified binding, report summary, file action buttons/feedback, failed event guidance, and inline failure screenshot preview.
- failed-run preview-unavailable artifact: present as `failed-run-preview-unavailable.png` with `failed-run-preview-unavailable.md`. The fixture writes an unreadable `failure.png` under `fixture-macros-preview-unavailable/.../runs/<evidenceID>/` and proves the report/manifest remain visible while screenshot preview falls back to `Screenshot preview unavailable`. Open/Reveal recording remains future evidence.
- visual diagnostics drill-in artifact: present as `visual-diagnostics-drill-in.png` with `visual-diagnostics-drill-in.md`. Runtime now persists `AutomationTaskRun.conditionEvidence` for OCR/visual condition runs, including observed summary, sample count, watched region, score/threshold when available, diagnostic fields, and optional last-sample / watched-region image artifact refs. The fixture screenshot proves last-sample and watched-region image preview loading through `AutomationConditionEvidenceArtifactPresenter`, plus Open/Reveal artifact affordances and inline action feedback; live capture recording and real Open/Reveal interaction recording remain future evidence.
- branch evidence drill-in artifact: present as `branch-evidence-drill-in.png` with `branch-evidence-drill-in.md`.
- template/baseline preview refs artifact: present as `template-baseline-preview-refs.png` with `template-baseline-preview-refs.md`. It renders `SemanticRecordingFixture.checkoutBundle` source reference, runtime sample, preview comparison, related template ref, matcher score/threshold, reason and traceable ids in one fixture surface. It does not claim live Review UI completion.
- semantic review timeline artifact: present as `semantic-review-timeline.png` with `semantic-review-timeline.md`. It renders `SemanticRecordingReviewProjection` from `SemanticRecordingFixture.checkoutBundle`, including before/after frame ids, selected-frame OCR overlay, source/runtime comparison, frame-to-condition Save Patch / Preview Draft affordances, candidate-level `review.draftSelection`, suggestion evidence refs, S4-aligned `review.acceptSuggestion` / `review.rejectSuggestion` / `review.clearDecision` action contract, accepted-decision explanation and Accept Patch / Reject controls. It does not claim live installed-app frame-to-condition completion.
- semantic review stored bundle artifact: present as `semantic-review-stored-bundle.png` with `semantic-review-stored-bundle.md`. It writes a checkout semantic recording manifest plus PNG refs under `fixture-semantic-review-stored-bundles/<recording-id>/` and renders Bundle Health, file-backed Available source/runtime/diff thumbnails and candidate-level `review.draftCandidate` in Review. It does not claim live installed-app capture or fake live video.
- semantic review missing artifacts artifact: present as `semantic-review-missing-artifacts.png` with `semantic-review-missing-artifacts.md`. It writes a checkout semantic recording manifest and frame PNGs while omitting source/runtime/diff/candidate files, proving Bundle Health counts missing refs, Review keeps safe evidence refs visible as `Missing file`, and Open/Reveal unavailability does not change Review action semantics. It does not claim live retention deletion or installed-app capture.
- semantic review pixel color artifact: present as `semantic-review-pixel-color.png` with `semantic-review-pixel-color.md`. It layers a deterministic pixel sample on the checkout fixture and proves the Review color picker plus `pixelMatched` staged draft patch before Draft Preview import. It does not claim live installed-app pixel sampling.
- semantic review materialized actions artifact: present as `semantic-review-materialized-actions.png` with `semantic-review-materialized-actions.md`. It renders the real Review UI after a fixture Draft Preview handoff has materialized a Review-generated visual asset into package-local refs, proving action rows include source artifact, package artifact, digest and draft task/condition evidence. It does not claim live installed-app import completion.
- in-app readiness: Run Detail can show condition diagnostics directly from `AutomationTaskRun.conditionEvidence`; evidence readiness marks visual diagnostics durable when present. Branch evidence is shown as durable when `AutomationTaskRun.branchEvidence` exists, including trigger, target run, delay, join policy, dependency ID, and reason; older runs can still use projection fallback.

S0 live-product evidence still expected. Each `.mov` / `.mp4` must be a non-empty real recording in a supported video container; empty placeholder files or non-video files renamed to `.mov` / `.mp4` are reported as undersized/invalid and do not satisfy strict audit. The paired sidecar must name exactly one accepted `Clip file:` candidate, must describe `Evidence source:` as live recording/capture, not fixture/mock/synthetic evidence, and must keep `Checklist item:` tied to the matching live gate title and id:

- `live-visual-diagnostics-open-reveal.mov` or `.mp4` with sidecar `.md`
- `live-macro-evidence-open-reveal.mov` or `.mp4` with sidecar `.md`
- `live-branch-evidence-consistency.mov` or `.mp4` with sidecar `.md`
- `live-task-reorder-wysiwyg.mov` / `.mp4` or `live-drag-link-wysiwyg.mov` / `.mp4` with sidecar `.md` (task reorder option is present and satisfies the authoring live gate)
- S3 Review UI artifact showing the same source reference, runtime sample and decision/comparison inside the real Macro Review / Run Detail flow.

## Audit Command

S0 can check this directory without manually scanning filenames:

```bash
swift run SparkleRecorder workflow product-evidence capture-plan
swift run SparkleRecorder workflow product-evidence capture-plan --json
swift run SparkleRecorder workflow product-evidence prepare-live-capture
swift run SparkleRecorder workflow product-evidence prepare-live-capture --json
swift run SparkleRecorder workflow product-evidence complete-sidecar live-visual-diagnostics-open-reveal \
  --clip live-visual-diagnostics-open-reveal.mov \
  --capture-date 2026-07-06 \
  --worktree-note "main at <commit>, dirty only live product evidence clip" \
  --app-build "local swift run SparkleRecorder or installed app path" \
  --workflow "workflow id/name and package source" \
  --user-action "exact interaction captured in the clip" \
  --known-gaps "none for this gate, or describe remaining limitation" \
  --evidence-source "live App recording"
swift run SparkleRecorder workflow product-evidence audit --json
swift run SparkleRecorder workflow product-evidence audit --require-live --json
```

`capture-plan` is the operator/agent checklist for closing S0: it lists missing live gates, accepted clip filenames, sidecar template commands, post-recording `complete-sidecar` command templates, missing or invalid sidecar labels, undersized live clips and invalid clip containers. `prepare-live-capture` materializes the missing sidecar drafts before recording; it preserves existing notes by default, supports `--overwrite` for regeneration, and intentionally leaves placeholders that strict audit rejects until the real clip is captured and reviewed. `complete-sidecar` fills one reviewed sidecar through typed CLI fields, validates that `--clip` is an accepted filename for that gate, and still reports the gate open when the clip file is absent, empty, not a supported video container, mismatched in `Clip file:`, copied from another `Checklist item:`, or described as fixture/mock evidence. The normal audit reports fixture/live status and exits 0. The strict `--require-live` mode exits 1 until every S0 live-product artifact exists as a non-empty supported `.mov` / `.mp4` and the paired sidecar includes the required live capture labels: `Capture date:`, `Worktree note:`, `App build/run source:`, `Workflow/package:`, `User action:`, `Checklist item:`, `Known gaps:`, `Evidence source:`, and `Clip file:`. Current smoke result is 10/13 required items present: all fixture artifacts are present, the authoring task-reorder live gate is satisfied, and the three remaining live gates still miss visual diagnostics, macro evidence and branch consistency clips. The pure audit, capture-plan, sidecar-draft, sidecar-completion-command, sidecar-completion, empty-clip rejection, clip-container rejection, checklist-item validation, live-source validation and clip-match semantics are covered by `AutomationProductEvidenceAuditTests`.

Generate a live sidecar template before saving a capture:

```bash
swift run SparkleRecorder workflow product-evidence sidecar-template live-visual-diagnostics-open-reveal
swift run SparkleRecorder workflow product-evidence sidecar-template live-macro-evidence-open-reveal
swift run SparkleRecorder workflow product-evidence sidecar-template live-branch-evidence-consistency
swift run SparkleRecorder workflow product-evidence sidecar-template live-authoring-wysiwyg --sidecar live-drag-link-wysiwyg.md
swift run SparkleRecorder workflow product-evidence sidecar-template live-authoring-wysiwyg --sidecar live-task-reorder-wysiwyg.md
```

Fill every angle-bracket placeholder before running strict audit; placeholders are treated as incomplete sidecar content.

## Acceptance Boundary

`AutomationTaskRun.branchEvidence` is now the durable source for branch decisions created by the reducer and persisted in run history. `AutomationDependencyEdgeProjection.branchDecision` may still provide fallback for older runs. Product completion now has a fixture screenshot proving that selected Run Detail explains why a dependency fired or skipped.

`AutomationTaskRun.conditionEvidence` is now the durable source for OCR/visual condition diagnostics created by the evaluator/effect runner and persisted in run history. Live evaluators can also save last-sample and watched-region PNGs under `AutomationEvidence/<runID>/...` and persist relative artifact refs. UI loads those refs through `AutomationConditionEvidenceArtifactPresenter`, not by reconstructing paths in SwiftUI. Product completion now has a fixture screenshot proving that selected Run Detail explains watched region, last sample/crop, score/threshold, artifact image previews, and artifact action feedback; a live capture recording that proves real Open/Reveal behavior is still future evidence.

Run macro package evidence is loaded through `AutomationTaskRunEvidencePresenter`. Product completion now has fixture screenshots proving the per-run evidence path: `runs/<evidenceID>/manifest.json`, `report.json`, and `failure.png` bind to the selected failed run, render report summary plus inline screenshot preview, keep Reveal Report / Open Screenshot actions close to the verified binding, report action success/failure back in the Run Detail surface, and degrade to preview-unavailable copy when the screenshot file exists but cannot be decoded. Live playback failure recording and Open Screenshot / Reveal Report interaction recording remain future evidence.

Semantic Review Run Target evidence is present as `semantic-review-run-target.png` with `semantic-review-run-target.md`. It renders the opened Macro Review sheet with `Run Target` context from failed run evidence, proving selected event/frame provenance is visible before Teach/Draft actions. It does not claim live per-run semantic bundle metadata.

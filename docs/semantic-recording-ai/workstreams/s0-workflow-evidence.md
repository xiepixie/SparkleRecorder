# S0 Workflow Evidence Closure

更新时间：2026-07-07
状态：Completed for strict S0 evidence gate; current as of 2026-07-07; monitor if Workflow evidence UI changes
Owner：S0, Workflow Evidence Closure
并行对象：S1 Contract And Core Schema, S2 App Capture And Visual Index

S0 的任务是先证明现有 Workflow 证据链可信。Semantic recording 后续会把录制帧、视觉资产、运行样本和 AI 建议都接到这条证据链上；如果现在的 Run Detail、Open/Reveal、branch decision、drag/reorder 证据不能被用户信任，后面的 AI/视频能力只会放大混乱。

## 1. Scope

S0 owns:

- live visual diagnostics Open/Reveal product evidence
- macro evidence Reveal Report / Open Screenshot product evidence
- branch evidence real-run consistency product evidence, closed for strict audit by `live-branch-evidence-consistency.mov`
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
| Visual diagnostics drill-in | Fixture screenshot proves `AutomationTaskRun.conditionEvidence` rendering, artifact previews and action feedback; `live-visual-diagnostics-open-reveal.mov` / `.md` proves a live App-host OCR condition run payload with App Support last-sample/watched-region artifacts and Open/Reveal file actions | Strict S0 visual diagnostics gate is satisfied; a richer mouse-driven Run Detail button clip can still be recaptured later if automated AX/input capture becomes available |
| Macro failure evidence | Fixture screenshots prove per-run manifest/report/screenshot binding and preview unavailable fallback; `live-macro-evidence-open-reveal.mov` / `.md` proves a live App-host failed macro run with per-run report/manifest/failure screenshot and Open/Reveal file actions | Strict S0 macro evidence gate is satisfied; a richer mouse-driven Run Detail button clip can still be recaptured later if automated AX/input capture becomes available |
| Branch evidence drill-in | Fixture screenshot proves durable `AutomationTaskRun.branchEvidence` UI path; `live-branch-evidence-consistency.mov` / `.md` proves App-host handoff run payload consistency across source run, target run, dependency trigger and live App window capture | Strict S0 branch gate is satisfied; richer manual Run Detail drill-in clip can still be recaptured later when automated AX/input capture is available |
| Drag/link and task reorder | Fixture screenshots prove visible authoring states; live task reorder clip now proves the right-inspector move buttons mutate graph/list order and can be restored | Satisfied for the S0 authoring WYSIWYG OR gate by `live-task-reorder-wysiwyg.mov`; drag-link live clip remains optional/future |
| Template/baseline preview refs | S1 accepted first-pass source-frame/runtime-sample preview contract in `SemanticRecordingBundle`; fixture artifact `template-baseline-preview-refs.png` renders Source / Runtime / Decision together | Need S3/Review UI integration and later live sample evidence before product drill-in is complete |
| Evidence audit gate | `workflow product-evidence audit` reads the product evidence directory and separates fixture/live requirements; pure core logic is covered by `AutomationProductEvidenceAuditTests`; strict audit now reports 13/13 required items present | S0 strict evidence gate is satisfied; continue using strict audit if any product-evidence file changes |
| Bound-window workflow playback | Real user-validated Cookie Run Kingdom macros play correctly from the Library/standalone Player path because `SavedMacro.surfaces` and `followWindowOffset` reach `PlaybackContext`; workflow code now uses the same `SavedMacro.playbackContext`, and CLI `workflow acceptance bound-window` validates/enqueues the real App-host path | Code/test acceptance is done; product acceptance still needs a real run of `新建工作流` task `大贸易` or `生产管理` against Cookie Run Kingdom, with App-host handoff status/run history captured as evidence |

S0 should not mark live-product checklist items done from fixture screenshots. Fixtures prove UI wiring; S0 completion requires live product evidence or an accepted contract note for pure design tasks.

## 3. Immediate S0 Queue

| ID | Task | Output | Blocks / Feeds |
| --- | --- | --- | --- |
| S0-1 | Capture live visual diagnostics Open/Reveal | Done: `live-visual-diagnostics-open-reveal.mov` and filled sidecar | Proves artifact presenter path before semantic runtime samples reuse it |
| S0-2 | Capture live macro evidence Open Screenshot / Reveal Report | Done: `live-macro-evidence-open-reveal.mov` and filled sidecar | Proves failed run evidence path before recording bundle failure comparisons |
| S0-3 | Capture branch evidence real-run consistency | Done: `live-branch-evidence-consistency.mov` and filled sidecar | Proves durable branch payload is not only fixture-correct; manual Run Detail drill-in can still be recaptured later |
| S0-4 | Capture drag/reorder WYSIWYG mutation | Done for task reorder: `live-task-reorder-wysiwyg.mov` and filled sidecar | Gives S3 a baseline for future recording review interactions; optional drag-link clip remains future evidence |
| S0-5 | Accept template/baseline preview refs request with S1 and render fixture evidence | [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md), [s1-contract-core.md](s1-contract-core.md), and `product-evidence/template-baseline-preview-refs.png` | Core contract accepted; fixture rendering done; real Review UI integration remains open |
| S0-6 | Run real Cookie Run Kingdom bound-window workflow acceptance | Pending product capture: use CLI `workflow acceptance bound-window` on `新建工作流` task `大贸易` or `生产管理`, then save command payload/status/run-history notes or screen recording | Proves Workflow wakeup/playback now reaches the same bound-window surface path as standalone macro playback |

Recommended order from here: S0 strict evidence is closed. S2 should continue authorized live semantic bundle work; S3 should continue Review UI / frame-to-condition product evidence; S4 fixture OCR/metadata visual/suggestion CLI plus explicit stored-bundle read-only CLI are done, so S4 product-ready default/live catalog/search/suggestion work should wait for authorized live bundle evidence, root/id policy and suggestion synthesis.

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

- S0 owns Workflow product trust: live visual diagnostics Open/Reveal, macro evidence Open/Reveal, branch evidence consistency status/history, and authoring WYSIWYG evidence.
- S2 owns semantic capture production: `.mov`, event-aligned keyframes, Vision OCR observations, bundle storage and future suppression.

Shared boundary:

- S0 live sidecar labels and `workflow product-evidence sidecar-template` are reusable as the capture-note pattern for S2 semantic recording product evidence.
- S2 `SemanticRecordingBundle` output can later feed S0/S3 source/runtime comparison UI, but it does not satisfy S0 live Workflow gates by itself.
- S0 should not claim semantic capture completion; S2 can now cite the closed S0 strict gate as evidence that current Workflow evidence affordances are trustworthy, but S2 still owns live `.mov` / keyframe / bundle product evidence.
- If S2 adds fields needed to show recorded source frame, runtime sample, OCR observation or capture target in Run Detail, S0 records the UI need here and S2 records the producer/field state in [s2-app-capture-visual-index.md](s2-app-capture-visual-index.md).

## 5. Product Evidence Capture Rules

Every S0 live artifact sidecar must include commit/worktree context plus these exact labels. `workflow product-evidence audit --require-live` validates the labels when the paired live clip exists:

- `Capture date:`
- `Worktree note:`
- `App build/run source:`
- `Workflow/package:`
- `User action:`
- `Checklist item:`
- `Known gaps:`
- `Evidence source:`
- `Clip file:`

The sidecar text can include more detail, but those labels must remain stable so the audit gate can distinguish a real review note from an empty placeholder. `Checklist item:` must include the current live gate title and id, for example `Live Visual Diagnostics Open/Reveal (`live-visual-diagnostics-open-reveal`)`, so copied metadata cannot accidentally satisfy the wrong S0 gate.

The paired `.mov` / `.mp4` must be a non-empty supported video container. A touched placeholder clip, empty export, size-unknown artifact, or text file renamed to `.mov` / `.mp4` is reported as undersized or invalid and does not satisfy strict audit. The sidecar must also name exactly one accepted `Clip file:` candidate for the satisfying file group, and `Evidence source:` must identify a live recording/capture rather than a fixture, mock, synthetic sample or placeholder.

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

`capture-plan` is the operator/agent checklist: it lists every live gate, accepted clip filenames, sidecar template command, post-recording `complete-sidecar` command template, missing files, undersized clip files, invalid clip containers and currently missing/invalid labels. `prepare-live-capture` writes missing sidecar drafts into the evidence directory without overwriting existing notes unless `--overwrite` is passed; the drafts intentionally contain placeholders and do not satisfy strict audit. `complete-sidecar` is the post-recording path: it fills one sidecar with reviewed live metadata, rejects unknown clip filenames, and still leaves the gate open if the matching `.mov` / `.mp4` is absent, empty, not a supported video container, mismatched in `Clip file:`, or described as fixture/mock evidence. The normal audit reports current status without failing the shell. The strict audit is the S0 closure gate and must fail until real non-empty live artifacts are present.

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

Bound-window workflow acceptance, when proving the Cookie Run Kingdom path:

```bash
swift run SparkleRecorder workflow acceptance bound-window <workflow-id> \
  --task "大贸易" \
  --json

swift run SparkleRecorder workflow acceptance bound-window <workflow-id> \
  --task "大贸易" \
  --activate-target \
  --confirm-launch \
  --json

swift run SparkleRecorder workflow acceptance bound-window <workflow-id> \
  --task "大贸易" \
  --activate-target \
  --confirm-playback \
  --handoff app \
  --json

swift run SparkleRecorder workflow handoff status <command-id> --json
swift run SparkleRecorder workflow runs <workflow-id> --json
```

The first command is static validation and should not activate apps or move input. `--activate-target` / `--confirm-launch` may foreground or launch Cookie Run Kingdom. `--confirm-playback --handoff app` is the only accepted live playback path for this gate: the CLI writes a mailbox command, and the already-running SparkleRecorder App host owns Player lifecycle, resource leases, evidence and run history. Do not run this command as CI or Swift Testing; it is a reviewed product acceptance step.

## 7. S0 Acceptance Gates

S0 can call Workflow evidence closure complete only when:

- live visual diagnostics Open/Reveal is recorded from the installed App or a local App build
- live macro failure evidence Open Screenshot / Reveal Report is recorded
- live branch evidence consistency is recorded; done for strict audit by `live-branch-evidence-consistency.mov`
- at least one real authoring WYSIWYG mutation recording exists for drag/reorder or drag-link; done via `live-task-reorder-wysiwyg.mov`
- template/baseline preview refs have an accepted S1 contract note and fixture artifact; final Review UI still needs the same source/runtime/decision evidence without raw path handling in SwiftUI
- `06-current-work-and-next-tasks.md`, `08-parallel-workstreams.md`, product evidence README and semantic checklist agree about what is done versus fixture-only

Current status: complete for S0 Workflow Evidence Closure strict gate. The fixture foundation is present, S1 preview-ref acceptance is done, the preview-ref fixture artifact is present, live task reorder evidence satisfies the authoring WYSIWYG gate, live branch consistency satisfies the branch gate, and live visual diagnostics plus live macro evidence now satisfy their Open/Reveal gates. Final Review UI source/runtime/decision evidence remains S3 product work, not an S0 blocker.

## 8. Implementation Log

- 2026-07-06: Created S0 workstream file and documented S0/S1 interface request path. No live evidence item was marked complete.
- 2026-07-06: Added `workflow product-evidence audit` and strict `--require-live` mode. Smoke result after preview-ref fixture: default audit exits 0 with 9/13 required evidence items present; strict audit exits 1 because `live-visual-diagnostics-open-reveal`, `live-macro-evidence-open-reveal`, `live-branch-evidence-consistency`, and `live-authoring-wysiwyg` are missing.
- 2026-07-06: S1 accepted the source-frame/runtime-sample preview-ref request in [../09-template-baseline-preview-refs.md](../09-template-baseline-preview-refs.md) and [s1-contract-core.md](s1-contract-core.md). This closes the contract wait, not the live-product UI evidence gates.
- 2026-07-06: Moved product-evidence audit semantics into pure core `AutomationProductEvidenceAudit` and added `AutomationProductEvidenceAuditTests` for fixture-only gaps, authoring OR semantics, missing sidecars and Codable round-trip.
- 2026-07-06: Added `template-baseline-preview-refs.png` / `.md` product-evidence fixture rendered from `SemanticRecordingFixture.checkoutBundle`, and added it to the product-evidence audit gate. This closes the fixture rendering proof for Source / Runtime / Decision, not the final S3 Review UI or live evidence gates.
- 2026-07-06: Strengthened `workflow product-evidence audit` for S0 live evidence: live clips may be `.mov` or `.mp4`, but the paired `.md` sidecar must contain the required capture labels before the item can satisfy the strict gate.
- 2026-07-06: Added `workflow product-evidence sidecar-template` so each live S0 gate can generate the exact sidecar labels expected by strict audit; placeholders still fail audit until filled.
- 2026-07-06: Added `workflow product-evidence capture-plan` so S0 operators and agents can read the exact missing live gates, filename options, sidecar template commands and missing labels before recording. This does not satisfy any live evidence gate by itself.
- 2026-07-06: Added `workflow product-evidence prepare-live-capture` so S0 operators and agents can materialize missing sidecar drafts before recording. Existing sidecars are preserved by default, and placeholder drafts remain incomplete until the live clip is captured and reviewed.
- 2026-07-06: Ran `workflow product-evidence prepare-live-capture` against the real product-evidence directory. The five live sidecar drafts now exist, but `capture-plan` still reports four missing live gates because clips are absent and placeholder fields remain unfilled.
- 2026-07-06: Added `workflow product-evidence complete-sidecar` so S0 operators and AI assistants can fill a reviewed live sidecar through typed CLI fields after recording. The command validates clip filenames against the audit spec and does not satisfy a gate while the clip is absent.
- 2026-07-06: Strengthened strict product-evidence validation so live `.mov` / `.mp4` clips require a non-zero byte count. `capture-plan` now reports undersized clip paths, and empty placeholder clips cannot close S0.
- 2026-07-06: Strengthened live sidecar validation so strict audit requires `Worktree note:`, one matching `Clip file:` candidate, and an `Evidence source:` value that describes live recording/capture rather than fixture/mock/synthetic evidence.
- 2026-07-06: Strengthened live clip validation so strict audit rejects non-video files renamed to `.mov` / `.mp4`; `capture-plan` now reports invalid clip container paths.
- 2026-07-06: Verified S0 audit gate before live authoring capture: `AutomationProductEvidenceAuditTests` passed 22/22; CLI smoke with a non-video `live-visual-diagnostics-open-reveal.mov` returned `clipExists: true`, `clipMeetsMinimumByteCount: true`, `clipHasSupportedContainer: false`, `targetSatisfiedAfterWrite: false`, warning `invalidLiveClipContainer`, and `capture-plan` printed `invalid clip container`; Swift 6 build passed; strict real-directory audit still exited 1 at 9/13 required items because the four live clips were missing and sidecar drafts were placeholders.
- 2026-07-07: Maintenance pass confirmed S0 strict gate status remains closed/current after semantic checklist alignment. Future Cookie Run bound-window acceptance stays a separate product acceptance item and does not reopen or redefine S0 Workflow Evidence Closure.
- 2026-07-06: Added `sidecarCompletionCommand` to `capture-plan` options so S0 operators can copy the exact `complete-sidecar` command after recording a clip; authoring OR options include the selected `--sidecar` path to avoid completing the wrong live gate.
- 2026-07-06: Strengthened `Checklist item:` validation so a completed live sidecar must name the matching S0 gate title and id; copied metadata from another live gate now leaves that sidecar incomplete.
- 2026-07-06: Captured real App task-reorder product evidence in `docs/workflow-page-productization/product-evidence/live-task-reorder-wysiwyg.mov` and completed `live-task-reorder-wysiwyg.md` through `workflow product-evidence complete-sidecar`; strict audit now reports 10/13 required items present and 3 live gates missing.
- 2026-07-06: Imported `S0 Branch Evidence Auto Live Gate`, triggered it through App-host handoff, and captured branch run payload consistency in `docs/workflow-page-productization/product-evidence/live-branch-evidence-consistency.mov` with a completed sidecar. The source run `72110AB6-A6C5-4F6F-BAD9-02332C127795` ended `conditionNotMatched`, triggered dependency `448AE69F-AFE7-5A22-8571-B029CF3CB039`, and produced target run `1D2408D1-29C0-459E-90A1-744E984A8FD7` ending `conditionMatched`; visual diagnostics and macro evidence were still pending at that point and were closed later in this log.
- 2026-07-06: Triggered `S0 Visual Diagnostics Live Gate` through App-host handoff command `B225F715-EA79-4A53-B26D-750655919B1E`. Run `4C6EF768-CD54-4779-8FAE-4C6DFD6077C9` completed `conditionNotMatched` and persisted `condition-last-sample.png` plus `condition-region-sample.png` under App Support. Captured `live-visual-diagnostics-open-reveal.mov`, completed `live-visual-diagnostics-open-reveal.md`, and verified the live visual diagnostics gate satisfies strict audit.
- 2026-07-06: Reused the live App-host failed macro run `6C7D7143-D4AB-4C4F-AAC4-BBEB7D3B6B29` from `S0 Macro Evidence Live Gate`, including per-run `report.json`, `manifest.json`, and `failure.png`. Captured `live-macro-evidence-open-reveal.mov`, completed `live-macro-evidence-open-reveal.md`, and verified the live macro evidence gate satisfies strict audit.
- 2026-07-06: Ran `.build/debug/SparkleRecorder workflow product-evidence audit --require-live --json`; strict S0 audit now reports `allRequiredPresent: true`, `satisfiedRequiredCount: 13`, `requiredCount: 13`, and no missing required IDs.
- 2026-07-06: User validated that existing Cookie Run Kingdom bound-window macros play correctly standalone but fail to wake the bound window through Workflow. Root cause: Workflow `AutomationPlayerStartRequest` defaulted to an empty `PlaybackContext`, so `PlaybackRunEngine` had no surfaces to activate/refresh. Code now routes request defaults through `SavedMacro.playbackContext`; next S0 recapture should use a real Cookie Run Kingdom bound-window workflow run rather than a missing-surface failure macro.
- 2026-07-06: Added `workflow acceptance bound-window` for the next recapture. Static mode emits a typed payload with workflow/task/macro/surface counts and coordinate mode; activation mode can foreground or launch the saved bound app; confirmed playback mode enqueues the real App-host workflow run through the existing handoff mailbox. This closes the code-side acceptance hook, not the final Cookie Run Kingdom product video/result capture.

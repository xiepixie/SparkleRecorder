# Current Work And Next Tasks

更新时间：2026-07-06
状态：下一阶段执行账本
Owner：Recording / Workflow Evidence / AI CLI shared planning

本文把 `semantic-recording-ai/` 的愿景转成当前可执行任务。它的作用不是扩大范围，而是防止方向跑偏：先让现有 Workflow 证据可信，再做最小 semantic recording 竖切，最后再谈 AI 组合和 App Knowledge。

## 1. Current Work Status

当前项目已经有三块底座，可以支撑 semantic recording，但还不能直接宣称“AI 录制理解”完成。

| Area | Current State | Evidence | Gap |
| --- | --- | --- | --- |
| Low-level recording | `RawInputEvent`、`RecordingEventPipeline`、`RecordingSessionProcessor` 已把 CGEvent 边界和纯 pipeline 分开 | Swift Testing 覆盖 pipeline/buffer/sampler/session processor | 还没有 event-aligned keyframe/video bundle |
| Workflow runtime | reducer/effect/runtime/resource/player/condition/run history 已有 first pass | `AutomationReducerTests`、`AutomationOwnerBClientTests`、runtime/session tests | 还缺真实产品录屏证明 branch/evidence/UI 状态一致 |
| Workflow AI draft | `sparkle.workflow.draft.v1` validate/simulate/dry-run/import/edit/patch 已有 first pass | Draft/import/runtime CLI tests | 还不能从 recording evidence 自动生成 draft |
| Visual conditions | OCR/visual condition、visual assets、package-root retention、condition diagnostics payload 已有 first pass | Contract/reducer/view projection/OwnerB tests; `template-baseline-preview-refs.png` fixture renders source/runtime/decision from `SemanticRecordingBundle` | 最终 Review UI 仍需把录制帧、运行样本、score/diff 接进真实用户流程 |
| Run evidence | Macro evidence presenter、condition artifact presenter、branch evidence first pass 已有 | Product fixture PNG + tests | live Open/Reveal、live visual capture、branch real-run consistency 还缺录屏 |
| Semantic capture session | pure `SemanticRecordingCaptureSession` / `SemanticRecordingCaptureClient` 已能用 fake movie/frame/index clients 生成 bundle、video segment、event-aligned keyframes 和 observations；app-edge `LiveSemanticCaptureClient`、ScreenCaptureKit movie/frame、Vision OCR indexer、bundle store skeleton、permission preflight evaluator 和 live PermissionCenter bridge 已编译通过 | `SemanticRecordingCaptureTests`、`SemanticRecordingPreflightTests`、Swift 6 build | 普通录制生命周期接线、live 产品证据、failure/partial artifact 处理、preflight UI/gating、AX/suppression、retention/deletion 仍缺 |
| Context-only condition evidence | `previousOutcome`、external signal、manual approval 已通过 `AutomationConditionEvaluationEvidence.contextual` 生成 durable diagnostics | `AutomationOwnerBClientTests.contextualConditionEvaluatorUsesContextAndProviders` | UI 可展示，但还没有产品证据截图/录屏专门覆盖 |

本轮维护状态：

- 已确认 `semantic-recording-ai/` 应作为 Workflow 证据缺口之后的路线校准源，而不是替代 `automation-engine/` 或 `workflow-page-productization/`。
- 已把当前剩余任务整理为本文件的执行账本。
- 已把 `AutomationConditionEvaluationEvidence` 的 context-only diagnostics 纳入 current status，避免未来只把 diagnostics 理解成 OCR/visual 截图。
- 已完成 2026 Apple API 可行性核对并接受 macOS 15+ 产品基线：`SCRecordingOutput` 是默认完整 `.mov` 路径；同一录制生成 event-aligned keyframes 作为视觉索引；不规划 macOS 14 `AVAssetWriter` fallback；Vision 可提供 OCR/feature print/tracking primitives，但 pattern search 需要自有评分和 deterministic matcher。
- 已新增 [08-parallel-workstreams.md](08-parallel-workstreams.md)，把下一阶段拆成 S0 Workflow Evidence、S1 Contract/Core、S2 App Capture/Visual Index、S3 Review UX、S4 CLI/AI/App Knowledge。
- 已新增 [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md) 作为 S0 工作台，并确认 S1 已接受 [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md) 的 first-pass core contract；source/runtime/decision fixture 渲染证据已补，真实 Review UI 接线仍待补。
- 已新增 `workflow product-evidence audit` 作为 S0 证据门禁；当前 smoke 为 9/13 required present，缺 4 个 live-product artifacts；live artifact 可用 `.mov` 或 `.mp4`，但严格门禁会校验同名 sidecar 的必填 capture labels 并拒绝未填写的占位符。`workflow product-evidence capture-plan` 会列出每个缺失 live gate 的文件名候选、sidecar 模板命令和缺失标签；`workflow product-evidence prepare-live-capture` 已把 5 个缺失 live sidecar 草稿写入 product-evidence 目录且默认不覆盖已有记录；`workflow product-evidence complete-sidecar` 可在录屏后用 typed CLI 字段补全单个 sidecar 并校验 clip 文件名；`workflow product-evidence sidecar-template` 可生成单个 live gate 的标准 sidecar 草稿。严格门禁仍然红，因为 clips 缺失且当前真实 sidecar 字段未填写。
- 已新增 S1 core schema v0 first pass：`SemanticRecordingBundle`、video/keyframe/timeline/AI-safe event/visual observation/suppression/source preview/runtime sample/comparison/query/suggestion value types，以及 `SemanticRecordingFixture.checkoutBundle()` / query result / suggestion fixtures；测试覆盖 path safety、schema validation、fixture validation 和 preview comparison round trip。
- 已新增 [10-next-stage-reality-check.md](10-next-stage-reality-check.md)，把剩余工作按用户价值重新分成 P0 Workflow evidence trust、P1 Review and Teach、P2 live capture、P3 CLI for AI collaboration、P4 App Knowledge later，并明确 OCR/visual region picker、source/runtime comparison、frame-to-condition 和 Player state machine extraction 的边界。
- 已新增 [workstreams/s2-app-capture-visual-index.md](workstreams/s2-app-capture-visual-index.md)，记录 S2 capture session first pass、targeted tests、app-edge ScreenCaptureKit/Vision/store 骨架和生命周期接线/产品证据剩余任务。
- 已启动 S2 app capture first pass：`SemanticRecordingCaptureSession` 和 `SemanticRecordingCaptureTests` 用 fake clients 证明 `.mov` segment、event-aligned keyframes、AI-safe semantic events、OCR observation 回填和 keyframe-only 模式；app target 已有 `LiveSemanticCaptureClient`、`ScreenCaptureKitMovieRecorder`、`ScreenCaptureKitFrameSource`、`VisionRecordingIndexer`、`RecordingBundleStore` 骨架；`SemanticRecordingPreflight` / `LiveSemanticRecordingPreflight` 已覆盖 permission snapshot、blocking/degraded capability 判断并通过 Swift Testing；整体通过 Swift 6 build。
- 尚未把 S2 接进普通宏录制生命周期；尚未产出 live `.mov` 产品证据、AX/window observation production、Review UI、Recording CLI command、retention/deletion policy 或 frame-to-`AutomationWorkflowDraftVisualAssets` asset copy。

## 2. Direction Decision

方向正确，但正确点不在“让 AI 看视频自动操作电脑”，而在“让一次录制变成可解释、可修正、可组合的自动化资产”。

正确路线：

```text
record playable macro
  -> align events with keyframes and visual observations
  -> user reviews intent and fragile waits
  -> extract visual assets / conditions from frames
  -> AI proposes draft with evidence refs
  -> user validates, simulates, imports
  -> runtime evidence feeds diagnosis and future cleanup
```

需要避免的路线：

```text
record video
  -> send whole video to AI
  -> AI guesses workflow
  -> write runnable automation directly
```

SparkleRecorder 的优势是本地确定性：录制事件、窗口/视觉证据、Workflow reducer、condition evaluator、CLI draft 和 run evidence 都能被测试和审阅。Semantic recording 应该增强这些边界，而不是绕过它们。

## 3. User Behavior Logic

用户不是一开始就想配置复杂状态机。用户的直觉路径是：

1. 快速演示一次，不想打断录制。
2. 停止后回看，才愿意解释“这里在等什么”、“这个输入是否是变量”、“这个点击是否应该绑定文字或图标”。
3. 让 AI 帮忙提出修正，但用户要看到证据。
4. 把多个已知宏拼成 workflow。
5. 运行失败后回到证据：录制时基准、运行时样本、分支原因、失败截图。
6. 对同一应用重复积累，下一次少录一点。

所以第一版产品不应该要求用户在录制前设计 workflow，也不应该要求用户相信 AI 的黑盒结论。第一版应该让用户录完之后更容易“教系统”。

## 4. Remaining Task Register

### Bridge A: Close Current Workflow Evidence

这些任务优先级最高，因为它们验证现有 Workflow 是否可信。

| Task | Owner | Why It Matters | Acceptance |
| --- | --- | --- | --- |
| Live visual diagnostics recording | App + UI | 用户需要看到系统真实看了哪里，不只是 fixture | 真实 App 运行 OCR/visual condition，Run Detail 显示 sample/crop/score/threshold，Open/Reveal 打开真实 artifact |
| Branch evidence real-run recording | Core + UI | 用户需要相信 FlowGraph 走线和 Run Detail 原因一致 | 同一次 success/failure/timeout run 中，edge 状态、selected run、branchEvidence drill-in 一致 |
| Macro evidence file-action recording | App + UI | 失败后用户第一件事是打开报告或截图 | Reveal Report / Open Screenshot 真实交互有 inline feedback |
| Drag/reorder WYSIWYG recording | UI | 编排页面必须可用，preview 不能骗用户 | macro drag、task reorder、connector link 的 indicator 与 reducer mutation 一致 |
| Template/baseline preview contract | S0 + S1 + App + UI | 字符串 refs 不够，用户要知道 ref 指向什么 | S1 已接受 first-pass core contract；S0 fixture artifact 已展示 source/runtime/decision；下一步需要真实 Run Detail/Review UI artifact 展示 recorded template/baseline、runtime sample、score/diff/fallback |
| Resource/runtime product evidence | Core + UI | 等待资源、重试、超时要能被用户解释 | 多 workflow resource queue、max wait、handoff status readback 有产品证据 |

Do not start video bundle implementation before Bridge A has at least live evidence clips for visual diagnostics and branch evidence. Otherwise semantic recording will inherit an untrusted evidence UI.

### Phase 0: Freeze Minimal Semantic Contract

| Task | Owner | Deliverable | Notes |
| --- | --- | --- | --- |
| Bundle schema v0 | Core | `SemanticRecordingBundle`, version, ids, paths | Keyframe-only compatible; full video optional |
| Timeline/event split | Core | private `timeline.jsonl`, AI-safe `events.jsonl`, `suppressed.jsonl` | Suppression is a first-class artifact, not a log afterthought |
| Frame refs | Core | `RecordingFrameReference`, event/frame/surface alignment | Must support click before/after frame |
| Visual observations | Core | OCR/AX/window/pixel/template observation value types | App produces, core stores values |
| Asset mapping | Core + App | frame crop -> `AutomationWorkflowDraftVisualAssets` | Reuse existing visual asset refs and safe path rules |
| Retention/deletion policy | App | user-facing local storage and delete semantics | Video/keyframes are sensitive |
| Apple availability policy | App + Core | macOS 15+ baseline, default `SCRecordingOutput` video, event-aligned keyframes, no macOS 14 fallback | Must be written before live video code |

### Phase 1: Video Plus Keyframe Recording Slice

First implementation should prove full video and keyframes together, while still allowing a future light keyframe-only mode for privacy/storage.

| Task | Owner | Acceptance |
| --- | --- | --- |
| Pure capture session | Core | first pass done: fake clients build a validating `SemanticRecordingBundle` with video segment, keyframes, semantic events and observations |
| Capture `.mov` recording | App | first pass adapter compiles; accepted when ordinary recording lifecycle can write a real video segment through `SCRecordingOutput` with start/end metadata |
| Capture event-aligned keyframes | App | first pass adapter compiles; accepted when ordinary recording lifecycle writes frame refs and PNG artifacts around start/click/text/wait/stop |
| Persist frame index | App + Core | frame IDs, event IDs, time, surface ID, bounds round-trip |
| Macro Review frame strip | UI | selecting event row jumps to before/after frame |
| OCR on selected frames | App | Vision runs app-edge; core stores observation fixtures |
| Tests | Core/App | fake clock/frame fixtures prove alignment; no real ScreenCapture in unit tests |

Full `.mov` capture is part of semantic recording on macOS 15+. Keyframe-only can remain a user-facing light mode, but no macOS 14 fallback is planned.

### Phase 2: Frame-To-Condition

This is the product vertical slice that makes semantic recording valuable.

| User Action | System Output | Acceptance |
| --- | --- | --- |
| Select text area on recorded frame | OCR wait condition draft | Draft validates and imports into existing workflow visual/OCR condition model |
| Select icon/button crop | `imageRef` template asset | Asset stores source frame, crop bounds, suggested search region, threshold |
| Select result panel | `baselineRef` region-changed asset | Runtime can compare baseline to last sample |
| Pick a status pixel | `pixelMatched` condition | Pixel stores source frame coordinate and target color |
| Accept suggestion | Draft patch or workflow draft | Suggestion includes evidence refs, confidence, risk, fallback |
| Reject suggestion | No mutation | User can keep playable macro unchanged |

### Phase 3: Recording CLI

CLI comes after bundle fixtures exist.

| Command Group | First Commands | Blocked By |
| --- | --- | --- |
| Catalog | `recording list/show/explain --json` | Bundle schema |
| Frame query | `recording frames/frame show/events-near --json` | Frame refs |
| OCR/search | `recording ocr search --json` | OCR observations |
| Asset extraction | `recording asset extract/baseline --json` | Frame-to-asset mapping |
| Suggestions | `recording suggest waits/locators/conditions/cleanup --json` | deterministic local heuristics |
| Draft | `workflow draft from-recording --json` | suggestions + draft compiler |

MCP remains deferred. When needed, MCP should wrap this service/CLI semantic contract, not create a separate product logic path.

### Phase 4: App Knowledge

This is future work, not next sprint.

| Task | When To Start |
| --- | --- |
| Group macros/recordings by app bundle ID and surface family | After several recordings have semantic bundles |
| Build app-level anchor/condition library | After frame-derived assets are stable |
| Natural-language goal composition | After CLI can explain, search, and generate draft from evidence |
| Cross-recording reusable skill summaries | After users can reject/accept AI suggestions reliably |

## 5. Overdesign Audit

| Tempting Design | Risk | Safer Version |
| --- | --- | --- |
| Full video without controls | storage and privacy risk | video default for semantic recording, plus explicit retention, deletion, exclusions and optional light mode |
| OCR/AX on every frame | CPU and noisy evidence | event-triggered keyframes and selected-frame analysis |
| Global visual asset library first | hard migration and missing-file complexity | recording/package-local assets first, then managed storage |
| AI writes runnable workflow | unsafe and hard to debug | AI writes draft/suggestion with evidence refs |
| MCP now | duplicated logic and harder tests | CLI/shared service first; MCP wrapper later |
| App knowledge graph now | too abstract without data | app/macro/surface grouping first |
| SwiftUI visual processing | hangs and untestable code | app-edge presenters/adapters and core value models |

## 6. Maintainability Checks

Every semantic recording PR should answer:

- Does this keep `RecordedEvent` as execution truth?
- Does this store evidence as versioned value data with safe relative refs?
- Can the feature be tested without real mouse, keyboard, ScreenCaptureKit, Vision or AX in unit tests?
- Does SwiftUI only render projections/presenter results?
- Does AI output cite frame/event/evidence IDs and stay reviewable?
- Does this reuse `AutomationWorkflowDraftVisualAssets`, artifact presenters and CLI envelope patterns?
- Can users delete or suppress sensitive recording evidence?

If the answer is no, the implementation probably belongs in a later phase or behind an app-edge adapter first.

## 7. Immediate Next Slice

Recommended order from here:

1. Product evidence: live visual diagnostics Open/Reveal recording.
2. Product evidence: real branch evidence consistency recording.
3. Product evidence and UX closure: OCR/visual region picker should show a region box for wait/verify actions and reserve click circles for click actions only.
4. API spike: target-window/display `.mov` capture through `SCRecordingOutput` plus event-aligned keyframes, with fake capture clients for tests. First pass now has fake-client session tests and app-edge ScreenCaptureKit/Vision/store skeletons; next step is wiring a real smoke path into recording lifecycle.
5. Fixture Review UI: open a `SemanticRecordingBundle` fixture and render frame/source/runtime/comparison states without live capture.
6. CLI prototype: `recording show` and `recording frames` against a fixture bundle.
7. Asset mapping note: define frame crop -> `AutomationWorkflowDraftVisualAssets` copy semantics before implementing frame-to-condition.
8. UI prototype: Macro Review frame strip for existing macro package fixtures.
9. Frame-to-condition design note: define the first user-reviewed conversion flow for OCR wait, image appeared/disappeared, region changed and pixel matched.
10. Playback architecture follow-up: continue extracting `Player.swift` lifecycle state into pure testable state machine/evidence helpers, but do not block semantic recording planning on a full Player rewrite.

This sequence keeps the project grounded: every new AI-facing capability starts from evidence a user can see.

并行执行边界见 [08-parallel-workstreams.md](08-parallel-workstreams.md)。下一阶段现实校准见 [10-next-stage-reality-check.md](10-next-stage-reality-check.md)。S0 进展维护在 [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md)。下一轮实现时不要把 S1/S2/S3/S4 的职责混到一个 PR 里；至少先冻结 S1 合同和 S2 API spike 的接口。

# Automation Engine Parallel Workstreams

Updated: 2026-09-04

## Accepted reconstruction boundary (verification pending)

S3 reconstruction Review requests complete macro snapshots and user-driven test/correction/accept/restore intents from Owner B. Accepted: repository loading pins one complete accepted revision; candidate test tokens bind source revision and normalized executable digest; acceptance revalidates the current source and preserves metadata. Live text observation distinguishes absent from unavailable and bounds polling/cancellation. Owner C consumes `MacroReconstructionReviewModel` state and intents. No Automation reducer action/effect or terminal semantics change is requested. Direct test mappings: `MacroCandidateRepositoryTests`, `PlaybackTextObservationTests`, `MacroReconstructionReviewTests`, plus existing `PlaybackLocatorCacheTests`. Central verification and all installed-app gates remain pending.

## Accepted interface note: workflow activation summary (2026-08-25)

- Owner C requested a user-facing readiness boundary for the scheduling UX.
- Owner A accepted the first pure `AutomationWorkflowActivationProjection` slice derived from the existing workflow projection. It owns blocked/manual-only/scheduled/running precedence and stable check IDs.
- Owner C consumes that projection in the workflow list and settings readiness card; Views do not query scheduler, repository, permissions, or files.
- Owner B capability snapshots for permissions, macro availability, and future background execution remain an explicit follow-up and are not inferred by the UI.
- Direct coverage lives in `AutomationWorkflowActivationProjectionTests`.

本文件说明哪些任务可以并行、哪些必须串行。核心判断标准：是否依赖 Automation Core 合同。

## Phase 0: 已完成的合同冻结

已完成并作为三人并行的共同输入：

- `AutomationWorkflow`
- `AutomationTask`
- `AutomationTaskRun`
- `AutomationDependency`
- `AutomationOutcome`
- `AutomationAction`
- `AutomationRunState`

Reducer 基本签名不再放在 Phase 0，它是 Owner A 在 Phase 1 的第一项交付。

## Phase 1: 可并行任务

本项目固定采用 3 个 owner 的并行模式。即使现实中有人临时兼任，也必须按 A/B/C 三个角色写规划、提接口请求和验收，避免状态语义、真实副作用和 UI 交互混在一起。

| Owner | Primary Scope | Files They Own First | Can Start After | Done Means |
| --- | --- | --- | --- | --- |
| A: Core/Reducer | `AutomationRunState`, reducer, dependency cascade, terminal outcome ordering | [workstreams/owner-a-core-reducer.md](workstreams/owner-a-core-reducer.md) | Phase 0 contract | Pure reducer handles tick/manual start/resource/player/condition/cancel and updates downstream `earliestStartTime` deterministically |
| B: Adapters/Persistence | `ResourceArbiter`, `PlayerClient`, `SchedulerClient`, `ConditionEvaluator`, `AutomationRepositoryClient`, repository snapshot/refresh state, effect runner, runtime shell/session, app lifecycle host, runtime handoff mailbox | [workstreams/owner-b-adapters-persistence.md](workstreams/owner-b-adapters-persistence.md) | Phase 0 contract | Live adapters only emit `AutomationAction`; mocks cover single/batch lease handoff, partial lease cleanup, Player result/cancel, scheduler tick, condition context/providers, repository refresh state, effect consumption, runtime loop/session shutdown, run-history append, App-host handoff command queue/dispatch |
| C: UI/Performance | FlowGraph projection, Resource Timeline projection, Canvas line drawing, projection refresh UI, node-position drag actions, first-pass authoring UI | [workstreams/owner-c-ui-performance.md](workstreams/owner-c-ui-performance.md) | Reducer projection/edit action shape from Owner A | UI reads projection values only, no direct Player/Scheduler calls, gestures and authoring forms emit reducer actions |

## Owner Rules

本阶段只保留 A/B/C 三个 owner。`ResourceArbiter`、`PlayerClient`、`SchedulerClient`、Persistence、FlowGraph 等都是这三个 owner 内部的交付物，不再单独列成 owner。

| Owner | Hard Boundary | Deliverables |
| --- | --- | --- |
| A: Core/Reducer | 不调用真实 `Player`、scheduler、file system、OCR、AppKit 或 SwiftUI；不把运行态写回 `SavedMacro`；不决定 UI 布局或 JSON 文件格式。 | `AutomationReducer`、effect/action 合同、dependency cascade、terminal ordering、projection shape、pure reducer tests。 |
| B: Adapters/Persistence | 不直接修改 `AutomationRunState`；不 import SwiftUI；不绕过 reducer 启动 `Player`；不把 live failure 压成 Bool；不把 run history 写回 `SavedMacro`；不让 `.sparkrec_workflow` 夹带 run history、evidence 或宏事件包。 | `AutomationEngineRuntime`、`AutomationRuntimeSession`、`LiveAutomationRuntimeHost`、`AutomationEffectRunner`、`AutomationResourceArbiterClient`、`AutomationPlayerClient`、`AutomationConditionEvaluatorClient`、condition provider clients、`AutomationSchedulerClient`、`AutomationRepositoryClient`、`AutomationRepositorySnapshotClient`、`AutomationRepositoryRefreshClient`、`automations.json` 格式、`.sparkrec_workflow` package codec、fake/live adapter tests。 |
| C: UI/Performance | 不直接调用 `Player`、scheduler、repository 或 arbiter；不在 SwiftUI `body` 内做 DAG traversal、file IO 或运行状态决策；拖拽/拉线/表单编辑只能通过已接受的 reducer action 或 provider 合同提交。 | Automation overview、FlowGraph projection UI、Canvas dependency line layer、Resource Timeline、projection refresh/loading/error UI、FlowGraph node-position/link action dispatch、workflow/task/dependency inspector、schedule/condition authoring forms、manual approval/external signal product source UI、evidence/run-history display、projection/UI performance tests。 |

## Interface Change Rules

跨 owner 的接口包括 `AutomationAction`、reducer effect、projection shape、client request/result、`AutomationOutcome`、`AutomationTaskRun` 字段和 `automations.json` 文档结构。

接口变更必须遵守：

- 提出方先在自己 owner 文件的 `Interface Requests` 记录请求，写清楚新增/修改的类型或 case、原因、兼容性影响、需要的测试。
- 受影响 owner 必须在自己的 `Accepted Contracts` 或 `Open Questions` 记录接受、拒绝或待定状态。
- 变更落地时同步更新 `02-parallel-workstreams.md`、对应 owner 文件和直接覆盖该接口的测试。
- 未被接受的跨边界需求只能以 adapter 内部实现或临时假数据处理，不能偷改其他 owner 的语义边界。
- 删除或重命名 public 合同必须先提供迁移说明；持久化字段必须保持旧 JSON 可读，除非阶段文档明确宣布破坏性迁移。

当前已接受的 A/B 接口变更：`AutomationEffect.evaluateCondition` 携带 `previousOutcomes`，由 reducer 从 `upstreamRunIDs` 解析，Owner B 只通过 `AutomationConditionEvaluationRequest` 消费。

当前已接受的 A/B/C evidence 变更：`AutomationConditionEvaluationResult` 可以携带 `AutomationConditionEvaluationEvidence`，reducer 会把它写入 terminal `AutomationTaskRun.conditionEvidence` 后再持久化 run history。`AutomationConditionDiagnosticArtifact` 只保存 App Support 相对路径、类型和 bounds metadata，并通过 core helper 规范化相对路径；Owner B 的 live OCR/visual evaluator 负责保存 last-sample / watched-region PNG，并在失败/拒绝终态尽量返回解释性 diagnostics payload；`previousOutcome`、external signal、manual approval 这类 context-only condition 也必须返回解释性 evidence，避免 Run Detail 只有 outcome 没有原因。Owner C 只能读取 payload 或通过 `AutomationConditionEvidenceArtifactPresenter` 预览/open/reveal artifact，不能在 SwiftUI 中拼路径、重新截图或调用 evaluator。UI 应该渲染失败 payload，只有 `conditionEvidence == nil` 时才标记 diagnostics missing。

当前已接受的 B/C 接口变更：`AutomationRepositoryRefreshState` 表达 repository refresh 的 idle/loading/loaded/failed，loading/failed 可以携带 previous snapshot，Owner C 不直接调用 repository throws API。

当前已接受的 B/C provider 变更：`LiveAutomationRuntimeHost` 接受 `AutomationExternalSignalClient`、`AutomationManualApprovalClient` 和 OCR region context 注入；app 层通过 `AutomationSignalStore` / `AutomationExternalSignalSourceView` 提供 external signal，通过 `AutomationManualApprovalPresenter` 提供 manual approval，SwiftUI 仍不直接调用 condition evaluator 或回读 reducer state。

当前已接受的 B/C persistence 变更：`.sparkrec_workflow` 由 `AutomationWorkflowPackageDocument` 和 `AutomationWorkflowPackage.encode/decode/validate` 表达，只承载静态 `AutomationWorkflow`；Owner C/product UI 负责保存/打开面板、selected/all workflow 导出与分享入口、冲突提示和缺失本地宏提醒，但不自行解释或扩展 package JSON 字段。当前 second pass 已接入保存/打开面板、selected/all workflow 导出与 macOS share sheet、Add Copies / Replace Existing 冲突提示和 missing macro reference 提示。

当前已接受的 Owner B/CLI runtime 变更：`AutomationRuntimeHandoffCommand` / `AutomationRuntimeHandoffClient` 提供文件 mailbox first pass。CLI `workflow run/cancel --handoff app` 只写入 `automation-runtime-handoff.json` 并返回 handoff payload；正在运行的 `LiveAutomationRuntimeHost` 轮询 mailbox，把命令转为既有 `AutomationAction.manualStart` / `cancelRun` 并通过 `AutomationRuntimeSession` dispatch。`AutomationRuntimeHandoffReceipt` 和 CLI `workflow handoff status <command-id>` 提供 pending/dispatched/failed/missing 回执查询 first pass；status payload 会在 receipt 带 run IDs 且 repository 有 run history 时附带 `runs` snapshots 和 `workflowStatus`，给 AI 直接判断 queued/running/terminal 的 readback。该合同不唤醒未运行 App、不保持 CLI 长会话、不向 CLI 推送实时进度；daemon/background handoff 和 push-style live result/progress stream 仍是后续任务。

当前已接受的 A/C 接口变更：FlowGraph 节点移动使用 `AutomationAction.moveTask`，reducer 持久化 `AutomationTask.graphPosition`，projection 优先读取该位置再回退到自动 DAG 布局；workflow/task/dependency authoring 使用 reducer edit actions，schedule/condition 表单只提交 `AutomationAction.upsertTask`；join policy UI 读取 `AutomationTaskNodeProjection.joinPolicy` / `joinPolicyLabel` / `incomingDependencyCount`，Graph badge 和 Inspector 编辑不重新实现 dependency resolution。

当前已接受的 A/B/C 目标应用启动接口：`AutomationTask.targetApplicationPolicy` 使用 `doNotActivate` / `activateIfRunning` / `launchIfNeeded` 表达任务级意图，旧 workflow 解码默认 `activateIfRunning`；reducer 将策略随 `AutomationEffect.startPlayer` 交给 Owner B，Owner B 在 Player 开始前激活或启动宏绑定 surface 的 bundle identifier，并在 `launchIfNeeded` 下等待绑定窗口出现，失败时返回可解释的 rejected outcome。Owner C 只编辑该字段并通过 `.upsertTask` 保存；Quick Schedule 新任务默认 `launchIfNeeded`，现有任务行为不变。

当前已接受的单宏自动运行接口：`AutomationTask.targetApplicationCleanupPolicy` 使用 `keepOpen` / `quitIfLaunched` 表达结束清理意图，旧 workflow 解码默认 `keepOpen`。Owner B 的目标应用 prepare 返回本次实际启动的 bundle identifiers，证据捕获完成后才允许 cleanup；`quitIfLaunched` 只处理该 session 内的应用，禁止退出运行前已存在的应用。Quick Schedule 新任务默认 `quitIfLaunched`。成功 `RunReport` 与失败报告一样将 `runID` 绑定为 `AutomationTaskRun.evidenceID`，Owner C 从 Library 通过 presenter 读取证据，不直接访问文件系统。

2026-07-18 accepted hardening: cleanup sessions identify exact run-launched process identifiers instead of re-querying every process with the same bundle identifier. `AutomationTask` additionally persists a bounded graceful-exit timeout and whether timeout permits force quit. Quick Schedule exposes these controls and defaults to graceful terminate plus exact-PID force fallback after five seconds. Owner B must await the configured cleanup result before emitting terminal Player completion; pre-existing applications remain ineligible. Owner C keeps countdown ticks and card hover/context-menu state scoped below the Library root so they do not invalidate schedule projections or the whole card grid.

2026-07-18 run-observability request and accepted contract: Owner C requests an execution-level Library Runs surface rather than extending task-local history. Owner A owns execution grouping by `executionID`, status precedence, first actionable failure, semantic recovery actions through `AutomationRunCenterProjection`, and pure retention planning/protection semantics through `AutomationRunRetentionPlanner`. Owner B supplies live-state-first/repository-fallback snapshots, durable queued/started checkpoints, persistence health, interruption reconciliation, atomic retention state transitions, path-confined artifact deletion, and daily cleanup orchestration. Owner C renders filters, counts, execution selection, stale/error states, failure focus, evidence navigation, and retention settings/confirmation without reading repository or evidence files directly. Direct projection/model/store tests are required before the Library entry is accepted.

2026-07-18 run-history performance request and accepted contract: Owner B may migrate embedded `AutomationPersistenceDocument.runHistory` lazily into the versioned `automation-runs.jsonl` checkpoint journal while keeping old JSON readable. Journal replay is last-write-wins by run ID; append must synchronize before later live effects, and retention/compaction must atomically preserve one latest entry per retained run. Owner A supplies a pure metadata count cap and a per-tick represented-schedule index without changing reducer outcomes. Owner C consumes a monotonic runtime revision, skips unchanged polling refreshes, and builds changed run-center projections off `MainActor`. The revision is volatile and must not enter persistence. Migration, torn-tail, compaction, unchanged-refresh, large-projection, scheduler-index, and count-cap tests are direct acceptance evidence; details live in `docs/run-observability/performance-plan.md`.

2026-07-18 run-recovery UX request and accepted contract: Owner B returns canonical per-run evidence persistence health rather than swallowing storage errors; Owner A checkpoints that health and owns workflow-level retry semantics with one new execution ID across enabled root tasks; Owner C maps semantic recommended actions to exact evidence navigation, execution-wide cancellation, workflow retry, permission settings, Run History settings, or focused Workflow editing. `evidenceID` alone is not availability. Commands must expose confirmation, progress, refresh, and localized feedback. Details live in `docs/run-observability/recovery-ux-plan.md`.

2026-07-19 run-storage control request and accepted contract: Owner A owns pure terminal-run deletion validation and the durable screenshot-removed projection mutation. Owner B inventories allocated bytes by artifact class, confines every deletion path, applies execution evidence/history deletion through the existing two-phase retention transaction, and atomically checkpoints screenshot-only deletion. Owner C shows whole-store and selected-execution usage, exposes an automatic-cleanup toggle with last/next status, and routes size-aware destructive confirmations through app-edge commands. SwiftUI does not enumerate or delete files.

2026-07-18 quick-linear-automation accepted contract: Owner C may compile a small ordered macro list, fixed dependency delays, and OCR-text gates into the existing draft/import contract without changing reducer or adapter semantics. Quick Sequence OCR authoring reuses the existing OCR/rectangle picker entry points and stores selected bounds as draft visual assets referenced by the OCR condition; runtime evaluation remains the existing Owner B client. Macro tasks use `launchIfNeeded`, `keepOpen`, one playback loop, and `latestOnly`; the first macro alone owns the manual/daily/weekly/once/interval schedule. Saving stays in Library, while opening Workflow is an explicit advanced action. Shared end-of-sequence target cleanup remains a future A/B lifecycle request because per-task Player sessions cannot reliably close an application launched by an earlier task.

2026-07-19 startup-readiness request and accepted contract: Owner C requests a bounded wait between Owner B finding the bound target window and posting the first macro input. Owner A persists `AutomationTask.targetApplicationReadyDelay` with zero-default backward compatibility and carries it through `AutomationEffect.startPlayer`; draft import/export round-trips the field. Owner B applies the normalized 0...60 second delay after target preparation, makes the wait cancellable, and cleans up the exact process launched by the run before returning cancellation. Owner C exposes the field in Quick Schedule, Quick Sequence, and advanced task editing; Quick Sequence may insert an existing login/navigation macro at the start and continues to use existing OCR condition tasks for observable readiness between steps. Details live in `docs/automation-readiness/README.md`.

当前已接受的单宏播放次数接口：`AutomationTask.playbackLoops` 是可选任务级覆盖，旧 workflow 缺失时保持宏自身循环语义。Quick Schedule 固定写入 `1`，Owner A 随 `startPlayer` effect 交给 Owner B，Owner B 在规划与播放前覆盖加载宏的 loop count。该字段随 workflow Codable 和 draft import/export 往返，避免 Library 的无限循环配置阻止自动任务完成与清理。

当前已接受的遗漏运行接口：`AutomationTask.missedRunPolicy` 使用 `catchUp` / `latestOnly`。旧 workflow 解码为 `catchUp` 以保持历史语义；Quick Schedule 写入 `latestOnly`。Reducer 对 `latestOnly` 只创建当前时刻最近一个到期 occurrence，若它已被 run 表示则不会回头补建更早遗漏，防止 App 关闭数天后形成补跑队列。该字段随 workflow Codable 和 draft import/export 往返。

当前已接受的 draft/import loop 变更：`sparkle.workflow.draft.v1` 可以表达固定次数 `loop` draft task；`AutomationWorkflowDraftLoopExpander` 在 validate 通过后、simulate/import 前把 loop body 展开成普通 acyclic tasks/dependencies，并按 body source 类型使用 `success` 或 `conditionMatched` 触发下一步。Owner A 保持 reducer/runtime 只接收普通 DAG workflow，Owner C 只显示 Draft Preview 的 loop 摘要和 projection-backed expansion/boundary explanation，Owner B package/repository 不保存特殊 runtime loop state。dependency cycle/self-edge validation 仍然有效，repeat-until / foreach、loop authoring UI 和 run evidence 是未来接口请求。

## Planning Files

每个 owner 的后续规划、接口请求、阶段风险和交付记录都写到 `workstreams/` 下自己的文件：

- A: [workstreams/owner-a-core-reducer.md](workstreams/owner-a-core-reducer.md)
- B: [workstreams/owner-b-adapters-persistence.md](workstreams/owner-b-adapters-persistence.md)
- C: [workstreams/owner-c-ui-performance.md](workstreams/owner-c-ui-performance.md)

跨 owner 的接口变更以三份 owner 文件为准，不再维护额外 owner 名单。

## 不建议并行的工作

- FlowGraph 交互和 reducer 合同同时重写。
- OCR 条件识别和通用 `ConditionEvaluator` 同时深做。
- `.sparkrec_workflow` 包格式和 `automations.json` 同时做。
- Player 大重构和 AutomationEngine 第一版同时做。
- 真实 scheduler 与 reducer 测试同时跑真实时间。

## 推荐开发顺序

1. Core contract。
2. Reducer + Swift Testing。
3. ResourceArbiter mock/live skeleton。
4. PlayerClient mock/live skeleton。
5. SchedulerClient mock/manual trigger。
6. Persistence with `automations.json`。
7. `.sparkrec_workflow` package codec after repository JSON is stable。
8. Read-only UI projection。
9. FlowGraph edit interactions。
10. OCR region picker authoring for display/window/content coordinate spaces。
11. Background scheduling and launch integration。

## 并行协作约束

- 所有模块只能通过 `AutomationAction` 改变 reducer state。
- UI 不直接调用 `Player`。
- Scheduler 不直接调用 `Player`。
- ResourceArbiter 不知道宏内容，只知道 run 和 resource。
- Persistence 不保存 volatile UI state。
- Tests 先验证 reducer，不依赖真实 time、mouse、keyboard、OCR。


## Reconstruction test lifecycle contract (2026-09-04)

Coordinator/C requests and B accepts shared Player reservation through target preparation, playback and deduplicated cleanup. Scoped cancellation identifies its own run; cancelled preparation cannot start late. Review cancels the whole test task and prevents recording entry while it is active. Tests: `AutomationPlayerReservationTests`, `MacroReconstructionReviewTests`. Candidate trial policy runs one iteration without chains; repository receipt binds policy, capability version and execution digest while accepted repeat/chain settings are preserved.


## Accepted manual playback handoff repair (2026-09-05)

UI requests the existing Owner B target-preparation/player/evidence path for manual playback; Owner B accepts a default-empty `onStarted` callback on the preview client so UI cannot announce playback before acceptance. Player uses an injected post-event permission check before starting; live automation rejects before launching targets. Reducer and persisted outcome schemas are unchanged. Direct tests are PlaybackPermissionTests and AutomationScheduledMacroPreviewClientTests, plus existing reservation/target-preparation tests. Investigation and live-evidence limits: [playback audit](../semantic-recording-ai/24-playback-reliability-audit.md).

# Acceptance Checklist

未被代码、测试、文档和产品体验共同证明的项不能打勾。first pass 可以写在状态栏，不能冒充 done。

## Contract

- [x] 新阶段文档目录存在，并说明和 `automation-engine/` 的关系。
- [x] Workflow Pro macOS visual/UX contract exists and is linked from owner docs.
- [ ] Page model 被 Engine/UI 两个 owner 接受。
- [ ] AI draft schema 被 Engine/UI 两个 owner 接受。
- [x] Backend Capability Notice 模板开始被使用。
- [ ] 旧 checklist 中和当前体验不符的完成项被降级或标注为 first pass。

## Owner 1: Engine / Runtime / AI CLI

- [ ] Repeating schedule 能生成独立 future runs。
  - First pass: [x] Reducer `clockTick` creates the next due unrepresented occurrence as an independent `AutomationTaskRun`.
- [ ] Resource waiting state 能被 reducer 表达并被 release 唤醒。
  - First pass: [x] `.resourceLeaseDenied` keeps the run in `waitingForResource`, and release/tick retries the waiting run through `.requestResource`. UI projection now presents foreground-input waits as `.waiting` and exposes `resourceWaiting` detail/resource/priority/wait-duration/blocker data.
- [ ] Timeout watchdog 终态释放资源并触发 timeout branch。
  - First pass: [x] `clockTick` completes queued/running timed-out runs as `.timedOut`, cancels macro work first, releases leases, persists the run, and triggers `.onTimeout` downstream dependencies. Countdown projection and Graph/Timeline/Task Inspector rendering first pass are available; product evidence remains open.
- [ ] Retry policy 会创建下一 attempt，并保留 execution/run history。
  - First pass: [x] Failure/timeout terminal outcomes create same-execution retry attempts until `maxAttempts` is exhausted; fixed/exponential backoff keeps retry runs planned until due, and downstream failure/timeout branches wait for the final attempt. Retry summary projection and Graph/Timeline/Task Inspector rendering first pass are available; exhausted/cancel copy remains open.
- [ ] Join policy 支持 `all` / `any` / `firstMatched`。
  - First pass: [x] Core `AutomationTask.joinPolicy`, reducer dependency resolution, draft import/export/editor/patch/CLI, and node projection support `all`, `any`, and `firstMatched`. UI now has FlowGraph join badges, Task Inspector editing/explanations, a condition-task If/Then/Else branch panel, branch decision summaries in Inspector rows, and selected-run branch context in Run Detail; runtime writes durable `AutomationTaskRun.branchEvidence`, and `product-evidence/branch-evidence-drill-in.png` proves the fixture drill-in. Live recording evidence remains open.
- [ ] Visual condition spec 进入 core contract。
  - First pass: [x] `AutomationConditionKind.visual`, `AutomationVisualCondition`, draft import/export/editor/patch/CLI, and injected evaluator callbacks support `regionChanged`, `imageAppeared`, `imageDisappeared`, and `pixelMatched`. UI can now create/edit visual waits in Workflow/Task Inspector, edit visual draft fields in AI Draft Preview, render `conditionProgress`, choose `pixelMatched` target colors with a shared ColorPicker + hex/swatch control, pick draft/package `visualAssets` region/image/baseline refs in AI Draft Preview, register package-local image/baseline files into draft `visualAssets.images/baselines`, import-copy external image/baseline files into the draft package, and capture a drawn screen region into a package-local baseline PNG. Workflow visualAssets persistence, workflow-scoped package provider binding, and package-root retention first passes can resolve those refs after import records retained package roots; `product-evidence/visual-diagnostics-drill-in.png` proves fixture last-sample/watched-region drill-in plus visual artifact Open/Reveal affordance and feedback. Live screenshot/template recording and managed storage/migration policy remain open.
- [ ] Visual asset/region registry 能让 AI draft/package 保存并恢复 region/image/baseline references。
  - First pass: [x] `AutomationWorkflowDraftDocument.visualAssets` supports package-level regions/images/baselines; validator checks duplicate/invalid assets and missing refs; import materializes `regionRef` into concrete OCR/visual search regions; export writes representable OCR/visual concrete regions into `visualAssets.regions`.
- [ ] Visual package image provider factory 能把 package-local image/baseline refs 接到 live evaluator。
  - First pass: [x] `AutomationWorkflow.visualAssets` preserves visual asset registries through internal workflow/package round trips, and `AutomationVisualAssetImageProviders.workflowPackages(...)` builds request-aware ImageIO-backed image/baseline providers from normalized `visualAssets.images/baselines` paths; draft validator rejects unsafe paths; live condition/runtime factories accept injected providers.
  - First pass: [x] AI Draft Preview can register image/baseline files from the draft source directory into safe package-relative `visualAssets` paths.
  - First pass: [x] AI Draft Preview can copy external image/baseline files into `assets/images` or `assets/baselines` under the draft source directory and register them as package-local assets with SHA-256 metadata.
  - First pass: [x] AI Draft Preview can capture a drawn screen region into `assets/baselines/<key>.png` under the draft source directory and register it as a package-local baseline asset.
  - First pass: [x] Visual asset package-root retention records local roots for confirmed imports, AI Draft Preview imports, workflow package imports, and explicit CLI `--visual-assets-root`, then restores runtime providers through the visual asset roots manifest.
  - Remaining: [ ] managed storage/migration policy, product evidence.
- [ ] Projection 提供 UI 所需状态，不让 SwiftUI 重新推导。
  - First pass: [x] `nextScheduledOccurrence`, `timeoutCountdown`, `retryAttemptSummary`, `joinPolicy` labels, `incomingDependencyCount`, `conditionProgress`, and `resourceWaiting` are computed in core projection for workflow/task nodes and resource timeline items where applicable.

- [ ] Scheduler adapter 支持 occurrence generation 或可靠 tick handoff。
  - First pass: [x] Existing scheduler tick -> reducer path now creates repeating due occurrences; App-host mailbox handoff can deliver CLI requests to a running App host. OS-level wakeup/daemon/background handoff remains.
- [ ] Resource arbiter/runner 支持等待队列，不把 busy 直接当失败。
  - First pass: [x] Busy/denied resource acquisition no longer creates terminal `.resourceConflict`; reducer preserves the wait and resumes by release/tick.
- [ ] Condition evaluator 支持 OCR 文本以外的首批视觉条件。
  - First pass: [x] Evaluator clients can inject a visual provider and default live evaluation now captures display screenshots through `AutomationVisualConditionEvaluatorClient.live`. Pixel/color conditions can evaluate directly; image appeared/disappeared and region changed can evaluate when injected template/baseline providers resolve their references. Workflow-scoped package provider binding, package-root retention, draft/package picker flows, visual asset registry persistence, and AI Draft Preview baseline capture have first passes; fixture product evidence exists for diagnostics drill-in, while live matching recording and deeper progress remain open.
- [x] CLI `workflow macros --json` 存在并返回 AI 可用宏目录。
- [x] CLI `workflow list/show/status/export` 能读取现有 workflow、汇总运行状态，并导出 AI 可编辑 draft。
- [ ] CLI `workflow draft task/dependency/condition set` 能逐步编辑草稿。
  - First pass: [x] `workflow draft init/inspect/normalize/patch/task add/task set/task remove/schedule set/condition set/dependency add/dependency set/dependency remove`。
  - Runtime first pass: [x] `workflow run/cancel/runs`。
  - Runtime handoff first pass: [x] `workflow run/cancel --handoff app` writes App-host mailbox commands consumed by `LiveAutomationRuntimeHost`。
  - Runtime handoff status first pass: [x] `workflow handoff status` reports pending/dispatched/failed/missing through command receipts。
  - Runtime handoff result readback first pass: [x] `workflow handoff status` includes repository-backed `runs` snapshots and optional `workflowStatus` when receipts identify run IDs。
  - Remaining: [ ] daemon/background handoff for waking a non-running App, long-running background sessions, and push-style live progress/result streaming。
- [x] CLI `workflow draft validate` 存在。
- [x] CLI `workflow draft simulate` 存在。
- [x] CLI `workflow import --dry-run` 存在。
- [x] CLI `workflow import --confirm` 走 reducer/repository 合同。
- [ ] 本阶段没有并行开发 MCP server；MCP 只保留为后续包装选项。

## Owner 2: Product UI / UX

- [ ] Workflow 页面能用 fixture 完成创建、拖拽、连线、编辑、删除。
- [ ] Workflow 页面按 Pro macOS 原生生产力工具验收：静止态 UI 隐身，主视觉是 automation data、dependency graph、resource timeline 和 run evidence。
- [ ] Macro Library 能拖拽宏到画布或列表生成 task。
  - First pass: [x] Macro Library can create macro tasks by dragging to FlowGraph canvas or to Workflow Inspector task-list insertion lines.
- [ ] Macro Library 在 UI 上表现为素材库/source bin，不是大色块“添加按钮”面板；拖入后生成 task instance，不污染 `SavedMacro`。
  - First pass: [x] Macro rows are native Buttons plus drag sources, use a quiet handle at rest, reveal add affordance on hover, and route creation to workflow task actions without mutating `SavedMacro`.
- [ ] 拖拽期间 drop target、插入前/后、连接目标和真实结果一致。
  - First pass: [x] Workflow Inspector task list shows row-between insertion lines for macro drops and existing task drops, inserts or reorders at the matching `workflow.tasks` index, keeps up/down icon buttons as the non-drag path, and updates moved task graph position from neighboring projected nodes when possible. `product-evidence/task-reorder-authoring.png` proves the fixture reorder state; full live recording remains open.
- [ ] 新建或拖入 task 后，节点、预览轨迹、连接线或插入结果立即可见；不需要刷新、重新定位或打开 Inspector 才显示。
  - First pass: [x] Macro drops to graph/list immediately dispatch reducer-backed workflow/task updates; list drops also assign a nearby graph position from current projection when available.
- [x] 静止态截图通过 Pro macOS 审查：主视觉是 graph/timeline/run evidence，不是高饱和大色块控件。
  - Evidence: [x] `product-evidence/idle-workflow.png` / `idle-workflow.md` from `AutomationRunState.ownerCFixture`.
- [ ] UI PR 附带 idle、drag/link、running 三种状态截图或录屏，且三种状态都符合克制原生视觉合同。
  - Evidence: [x] idle, connector drag-link, task-reorder, and running fixture screenshots are checked in under `product-evidence/`.
  - Remaining: [ ] full real drag/reorder `.mov` / `.mp4` is still missing, so the broader WYSIWYG evidence gate stays open.
- [ ] 普通节点、边列表、toolbar action 和全宽按钮不靠 `.controlSurface` 或强底色表达重要性；保留例外必须写进 Owner 2 文档。
- [ ] `.controlSurface` 使用审计完成：普通全宽按钮、Macro Library row、静止态 task/condition node、dependency row、toolbar action 和普通 Inspector 分组没有强制高亮底色。
- [ ] 强底色替换后仍保留明确 affordance：connector handle、insertion line、hover/focus outline、selection outline、menu 或按钮替代路径清晰可见。
- [ ] Workflow 静止态的视觉层级正确：用户数据和运行状态先于普通命令；普通添加/编辑按钮不能成为页面最显眼元素。
- [ ] 用户不打开 Inspector，也能完成基本依赖表达：A 成功后运行 B，A 超时后运行通知或补救 task。
  - First pass: [x] FlowGraph connector handles support drag-to-target dependency creation through the existing reducer action path.
- [ ] Inspector 不是唯一创建路径；基础编排可直接在画布/列表完成。
- [ ] Macro Library 作为 source bin 的拖拽主路径通过产品验收：拖入 graph/list 后 task 立即出现在用户放手或插入线对应位置，点击添加只是辅助路径。
- [ ] 条件和依赖能通过箭头、缩进或 `If...Then...Else` 分组被直观看懂。
  - First pass: [x] FlowGraph nodes show a restrained join policy badge for multi-input or non-default join nodes, branch source nodes show a quiet Then / Else / Timeout guide from existing edge projection, selected condition tasks show an Inspector If/Then/Else panel for existing branches, and dependency edges can expose triggered/skipped runtime branch decisions from projection. Persistent branch drill-in fixture screenshot is present; live recording evidence remains open.
- [ ] 条件分支在中心区域直接显示 success/failure/timeout/condition then/else，不只藏在右侧表格。
  - First pass: [x] FlowGraph branch guides expose outgoing Then / Else / Timeout / Cancel / Always summaries near the source node without requiring Inspector selection.
- [ ] 条件和宏的组合不能只是平铺卡片；至少通过箭头、缩进、分组或完整 If/Then panel 强化“如果/那么/否则”的视觉逻辑。
  - First pass: [x] Task Inspector now groups selected condition-task outgoing dependencies into Then / Else / Timeout plus existing Always / Cancel branches with target and delay/trigger detail.
- [ ] 依赖图至少达到 Level 1：用户能在图上通过 connector handle 创建依赖，并直接看到方向、trigger label 和可删除/可编辑入口。
- [ ] 条件分支达到 Level 2 之前不能标为完整：等待文本、等待画面、验证文本等条件要通过箭头、缩进或 `If...Then...Else` panel 表达 then/else/timeout。
  - First pass: [x] Selected condition tasks have an Inspector If/Then/Else panel; center graph branch guide remains the first-pass canvas expression; dependency edges now have branch decision projection. Persistent branch drill-in fixture screenshot is present, but broader screenshot/clip acceptance remains open before this can be marked complete.
- [ ] Macro Library 表现为 source bin：拖出的 `SavedMacro` 生成 `AutomationTask` 实例，同一个宏可多次使用，task/run/evidence 不回写宏模板。
  - First pass: [x] App UI creates a new `AutomationTask` for each macro add/drop and keeps macro row state presentation separate from run/evidence state.
- [ ] 已有 task 能按用户看到的相邻位置重排，并有非拖拽替代路径。
  - First pass: [x] Workflow Inspector task rows can be dragged to row-between insertion lines or moved with up/down icon buttons; the UI rewrites `workflow.tasks` through `.upsertWorkflow`, updates moved task graph position from projected neighbors when possible, and leaves dependencies, macro templates, run history, repository, Player, scheduler, and condition evaluator untouched. `product-evidence/task-reorder-authoring.png` proves fixture reorder evidence; live clip remains open.
- [ ] 运行中的 task 有克制的实时反馈，不使用大面积高饱和底色。
  - First pass: [x] Task Inspector has a restrained Run Control section with confirmation before manual start/cancel.
- [ ] 当前 task 的运行反馈像 Pro 工具的播放头/status hairline/细描边，不使用整卡发光、整块填色或会造成视觉疲劳的大动画。
  - First pass: [x] Graph nodes use projection-driven status hairlines and compact timeout/retry detail instead of saturated full-card fills.
- [ ] Workflow 运行期间，当前执行 task 必须有可见实时反馈，例如呼吸细描边、hairline progress、状态点或资源时间轴推进；不能只更新右侧文字字段。
- [ ] Graph 回答当前执行节点/触发边，timeline 回答资源占用/等待/延后原因，run detail 回答失败证据。
  - First pass: [x] Task Inspector Run History rows can be selected to show run detail metadata, evidence ID, retry-exhausted copy, selected-run branch evidence/context, and next-check guidance. Run Detail can also load macro package per-run evidence from `runs/<evidenceID>/manifest.json` / `report.json` when available, show binding status plus a report-derived diagnostic summary and manifest details, fall back to matching legacy latest evidence, render the saved failure screenshot inline, keep Reveal Report / Open Screenshot actions near the verified binding, report action success/failure inline, and keep report data visible if a saved screenshot cannot be previewed. Dependency edges and Run Detail can show runtime triggered/skipped/disabled branch decisions from durable `AutomationTaskRun.branchEvidence` with projection fallback, including dependency ID, trigger, target run, delay, target join policy, and reason. Condition runs can now show durable `AutomationTaskRun.conditionEvidence` with observed summary, samples, region, score/threshold, diagnostic fields, failure/rejected terminal explanations when available, live/fixture last-sample / watched-region artifact image previews, and artifact Open/Reveal success/failure feedback loaded through `AutomationConditionEvidenceArtifactPresenter`. `product-evidence/failed-run-detail.png` proves per-run evidence binding, report summary, file action affordances/feedback, failed-event guidance, and inline failure screenshot preview from a fixture; `product-evidence/failed-run-preview-unavailable.png` proves the report remains visible when screenshot preview decoding fails; `product-evidence/branch-evidence-drill-in.png` proves durable branch evidence drill-in; `product-evidence/visual-diagnostics-drill-in.png` proves fixture visual diagnostics drill-in with artifact action feedback. Live capture/Open-Reveal recording remains open.
- [ ] 运行时反馈能在 graph 和 resource timeline 同时解释 running/waiting/completed/failed/timeout。
  - First pass: [x] Graph nodes and Resource Timeline rows share restrained `AutomationDisplayStatus` hairline/status chip feedback plus timeout/retry runtime detail from projection.
- [ ] 运行时反馈覆盖三块表面：FlowGraph node 显示当前/等待/失败，dependency edge 显示触发路径，Resource Timeline 显示资源占用和等待队列；三者来自同一 projection。
- [ ] Timeout/retry 运行态反馈能在 graph 和 resource timeline 中展示倒计时、deadline、当前 attempt 和下一次 retry，而不在 SwiftUI 中重新推导。
  - First pass: [x] Graph nodes and Resource Timeline rows render `timeoutCountdown` / `retryAttemptSummary` as compact remaining-time, elapsed-progress, attempt, and planned-retry details without SwiftUI-side run-history scans.
- [ ] 运行态反馈由同一份 projection 驱动，graph/timeline/inspector 不出现互相矛盾的状态。
  - First pass: [x] Workflow row and Workflow Inspector read workflow-level status/statusDetail from `AutomationWorkflowProjection`; Graph/Timeline/Task Inspector timeout and retry details read the node/timeline projection fields.
- [ ] OCR/视觉条件等待反馈由 projection 驱动，Graph/Timeline/Inspector 不拆 condition enum 或重复计算 polling/timeout。
  - First pass: [x] `AutomationTaskNodeProjection.conditionProgress` and `AutomationResourceTimelineItem.conditionProgress` expose condition kind labels, target/detail copy, polling interval, active polling state, timeout countdown, and visual refs. Running and visual diagnostics fixture screenshots are present; live screenshot/clip evidence remains open.
- [ ] FlowGraph 拖拽稳定，不丢节点、不丢线、不需要刷新后才显示。
  - First pass: [x] FlowGraph node movement is parent-owned in `AutomationFlowGraphView`; dragged nodes, dependency curves, and edge labels share dynamic positions while dragging, tiny drags select the task card, and drop commits through `.moveTask`. Macro Library drops to the graph canvas now create tasks at the cursor-centered graph position, and existing task drops move the task there. Real interaction recording remains open.
- [ ] 资源时间轴能解释 running/waiting/conflict/completed。
  - First pass: [x] Resource Timeline shows the next scheduled occurrence from workflow projection before run history exists, and OwnerC fixture covers foreground-input resource waiting with user-facing `resourceWaiting` reason data. Resource waiting projection can also expose max-wait deadline/remaining/fraction when the task sets `maxResourceWaitSeconds`.
- [ ] Inspector 能编辑 schedule、timeout、retry、join policy、condition、dependency trigger。
  - First pass: [x] AI draft preview sheet can edit OCR condition, schedule, dependency set/remove, and task remove with confirmation/undo before import. Task Inspector can edit task-level join policy through reducer-backed `.upsertTask`.
- [ ] Task Inspector 能解释当前 task 的 running/waiting/timeout/retry 状态，并和 graph/timeline 使用同一份 projection。
  - First pass: [x] Task Inspector receives `AutomationTaskNodeProjection` and renders status, deadline, timeout duration, attempt, remaining attempts, next retry, evidence, and next schedule without scanning run history in SwiftUI. Run History separately renders selected `AutomationTaskRun` metadata/evidence ID and next-check copy for past runs.
- [ ] Workflow row、Inspector、节点和 Resource Timeline 能展示下一次计划启动时间，且不在 SwiftUI 中重新计算 schedule。
  - First pass: [x] They read `AutomationWorkflowProjection.nextScheduledOccurrence` / `nextScheduledTaskID` and node `nextScheduledOccurrence`.
- [ ] UI 不直接调用 Player、scheduler、repository、condition evaluator。
- [ ] 普通 Workflow 控件不使用 Web 风格高饱和全宽色块或无必要 `.controlSurface` 强调。
- [ ] 页面静止状态下像 Pro macOS 编排台，而不是由一组大色块 Web 按钮组成的 dashboard。
- [ ] Owner 2 视觉例外日志为空；如不为空，每条例外都有原因、状态范围和移除计划。
- [ ] 大量节点/连线下 Canvas 和 projection 渲染不卡顿。
- [ ] AI draft 导入前有 preview、validation warnings 和 macro resolution UI。
  - First pass: [x] Preview sheet shows validation issues, macro resolution, simulation, import dry-run, batch patch apply, and in-memory edit/rebuild feedback.
- [ ] 现有 workflow 能作为 AI 可编辑 draft 导出、检查 warning、再进入预览/导入链路。
  - First pass: [x] Single selected workflow can export `sparkle.workflow.draft.v1` JSON from Workflow Inspector with lossy warning feedback.

## Product Scenarios

- [ ] 串联两个宏并手动运行。
- [ ] 定时启动一个 workflow，并生成每次独立 run history。
  - First pass: [x] UI shows the next scheduled occurrence from projection; reducer clock ticks create independent due repeating runs. Product-level wakeup/background handoff remains.
- [ ] 两个前台输入任务冲突时，一个运行、一个等待，释放后继续。
  - First pass: [x] Reducer/resource path keeps the second run waiting after denial and reissues resource request after the first run releases. Max-wait timeout first pass can complete expired waiters as `.timedOut(deadline:)`; priority, preemption, and cross-process policy remain open.
- [ ] OCR 等待文本超时后走 timeout 分支。
  - First pass: [x] Reducer watchdog now triggers `.timedOut` branches for queued/running tasks with `AutomationTask.timeout`; Graph/Timeline can show timeout countdown from projection, and condition waits can expose `conditionProgress`. Product rendering/evidence remains open.
- [ ] 区域变化或图标出现条件能触发下游。
  - First pass: [x] Draft/import/core/evaluator-provider contract can express these conditions, route fake evaluator outcomes through the existing condition path, project what the visual wait is watching, preserve package-level `visualAssets` refs, and expose first-pass UI authoring in Workflow/Task Inspector plus AI Draft Preview. Pixel color picker, draft/package visual asset registry/picker, package-local image/baseline file registration, external image/baseline import-copy, AI Draft Preview baseline capture, app-edge visual package image provider, workflow-scoped package provider binding, and package-root retention first passes are available; fixture product evidence exists for running wait and diagnostics drill-in, while live screenshot matching recording and managed storage/migration policy remain open.
- [ ] AI 根据宏库生成 draft，validate/simulate/import 后能在 UI 中运行。

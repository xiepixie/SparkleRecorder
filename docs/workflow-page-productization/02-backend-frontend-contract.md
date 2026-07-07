# Engine To UI Contract

本文件是两人协作的主沟通渠道，规定 Engine owner 的能力如何交付给 UI owner。目标是让后端进度能够及时变成前端可开发的 projection/action/fixture，而不是只停在“代码已经有了”。

## 基本规则

- Engine owner 不直接要求 UI 读内部 state。
- UI owner 不在 SwiftUI `body` 中补状态机、DAG 解析、资源仲裁或文件 IO。
- 每个跨 owner 能力必须有请求、接受、测试和样例 projection。
- 后端完成不是“类型存在”，而是前端能通过 projection/action 使用。

## Communication Channels

本阶段只保留两个 owner：

- Owner 1: Engine, Runtime, And AI CLI，工作文件是 [workstreams/engine-runtime-ai.md](workstreams/engine-runtime-ai.md)。
- Owner 2: Product UI And Workflow UX，工作文件是 [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md)。

沟通写法：

1. 跨边界合同写在本文件：新 action、projection 字段、CLI output、fixture、validation warning 都必须先在这里登记。
2. 各自计划写在自己的 workstream 文件：任务清单、风险、实现日志、测试证据写到各自文件。
3. 请求双写但主次明确：请求方在自己的 workstream 记录摘要，完整请求写到本文件；接受方在自己的 workstream 写接受、拒绝或替代方案。
4. 完成状态只在本文件升级：`proposed -> accepted -> implemented -> tested -> ready-for-ui`。没有测试和 fixture 不得标 `ready-for-ui`。
5. 争议不散落聊天记录：未决问题写在本文件的 open questions，解决后移动到 accepted contracts。

## Backend Capability Notice

Engine owner 每完成一个会影响 UI 的能力，必须先在本文件写一条 notice，再同步到自己的 workstream 文件。UI owner 只把 `ready-for-ui` 的 notice 当真实能力接入。

模板：

```md
### Capability: <short name>

- Owner: Engine
- Status: proposed | accepted | implemented | tested | ready-for-ui
- User-facing capability:
- New or changed types:
- New or changed `AutomationAction` / `AutomationEffect`:
- Projection fields UI should read:
- Fixture/example state:
- Tests:
- Migration/backward compatibility:
- Open UI questions:
```

只有状态到 `ready-for-ui`，UI owner 才能把它当成真实能力设计交互。

### Capability: Workflow Draft Validation CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以对 `sparkle.workflow.draft.v1` 草稿执行只读校验，得到可展示的 errors、warnings 和 nextActions。
- New or changed types: `AutomationWorkflowDraftDocument`, `AutomationWorkflowDraft`, `AutomationWorkflowDraftTask`, `AutomationWorkflowDraftDependency`, `AutomationWorkflowDraftIssue`, `AutomationWorkflowDraftValidator`, `AutomationCLIResultEnvelope`, `AutomationWorkflowDraftValidationPayload`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This command is read-only and does not import, persist, or run workflows.
- Projection fields UI should read: None. UI/AI preview should consume the CLI JSON envelope `sparkle.cli.result.v1`.
- Fixture/example state: Any draft JSON using schema `sparkle.workflow.draft.v1`; optional macro catalog JSON is accepted through `--macro-catalog`.
- Tests: `AutomationWorkflowDraftTests`; CLI smoke command `swift run SparkleRecorder workflow draft validate <draft.json> --json`.
- Migration/backward compatibility: External draft schema is versioned and separate from internal `AutomationWorkflow` Codable. Unsupported schemas return `unsupportedSchema`.
- Open UI questions: Import preview now has dry-run and confirmed import CLI first pass; UI still needs review, confirmation, rollback/cancel wording, and repository refresh flow.

### Capability: Workflow Macro Catalog CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以读取本地宏库目录，拿到真实宏 ID、名称、标签、备注、时长、事件统计、资源需求和窗口/应用摘要，避免生成草稿时编造宏 ID。
- New or changed types: `AutomationWorkflowDraftMacroCatalogEntry`, `AutomationWorkflowDraftSurfaceSummary`, `AutomationWorkflowMacroCatalogPayload`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This command is read-only and does not import, persist, or run workflows.
- Projection fields UI should read: None. UI/AI preview should consume the CLI JSON envelope `sparkle.cli.result.v1`.
- Fixture/example state: `.sparkrec` packages under the normal macro directory, or a fixture directory passed via `--macros-dir`.
- Tests: `AutomationWorkflowDraftTests`; CLI smoke command `.build/debug/SparkleRecorder workflow macros --macros-dir <fixture> --search <term> --json`.
- Migration/backward compatibility: Reads current `.sparkrec/macro.json` and `events.json`; falls back to legacy `library.json` for read-only catalog output if the new directory is absent.
- Open UI questions: UI import preview still needs macro resolution UI for ambiguous/missing references and confirmed-write review.

### Capability: Workflow Draft Simulation CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以在不移动鼠标、不触发真实 Player 的情况下预览 draft 会按什么顺序运行、哪些依赖边会触发、哪些 task 会被跳过、前台输入资源预计被哪些 task 占用。
- New or changed types: `AutomationWorkflowDraftSimulationResult`, `AutomationWorkflowDraftSimulationStep`, `AutomationWorkflowDraftResourceOccupancy`, `AutomationWorkflowDraftBranchDecision`, `AutomationWorkflowDraftSimulationScenario`, `AutomationWorkflowDraftSimulator`, `AutomationWorkflowDraftSimulationPayload`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This command is read-only and deterministic.
- Projection fields UI should read: None. UI/AI preview should consume the CLI JSON envelope `sparkle.cli.result.v1`.
- Fixture/example state: Any valid `sparkle.workflow.draft.v1` JSON; optional macro catalog JSON is accepted through `--macro-catalog`.
- Tests: `AutomationWorkflowDraftTests`; CLI smoke command `.build/debug/SparkleRecorder workflow draft simulate <draft.json> --macro-catalog <catalog.json> --scenario timeout:<taskKey> --json`.
- Migration/backward compatibility: This is draft-level simulation, not live runtime execution. It intentionally does not call Player, Scheduler, Repository, ResourceArbiter, condition evaluator, OCR, or macOS APIs.
- Open UI questions: Runtime queue/retry/resource conflicts still need separate ready-for-ui notices. Confirmed import is ready at the CLI contract level, but UI still needs review and repository refresh handling.

### Capability: Workflow Import Dry-Run CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以在不写入 `automations.json`、不启动 Player 的情况下，把 `sparkle.workflow.draft.v1` 编译成内部 `AutomationWorkflow` 预览，看到 task/dependency ID 映射、宏解析结果、导入阻塞错误和可审阅 warnings。
- New or changed types: `AutomationWorkflowDraftImportOptions`, `AutomationWorkflowDraftImportResult`, `AutomationWorkflowDraftMacroResolution`, `AutomationWorkflowDraftImporter`, `AutomationWorkflowDraftImportPayload`。
- New or changed `AutomationAction` / `AutomationEffect`: None. `workflow import --dry-run` is read-only and does not persist workflows.
- Projection fields UI should read: None. UI/AI preview should consume the CLI JSON envelope `sparkle.cli.result.v1`.
- Fixture/example state: Any valid `sparkle.workflow.draft.v1` JSON; optional macro catalog JSON is accepted through `--macro-catalog`.
- Tests: `AutomationWorkflowDraftTests`; CLI smoke command `.build/debug/SparkleRecorder workflow import <draft.json> --dry-run --macro-catalog <catalog.json> --json`.
- Migration/backward compatibility: External draft schema remains separate from internal `AutomationWorkflow`. Dry-run compiles into internal values with stable IDs for review; confirmed persistence is a separate explicit command.
- Open UI questions: UI should present `macroResolutions`, `taskKeyToID`, `dependencyKeyToID`, and warnings such as `unresolvedRegionRef`; confirmed write still needs a product review/rollback/refresh flow.

### Capability: Workflow Confirmed Import CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户在 dry-run 审阅通过后，可以显式运行 `workflow import <draft.json> --confirm --json`，把 draft 编译后的静态 workflow 写入 `automations.json`。命令只导入工作流，不启动 Player、不移动鼠标键盘、不写 `SavedMacro` 运行状态。
- New or changed types: `AutomationWorkflowDraftImportMode.confirm`; `AutomationWorkflowDraftImportResult` 和 `AutomationWorkflowDraftImportPayload` 复用 dry-run payload，并通过 `mode: "confirm"` 表达确认写入结果。
- New or changed `AutomationAction` / `AutomationEffect`: CLI 写入必须通过 reducer `.upsertWorkflow(workflow, at:)`，并执行 reducer 产出的 `.persistWorkflows` effect；CLI 不直接编辑 repository JSON。
- Projection fields UI should read: None directly. UI/AI preview should consume `sparkle.cli.result.v1` confirmed import envelope, then refresh repository/live projection 来显示新 workflow。
- Fixture/example state: Any importable `sparkle.workflow.draft.v1` JSON with resolvable macros. CLI supports `--repository-dir <dir>` for tests and smoke verification without touching real Application Support.
- Tests: `AutomationWorkflowDraftTests` covers confirm envelope mapping; CLI smoke command `.build/debug/SparkleRecorder workflow import <draft.json> --confirm --repository-dir <fixtureRepo> --macro-catalog <catalog.json> --json`.
- Migration/backward compatibility: External draft schema remains separate from internal `AutomationWorkflow`. Import uses stable IDs derived from workflow/task/dependency keys and repository save semantics preserve existing `runHistory`; repeated import of the same workflow name upserts the same workflow ID.
- Open UI questions: App UI now has confirmation review, duplicate/upsert wording, reducer-backed `.upsertWorkflow`, post-import Refresh, Undo Import, Restore Previous, and confirmed Delete Workflow first pass. Fine-grained draft editing/status remains open. Confirmed import does not imply the workflow is safe to run; runtime still needs separate user approval.

### Capability: Workflow Draft Editing CLI First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以逐步创建和修改 `sparkle.workflow.draft.v1`，不用每次重写整份 JSON。当前 first pass 支持 `workflow draft init`、`inspect`、`normalize`、`task add`、`task set`、`task remove`、`schedule set`、`condition set`、`dependency add`、`dependency set` 和 `dependency remove`。
- New or changed types: `AutomationWorkflowDraftEditor`, `AutomationWorkflowDraftEditResult`, `AutomationWorkflowDraftEditPayload`, `AutomationWorkflowDraftEditError`; `AutomationWorkflowDraftTask.pollingSeconds` 用于把等待条件的轮询间隔传入 import 后的 `AutomationConditionSpec.pollingInterval`。
- New or changed `AutomationAction` / `AutomationEffect`: None. Draft editing is external-file editing only; it never writes `automations.json` and never starts Player.
- Projection fields UI should read: None directly. UI/AI draft tools should consume the `sparkle.cli.result.v1` edit envelope; `data.document` is the edited draft, `data.isValid` is current validation state, and `changedTaskKeys` / `changedDependencyKeys` identify what changed.
- Fixture/example state: The battle-exit flow can now be built and revised from an empty draft with CLI commands: init -> task add -> condition set -> dependency add -> schedule set -> dependency set/remove -> task remove -> normalize -> validate -> simulate -> import dry-run/confirm.
- Tests: `AutomationWorkflowDraftTests` covers incremental editor construction, invalid intermediate edit envelopes, duplicate task rejection, polling interval import, dependency/schedule updates, task removal cleanup, and normalization. CLI smoke covered the full battle-exit sequence, dependency/schedule edits, task removal/re-add, normalization, dry-run, and confirmed import into a fixture repository.
- Migration/backward compatibility: Existing drafts decode because `pollingSeconds` is optional. Edit commands only write a draft file when `--out` is explicit; otherwise they print the edited document in the JSON envelope.
- Open UI questions: App UI now consumes the shared editor path for OCR `condition set`, `schedule set`, `dependency set`, `dependency remove`, and `task remove` inside the AI draft preview sheet and rebuilds validation/simulation/import dry-run in memory after each apply. `task remove` has a destructive confirmation and local Undo because it can remove attached dependencies. Batch `patch` has a preview-sheet first pass through the patch applier. Remaining UI polish: runtime control and batch/deeper export review UI.

### Capability: Workflow Draft Patch CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或高级用户可以把一组 draft 编辑操作放进 `sparkle.workflow.patch.v1`，一次性应用到 `sparkle.workflow.draft.v1`，避免反复重写整份 JSON 或逐条调用 CLI。
- New or changed types: `AutomationWorkflowDraftPatchSchema`, `AutomationWorkflowDraftPatchDocument`, `AutomationWorkflowDraftPatchOperation`, `AutomationWorkflowDraftPatchApplier`。
- New or changed `AutomationAction` / `AutomationEffect`: None. Patch editing is external draft editing only; it never writes `automations.json`, never starts Player, and never touches `SavedMacro` runtime state.
- Projection fields UI should read: None directly. UI/AI draft tools should consume the `sparkle.cli.result.v1` edit envelope returned by `workflow draft patch`; `data.document` is the patched draft, `data.isValid` is current validation state, and `changedTaskKeys` / `changedDependencyKeys` are merged across all operations.
- Fixture/example state: `workflow draft patch battle.json patch.json --out battle.json --json`; patch schema supports `addTask`, `setTask`, `removeTask`, `setSchedule`, `setCondition`, `addDependency`, `setDependency`, `removeDependency`, and `normalize`.
- Tests: `AutomationWorkflowDraftTests` covers batch patch apply and unsupported operation rejection. CLI smoke covered patch -> write `--out` -> validate with a fixture macro catalog.
- Migration/backward compatibility: Patch schema is versioned as `sparkle.workflow.patch.v1` and separate from both internal `AutomationWorkflow` Codable and external draft schema. Existing draft editing commands remain valid.
- Open UI questions: App UI now has a preview-sheet Apply Patch entry that opens a `sparkle.workflow.patch.v1` JSON, applies it in memory through `AutomationWorkflowDraftPatchApplier`, shows changed task/dependency keys, and rebuilds validation/simulation/import dry-run before import. Direct preview controls can keep using the existing in-memory editor calls when that is more ergonomic.

### Capability: Workflow Read And Draft Export CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以读取现有 `automations.json` 中的 workflow，查看 workflow/run summary，并把内部 `AutomationWorkflow` 导出为 AI 可编辑的 `sparkle.workflow.draft.v1`。
- New or changed types: `AutomationWorkflowDraftExporter`, `AutomationWorkflowDraftExportResult`, `AutomationWorkflowDraftExportPayload`, `AutomationWorkflowSummary`, `AutomationWorkflowListPayload`, `AutomationWorkflowShowPayload`, `AutomationWorkflowDraftIssueCode.lossyWorkflowExport`。
- New or changed `AutomationAction` / `AutomationEffect`: None. `workflow list/show/export` are read-only for app state; `workflow export --out` only writes an external draft JSON file.
- Projection fields UI should read: None directly. UI/AI tools should consume `sparkle.cli.result.v1`; export payload includes `result.document`, `taskIDToKey`, `dependencyIDToKey`, `issues`, and optional `wrotePath`.
- Fixture/example state: Any repository directory containing `automations.json`; commands accept `--repository-dir <dir>` for fixture/smoke verification.
- Tests: `AutomationWorkflowDraftTests` covers workflow-to-draft export, export warnings for lossy OCR region conversion, and list/show run-history summaries. CLI smoke covers import-confirm fixture -> list -> show -> export.
- Migration/backward compatibility: Export generates stable task keys from task name plus UUID prefix because internal `AutomationWorkflow` currently does not persist original draft keys. OCR region bounds are not fully representable in draft v1, so export emits `lossyWorkflowExport` warnings instead of pretending the round trip is lossless.
- Open UI questions: App UI now has a single-workflow Export AI Draft button with save destination, pretty JSON output, and lossy warning feedback. Batch patch is handled in the draft preview sheet. Batch draft export, richer export review, and runtime views remain open.

### Capability: Workflow Status CLI

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以读取全部 workflow 或单个 workflow 的运行状态摘要，看到哪些任务未运行、已计划、等待上一步、等待鼠标键盘空闲、准备执行、正在执行、已完成或需要处理。
- New or changed types: `AutomationWorkflowStatusKind`, `AutomationTaskStatusSummary`, `AutomationWorkflowStatus`, `AutomationWorkflowStatusPayload`。
- New or changed `AutomationAction` / `AutomationEffect`: None. `workflow status` is read-only and does not create runs, cancel runs, acquire resources, start Player, or mutate repository state.
- Projection fields UI should read: CLI/AI tools can consume `sparkle.cli.result.v1` status data. App projection now also exposes workflow-level `AutomationWorkflowProjection.status` / `statusDetail` derived from task projection statuses for list and inspector summaries.
- Fixture/example state: Any repository directory containing `automations.json` and run history; commands accept `--repository-dir <dir>` for fixture/smoke verification. `workflow status --json` lists all workflows, and `workflow status <workflow-id> --json` filters one workflow.
- Tests: `AutomationWorkflowDraftTests` covers running, waiting-for-resource, and failed task status payloads. CLI smoke covers import-confirm fixture -> status all -> status single workflow.
- Migration/backward compatibility: This is a read-tier command. It does not change the internal workflow schema or external draft schema.
- Open UI questions: App UI now shows a first-pass workflow-level status summary in list rows and Workflow Inspector. Task Inspector has App-local run/cancel confirmation through existing reducer actions, and CLI `workflow run/cancel/runs` now has a first pass. Next scheduled occurrence, timeout countdown, retry attempt, condition progress, and resource waiting reason projections are ready; live graph/timeline polish still needs deeper resource queue policy, visual-condition product rendering, join policy grouping, and restrained runtime evidence.

### Capability: Workflow Runtime Control CLI First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI 或用户可以显式确认后从一个 workflow task 启动运行，读取 workflow run history，并对 repository snapshot 中可见的非终态 run 发出取消。运行命令可能移动鼠标键盘，所以必须传 `--confirm` 或 `--yes`。
- New or changed types: `AutomationWorkflowRunPayload`, `AutomationWorkflowCancelPayload`, `AutomationWorkflowRunsPayload`, `AutomationRuntimeHandoffPayload`, and `AutomationRuntimeHandoffStatusPayload` for handoff envelopes. `AutomationRuntimeHandoffStatusPayload` now includes `runs` snapshots and optional `workflowStatus` read from repository run history when a receipt identifies created/cancelled run IDs.
- New or changed `AutomationAction` / `AutomationEffect`: `workflow run` 通过 `AutomationRuntimeSession` dispatch `.manualStart(workflowID:taskID:requestedAt:)`，由 reducer/effect runner 创建 run、请求资源、启动 Player/condition/delay/notification 并持久化 terminal run。`workflow cancel` dispatch `.cancelRun(runID:at:)`，不直接改 repository JSON。
- Projection fields UI should read: CLI/AI tools consume `sparkle.cli.result.v1` runtime envelopes. App UI should still use runtime host/projection actions directly rather than shelling out to CLI.
- Fixture/example state: `workflow run <workflow-id> --task <task-id-or-exact-name> --confirm --repository-dir <fixture> --player-mode fakeSuccess --json`; `workflow run <workflow-id> --task <task> --confirm --handoff app --repository-dir <fixture> --json`; `workflow handoff status <command-id> --repository-dir <fixture> --json` returns receipt state plus `runs` / `workflowStatus` after the App host has consumed the command and persisted run history; `workflow runs <workflow-id> --repository-dir <fixture> --json`; `workflow cancel <run-id> --confirm --repository-dir <fixture> --json`。
- Tests: `AutomationWorkflowRuntimeCLITests` covers runtime payload/envelope semantics, including handoff payload/status payloads, run snapshot/status payload fields, and old status JSON decoding without the new fields. CLI smoke covered draft init -> delay task add -> import confirm into fixture repository -> `workflow run --confirm --player-mode fakeSuccess` -> `workflow runs`, plus `workflow run --confirm --handoff app` writing `automation-runtime-handoff.json` and `workflow handoff status` reporting pending state.
- Migration/backward compatibility: Adds new CLI commands and payloads only. Existing read/import/draft commands are unchanged. `workflow run` can infer the single enabled root task, but otherwise requires `--task`.
- Open UI questions: `workflow cancel` without handoff can only cancel runs visible to the command's repository snapshot. `--handoff app` now gives CLI/AI a first-pass App-host delivery path when the App is running, and `workflow handoff status` gives a receipt/status polling path with repository-backed run snapshots when available; true daemon/background long-running sessions, App wakeup, and push-style live progress/result delivery remain future work.

### Capability: Runtime App-Host Handoff Mailbox First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: CLI/AI can ask the running SparkleRecorder App host to start a workflow task or cancel a run without launching Player in the CLI process, then query whether the App host has dispatched or failed that command. This is the first step toward cross-process runtime control.
- New or changed types: `AutomationRuntimeHandoffCommandKind`, `AutomationRuntimeHandoffCommand`, `AutomationRuntimeHandoffReceiptStatus`, `AutomationRuntimeHandoffReceipt`, `AutomationRuntimeHandoffMailboxDocument`, `AutomationRuntimeHandoffMailbox`, `AutomationRuntimeHandoffStore`, `AutomationInMemoryRuntimeHandoffStore`, `AutomationRuntimeHandoffClient`, `AutomationRuntimeHandoffPayload`, `AutomationRuntimeHandoffStatusPayload`.
- New or changed `AutomationAction` / `AutomationEffect`: No reducer or effect changes. Handoff commands map to existing `.manualStart(workflowID:taskID:requestedAt:)` and `.cancelRun(runID:at:)` actions. `LiveAutomationRuntimeHost` polls the mailbox and dispatches those actions through its existing `AutomationRuntimeSession`.
- Projection fields UI should read: None. UI can keep using existing runtime host actions and projection. CLI/AI tools consume the standard `sparkle.cli.result.v1` envelope with `AutomationRuntimeHandoffPayload` and `AutomationRuntimeHandoffStatusPayload`.
- Fixture/example state: `workflow run <workflow-id> --task Start --confirm --handoff app --repository-dir <fixture> --json` writes `automation-runtime-handoff.json` with one `manualStart` command. A running App host using the same repository consumes the command, atomically removes it, and writes an `AutomationRuntimeHandoffReceipt`. `workflow handoff status <command-id> --repository-dir <fixture> --json` returns `pending`, `dispatched`, `failed`, or `missing`.
- Tests: `AutomationOwnerBClientTests.runtimeHandoffCommandsMapToReducerActions`, `runtimeHandoffMailboxQueuesSortsAndRemovesCommands`, `AutomationWorkflowRuntimeCLITests.workflowHandoffPayloadReportsQueuedAppHostCommand`, `workflowHandoffStatusPayloadReportsReceiptState`, targeted Swift Testing filter for Owner B/runtime CLI, and CLI smoke for `workflow run --handoff app` + `workflow handoff status`.
- Migration/backward compatibility: Default `workflow run` / `workflow cancel` behavior is unchanged unless `--handoff app` is supplied. Missing mailbox means no pending commands. v1 mailbox documents without receipts decode as empty receipt lists and are rewritten as v2 on save. This first pass uses a file mailbox, not XPC; it does not keep CLI sessions alive, push progress events back to the CLI, or wake a non-running App.
- Open UI questions: UI does not need to consume the mailbox directly. Product-level background wakeup, login item/daemon ownership, and live progress/result streaming are future runtime-host work.

### Capability: Next Scheduled Occurrence Projection

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: UI 可以直接展示 workflow/task 下一次计划运行时间，不需要在 SwiftUI 中解析 once/repeating schedule 或扫描 run history。
- New or changed types: `AutomationScheduledOccurrence`, `AutomationSchedule.nextOccurrence(onOrAfter:excludingScheduledStartTimes:)`, `AutomationRepeatRule.nextOccurrence(onOrAfter:excludingScheduledStartTimes:)`, `AutomationTaskNodeProjection.nextScheduledOccurrence`, `AutomationWorkflowProjection.nextScheduledOccurrence`, `AutomationWorkflowProjection.nextScheduledTaskID`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This is projection-only and pure value calculation.
- Projection fields UI should read: Node cards/inspectors read `AutomationTaskNodeProjection.nextScheduledOccurrence`; workflow rows/inspectors read `AutomationWorkflowProjection.nextScheduledOccurrence` and `nextScheduledTaskID`.
- Fixture/example state: A workflow with a future once task and a repeating task whose current occurrence is already represented by a run will project the once task as workflow-level next occurrence and the repeating task's next unrepresented interval at the node level.
- Tests: `AutomationScheduleOccurrenceTests` covers once, repeating, excluded occurrences, and end rules. `AutomationViewProjectionTests.nextScheduledOccurrenceIsProjectedOutsideSwiftUI` covers node/workflow projection.
- Migration/backward compatibility: Adds optional projection fields and a pure schedule helper. Existing workflows and run history remain compatible.
- Open UI questions: Workflow row, Workflow Inspector, FlowGraph node, and Resource Timeline UI now display the projected next occurrence. Repeating scheduled run generation now has a reducer first pass, but product-level background wakeup/daemon handoff and future multi-occurrence timeline preview remain separate tasks.

### Capability: Repeating Scheduled Run Generation First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: 每次 scheduler `clockTick` 到来时，reducer 会把 repeating schedule 的下一个已到期但尚未由 run history 表示的 occurrence 创建为独立 `AutomationTaskRun`。同一个宏一夜运行多次，会有多个 run/execution ID 和各自的 scheduled start time。
- New or changed types: `AutomationSchedule.nextDueOccurrence(onOrBefore:excludingScheduledStartTimes:)`, `AutomationRepeatRule.nextDueOccurrence(onOrBefore:excludingScheduledStartTimes:)`。
- New or changed `AutomationAction` / `AutomationEffect`: No new action. Existing `.clockTick(Date)` now creates the due occurrence through the same `createRun` / `prepareRun` path as one-shot schedules. Existing effects such as `.wait`, `.requestResource`, `.startPlayer`, `.evaluateCondition`, and `.persistRun` continue to describe the live work.
- Projection fields UI should read: None new. UI should keep reading `nextScheduledOccurrence` projection and runtime/timeline projection; SwiftUI should not call the schedule helper directly.
- Fixture/example state: A repeating task with anchor `10:00`, one represented run at `10:00`, and a `clockTick` at `11:00` creates a new run scheduled for `11:00`. A second `clockTick` at the same time does not create a duplicate. If the schedule ended after two occurrences and both are represented, no new run is created.
- Tests: `AutomationReducerTests.clockTickCreatesNextDueRepeatingScheduledRun`, `AutomationReducerTests.clockTickDoesNotCreateRepeatingRunAfterScheduleEnd`, and `AutomationScheduleOccurrenceTests` cover due occurrence selection, exclusion, future prevention, and end rules.
- Migration/backward compatibility: Existing workflows and run history are compatible. This is pure reducer/runtime behavior; no repository schema change and no UI schema change. The reducer deliberately creates at most one due occurrence per task per tick to avoid flooding after long downtime.
- Open UI questions: This first pass does not implement OS-level wakeup, login-item scheduling, daemon handoff, or a UI preview of many future occurrences. Retry, timeout watchdog, and join policy remain separate tasks; resource waiting has its own first-pass notice below.

### Capability: Resource Waiting Queue/Resume First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: 当前台键鼠等独占资源被占用时，run 不再默认失败为 `resourceConflict`，而是保持 `waitingForResource`。资源释放或 scheduler tick 后，reducer 会重新发出 `.requestResource`，让等待中的任务继续尝试运行；如果 task 配置了最大资源等待时间，到期会走 `.timedOut(deadline:)`，从而触发既有 timeout 分支或 retry 策略。
- New or changed types: `AutomationResourceRequirement.maxWaitDuration` stores the resource-wait deadline policy separately from `leaseTimeout`; draft/AI schema uses `AutomationWorkflowDraftTask.maxResourceWaitSeconds`; projection exposes deadline/remaining/fraction in `AutomationResourceWaitingProjection`.
- New or changed `AutomationAction` / `AutomationEffect`: `.resourceLeaseDenied` semantics changed from terminal failure to non-terminal wait. `.clockTick`, normal terminal lease release, and `.panicRelease` now retry runs in `waitingForResource` through `.requestResource`. `.clockTick` also expires resource waits whose `maxWaitDuration` elapsed by completing them as `.timedOut(deadline:)` through the normal release/persist/downstream path. `.resourceLeaseAcquired` / `.resourceLeasesAcquired` only start runs that are still waiting, preventing stale duplicate acquire actions from restarting queued/running work.
- Projection fields UI should read: Queue/resume status still appears through task/run status projection. For detailed user-facing reason, UI should read `resourceWaiting.detail`, `resources`, `resourceLabels`, `priorityLabel`, `waitingSince`, `waitedDuration`, `maxWaitDuration`, `deadline`, `remainingDuration`, `elapsedFraction`, and `blockers` instead of rebuilding resource/lease state in SwiftUI.
- Fixture/example state: Run A holds `.foregroundInput`; Run B requests `.foregroundInput` and receives `.resourceLeaseDenied`, so it remains `waitingForResource` with no outcome. When Run A completes and releases its lease, reducer emits `.releaseResource` then `.requestResource` for Run B before newly-created downstream work. If Run B has `maxWaitDuration = 5` and the scheduler ticks after 5 seconds, it completes as `.timedOut(deadline:)` and timeout dependencies can fire. OwnerC fixture also includes a foreground-input `waitingForResource` task and planned retry task for UI review.
- Tests: `AutomationReducerTests.resourceDeniedKeepsRunWaitingWithoutTerminalFailure`, `resourceReleaseRetriesWaitingRunsBeforeDownstreamWork`, `clockTickRetriesRunsWaitingForResources`, `clockTickTimesOutResourceWaitAfterMaxWaitDuration`, `resourceLeaseDeniedTimesOutExpiredResourceWaitImmediately`, `AutomationWorkflowDraftTests.draftResourceMaxWaitImportsExportsEditsAndPatches`, `AutomationContractTests.resourceRequirementMaxWaitStaysCodableCompatible`, `AutomationViewProjectionTests.resourceWaitingReasonIsProjectedOutsideSwiftUI`, and existing resource runtime/session tests cover the first pass.
- Migration/backward compatibility: Existing workflows and run history remain compatible. Future `resourceConflict` outcomes can still represent hard resource failures, but live arbiter busy/denied is now treated as wait/retry by default.
- Open UI questions: User-configurable priority policy, lease-expiration watchdog UI, resource preemption, and cross-process resource coordination remain open. UI can safely show waiting/resource queue state, max wait countdown, and timeout outcome routing from projection, but should not promise preemption or OS-level resource arbitration yet.

### Capability: Resource Waiting Reason Projection First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: UI 可以解释一个 task 为什么在等资源、等了多久、需要哪些资源、优先级是什么，以及当前 active lease 是否能指出阻塞它的 run/task。用户看到的是“等待鼠标键盘空闲 / 被某个任务占用”，不是内部 `lease denied`。
- New or changed types: `AutomationResourceWaitingProjection`, `AutomationResourceBlockerProjection`, `AutomationTaskNodeProjection.resourceWaiting`, `AutomationResourceTimelineItem.resourceWaiting`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This is projection-only and computed from workflow tasks, visible runs, active leases, and `generatedAt`.
- Projection fields UI should read: Node cards/inspectors read `AutomationTaskNodeProjection.resourceWaiting`; Resource Timeline rows read `AutomationResourceTimelineItem.resourceWaiting`. Fields include `detail`, `resources`, `resourceLabels`, `priority`, `priorityLabel`, `waitingSince`, `waitedDuration`, optional `maxWaitDuration`, optional `deadline`, optional `remainingDuration`, optional `elapsedFraction`, and `blockers` with blocker `resource`, `resourceLabel`, `runID`, optional `taskID`, optional `taskTitle`, and optional `leaseExpiresAt`.
- Fixture/example state: OwnerC fixture exposes `Wait for mouse handoff` with `resourceWaiting.detail = "Waiting for mouse and keyboard"`, foreground-input resource labels, normal priority, and deterministic waited duration. A projection test also covers an active foreground lease where `Needs input next` is blocked by `Holding input`.
- Tests: `AutomationViewProjectionTests.ownerCFixtureExposesResourceWaitingAndRetryReviewStates` and `resourceWaitingReasonIsProjectedOutsideSwiftUI` cover node/timeline parity, waiting duration, resource ordering, priority label, and active lease blocker mapping.
- Migration/backward compatibility: Adds optional projection fields only. Existing workflows/run history remain compatible; non-waiting runs project `resourceWaiting = nil`.
- Open UI questions: This projection does not decide scheduling priority, lease preemption, or cross-process arbitration. It exposes current waiting reason, visible blockers, and max-wait countdown data so UI can render a clear explanation without reimplementing resource queue semantics.

### Capability: Timeout Watchdog First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: task 已经进入 queued/running 后，如果超过 `AutomationTask.timeout`，reducer 会在 `.clockTick` 中自动把 run 完成为 `.timedOut(deadline:)`，取消仍在运行的宏、释放资源，并通过现有 dependency 解析触发 timeout 分支。
- New or changed types: None. Existing `AutomationTask.timeout`, `AutomationOutcome.timedOut(deadline:)`, `AutomationAction.clockTick`, `AutomationEffect.cancelPlayer`, `AutomationEffect.releaseResource`, and timeout dependency triggers are reused.
- New or changed `AutomationAction` / `AutomationEffect`: `.clockTick(Date)` now runs a timeout watchdog before resource retry and due-run creation. For queued/running macro tasks it emits `.cancelPlayer(runID:)` before terminal cleanup. Existing `completeRun` still owns release, persist, waiting-resource retry, and downstream resolution.
- Projection fields UI should read: UI can show terminal timeout through existing task/run status projection and timeout dependency edges. Runtime feedback projection first pass now also exposes `AutomationTaskNodeProjection.timeoutCountdown` and `AutomationResourceTimelineItem.timeoutCountdown` for non-terminal queued/running runs with task timeout.
- Fixture/example state: A macro task with timeout `5` starts at `10:00:00`, reports player start at `10:00:01`, and receives `clockTick(10:00:07)`. The run completes as `.timedOut(deadline: 10:00:06)`, releases foreground input, persists the timed-out run, and creates any downstream task connected by `.onTimeout`.
- Tests: `AutomationReducerTests.clockTickTimesOutRunningMacroAndTriggersTimeoutBranch`, `AutomationReducerTests.clockTickTimesOutQueuedMacroBeforePlayerStarts`, and `AutomationReducerTests.clockTickDoesNotTimeoutWhileWaitingForResource`.
- Migration/backward compatibility: Existing workflows/run history remain compatible. `timeout` still defaults to nil. Resource waiting time is not counted as task runtime timeout; max resource wait is a separate future policy.
- Open UI questions: Graph/Timeline/Task Inspector now have first-pass countdown rendering from projection. Task Run Detail has a per-run-aware evidence viewer first pass: failed playback reports bind `AutomationTaskRun.evidenceID` to `RunReport.runID`, repository writes macro package `runs/<evidenceID>/manifest.json` / `report.json`, and UI falls back to legacy latest evidence only when the latest report runID matches. The evidence section now shows binding status plus a report-derived diagnostic focus/preview/next-check summary, so users can distinguish verified per-run evidence, legacy latest matches, latest-macro-only evidence, mismatches that need review, and the immediate artifact to inspect. Run Detail also shows durable branch evidence from `AutomationTaskRun.branchEvidence` with projection fallback for older runs. User-configurable max resource wait, live screenshot/recording acceptance evidence, visual diagnostics live-capture polish, and visual-condition product rendering remain open. UI may show timed-out terminal state, timeout branches, and the first-pass task timeout countdown now, but should not promise full retry/backoff polish without using the retry summary projection below.

### Capability: Retry Policy First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: 如果 task 配置了 `AutomationRetryPolicy(maxAttempts:)`，failure/timeout 终态会先创建同一 execution 的下一次 attempt，并保留每次独立 `AutomationTaskRun`。只有 attempts 用完后，reducer 才解析 failure/timeout 下游分支。
- New or changed types: None. Existing `AutomationRetryPolicy`, `AutomationRetryBackoff`, `AutomationTask.retryPolicy`, and `AutomationTaskRun.attempt` are used.
- New or changed `AutomationAction` / `AutomationEffect`: No new action/effect. Existing terminal actions (`playerFinished`, `conditionEvaluated`, `taskFinished`, and timeout watchdog via `clockTick`) can now create a retry run from `completeRun`. Retry attempts use the same `executionID`, increment `attempt`, preserve upstream run IDs, and either start immediately or stay `.planned` until fixed/exponential backoff is due.
- Projection fields UI should read: Existing run history carries `AutomationTaskRun.attempt`. Runtime feedback projection first pass now exposes `AutomationTaskNodeProjection.retryAttemptSummary` and `AutomationResourceTimelineItem.retryAttemptSummary` for node badges, timeline summaries, and planned retry copy.
- Fixture/example state: Macro A has `retryPolicy.maxAttempts = 2` and a failure branch to B. Attempt 1 fails, reducer persists attempt 1 and creates attempt 2 for Macro A without starting B. If attempt 2 fails, reducer persists attempt 2 and then creates B through the failure dependency.
- Tests: `AutomationReducerTests.retryableFailureCreatesNextAttemptBeforeFailureBranch`, `AutomationReducerTests.retryBackoffPlansNextAttemptUntilDue`, and `AutomationReducerTests.timeoutRetrySuppressesTimeoutBranchUntilFinalAttempt`.
- Migration/backward compatibility: Existing workflows are compatible because `.none` is still `maxAttempts = 1`. Existing run history remains valid; retry adds additional run rows in the same execution instead of mutating prior attempts.
- Open UI questions: Graph/Timeline/Task Inspector now have first-pass retry summary rendering from projection. Retry-specific cancellation controls, product copy for exhausted retries, deeper run detail, and screenshot evidence remain open. UI should consume `retryAttemptSummary` instead of recomputing attempt state in SwiftUI.

### Capability: Runtime Feedback Projection First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: UI 可以在 Graph、Resource Timeline 和 Inspector 中直接显示 task timeout 倒计时和 retry attempt 摘要，不需要在 SwiftUI 中扫描 run history 或重算 timeout deadline。
- New or changed types: `AutomationTimeoutCountdownProjection`, `AutomationRetryAttemptSummary`, `AutomationTaskNodeProjection.timeoutCountdown`, `AutomationTaskNodeProjection.retryAttemptSummary`, `AutomationResourceTimelineItem.timeoutCountdown`, `AutomationResourceTimelineItem.retryAttemptSummary`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This is projection-only and computed from workflow tasks plus run history.
- Projection fields UI should read: Node cards/inspectors read `AutomationTaskNodeProjection.timeoutCountdown` and `retryAttemptSummary`; Resource Timeline rows read `AutomationResourceTimelineItem.timeoutCountdown` and `retryAttemptSummary`.
- Fixture/example state: A running task with timeout 10 seconds and `actualStartTime` four seconds ago projects remaining 6 seconds and `elapsedFraction` around 0.4. A planned retry run for attempt 2 of 3 projects `currentAttempt = 2`, `maxAttempts = 3`, `remainingAttempts = 1`, `nextRetryAt`, and a user label such as `Attempt 2 of 3`.
- Tests: `AutomationViewProjectionTests.timeoutCountdownIsProjectedOutsideSwiftUI` and `AutomationViewProjectionTests.retryAttemptSummaryIsProjectedOutsideSwiftUI` cover node/timeline projection.
- Migration/backward compatibility: Adds optional projection fields only. Existing workflows and run history remain compatible; UI can progressively adopt these fields.
- Open UI questions: Owner 2 now has restrained Graph/Timeline/Task Inspector first-pass rendering: countdown text, elapsed progress, retry badge copy, planned retry time, deadline, and remaining attempts are read from projection. Task Run Detail can load per-run-aware playback evidence through the app-edge presenter, dependency edges now have runtime branch decision evidence/projection, and condition runs now have durable diagnostics on `AutomationTaskRun.conditionEvidence`, including optional live sample/crop artifact refs loaded through the condition artifact presenter. Running-state screenshots, branch drill-in fixture evidence, and visual diagnostics fixture evidence exist; live capture/Open-Reveal recording, template/baseline preview polish, and stronger visual join grouping remain separate productization contracts. Visual condition polling/progress projection has a separate first pass below.

### Capability: Join Policy First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: 多入边 task 可以选择 `all`、`any` 或 `firstMatched` 合流语义。`all` 等所有入边满足；`any` 选择最早 ready 的入边，允许计划中的下游被更早 ready 的入边提前；`firstMatched` 锁定第一个完成的入边，后续同 execution 入边不会改写该下游 run。
- New or changed types: `AutomationJoinPolicy`, `AutomationTask.joinPolicy`, `AutomationTaskNodeProjection.joinPolicy`, `AutomationTaskNodeProjection.joinPolicyLabel`, `AutomationTaskNodeProjection.incomingDependencyCount`, `AutomationWorkflowDraftTask.joinPolicy`, `AutomationWorkflowDraftIssueCode.invalidJoinPolicy`, `AutomationWorkflowDraftPatchOperation.joinPolicy`。
- New or changed `AutomationAction` / `AutomationEffect`: None. Existing terminal actions still call downstream resolution; reducer now applies the target task's join policy during dependency resolution.
- Projection fields UI should read: Node cards/inspectors read `AutomationTaskNodeProjection.joinPolicy`, `joinPolicyLabel`, and `incomingDependencyCount`. Draft/AI preview reads/writes task-level `joinPolicy` using `all`, `any`, or `firstMatched`.
- Fixture/example state: B and C both point to D. D defaults to `all`, so D waits until both B and C finish. With `any`, D can start from C if C becomes ready before B's delayed edge. With `firstMatched`, D locks onto B if B completed first, even if C becomes ready sooner later. OwnerC fixture includes a `.any` two-input notification join node for UI review.
- Tests: `AutomationReducerTests.allJoinWaitsForEveryIncomingDependency`, `anyJoinUsesEarliestReadyIncomingDependency`, `firstMatchedJoinLocksFirstCompletedIncomingDependency`; `AutomationWorkflowDraftTests.draftValidatorRejectsUnsupportedJoinPolicy`, `draftImportAndExportPreserveNonDefaultJoinPolicy`, `draftEditorAndPatchUpdateJoinPolicy`; `AutomationViewProjectionTests.joinPolicyIsProjectedOutsideSwiftUI`, `ownerCFixtureExposesJoinPolicyReviewState`。
- Migration/backward compatibility: Existing internal workflows and drafts default to `.all`; `AutomationTask` custom decoding treats missing `joinPolicy` as `.all`. Draft import/export omits default `all` to keep JSON quiet and preserves non-default policies.
- Open UI questions: Owner 2 now has first-pass FlowGraph badges, Task Inspector editing/explanations for all/any/firstMatched, center branch guide, selected-condition If/Then/Else branch panel, and branch decision summaries inside the Inspector branch rows. Runtime branch decision evidence is now persisted on completed source runs and projection prefers that payload when available; screenshot/clip evidence and deeper branch drill-in polish remain open. This first pass ignores later branches for the already-created target run, but it does not cancel upstream tasks that are already running.

### Capability: Runtime Branch Decision Evidence First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: 当一次 run 产生 success/failure/timeout/cancelled 等终态后，runtime 会把这次 run 的 outgoing dependency decisions 写成 durable payload。UI 可以解释 triggered、skipped、disabled sibling edges、source outcome、target run、delay 和 target join policy，而不是只在 SwiftUI 中重新推导。
- New or changed types: `AutomationBranchDecisionEvidence`, optional `AutomationTaskRun.branchEvidence`, `AutomationBranchDecisionStatus`, `AutomationBranchDecisionProjection`, and optional `AutomationDependencyEdgeProjection.branchDecision`.
- New or changed `AutomationAction` / `AutomationEffect`: No new action/effect case. `AutomationReducer.completeRun` resolves downstream work, then writes `AutomationBranchDecisionEvidence` onto the completed source run before emitting `.persistRun`. `AutomationRepositoryClient.appendRun` persists the payload inside `automations.json` run history.
- Projection fields UI should read: Prefer `AutomationTaskRun.branchEvidence` for selected-run drill-in. FlowGraph/Inspector can keep reading `AutomationDependencyEdgeProjection.branchDecision`; projection now prefers durable `branchEvidence` when present and falls back to computed edge state for older run history.
- Fixture/example state: Source task A fails. Edge `A onSuccess -> B` stores `.skipped`; edge `A onFailure -> C` stores `.triggered` with C's downstream `targetRunID`; disabled outgoing edges store `.disabled` without creating target runs. Retryable non-final attempts do not store branch evidence because downstream work is intentionally suppressed until the final attempt.
- Tests: `AutomationReducerTests.terminalRunPersistsDurableBranchDecisionEvidence`, `AutomationReducerTests.retryableTerminalRunDoesNotPersistBranchEvidenceUntilFinalAttempt`, `AutomationOwnerBClientTests.repositorySavesWorkflowsAndAppendsRunHistory`, and `AutomationViewProjectionTests.branchDecisionsAreProjectedOnDependencyEdges`.
- Migration/backward compatibility: Adds an optional run-history field. Existing workflows and old runs decode without branch evidence and continue to use projection fallback; new terminal source runs with outgoing dependencies persist branch evidence.
- Open UI questions: Product acceptance now has idle/drag-link/task-reorder/running fixture screenshots and `product-evidence/branch-evidence-drill-in.png`; a real drag/reorder recording and broader live branch workflow clip remain open before marking the whole interaction product-complete.

### Capability: Visual Condition Core Spec First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: Workflow draft and internal workflow can express the first non-OCR visual waits users asked for: `regionChanged`, `imageAppeared`, `imageDisappeared`, and `pixelMatched`. These let a user say “wait until this area changes”, “wait until this icon appears/disappears”, or “wait until this pixel/region has this color” before continuing downstream.
- New or changed types: `AutomationVisualConditionType`, `AutomationVisualCondition`, `AutomationVisualCondition.searchRegionResolution(in:)`, `AutomationConditionKind.visual`, `AutomationWorkflowDraftCondition.imageRef`, `baselineRef`, `pixel`, `colorHex`, `pixelSampleRadius`, `threshold`, `AutomationWorkflowDraftIssueCode.missingVisualReference`, `missingPixel`, `invalidThreshold`, `invalidPixelSampleRadius`, and `invalidColor`.
- New or changed `AutomationAction` / `AutomationEffect`: No reducer action/effect change. Existing `.evaluateCondition` carries `AutomationConditionSpec`; `AutomationConditionEvaluatorClient.contextual` and the live factory accept an injected visual evaluator callback. The default live path now uses the app-edge live visual evaluator described below.
- Projection fields UI should read: UI/AI draft tooling can read/write the draft condition fields above. Runtime visual-condition polling/progress projection is now available through the separate `conditionProgress` contract below.
- Fixture/example state: A condition task with `condition.type = "imageDisappeared"`, `regionRef = "battle_result_area"`, `imageRef = "loading_spinner_template"`, `threshold = 0.91`, `timeoutSeconds = 20`, and `pollingSeconds = 0.4` imports into `.condition(.visual(...))` and exports back to `sparkle.workflow.draft.v1`.
- Tests: `AutomationContractTests.visualConditionRoundTripsThroughCodable`, `AutomationOwnerBClientTests.contextualConditionEvaluatorUsesContextAndProviders`, `AutomationWorkflowDraftTests.draftImportDryRunPreservesVisualConditionsAsCoreSpecs`, `draftValidatorChecksVisualConditionReferences`, `draftImportAndExportPreserveVisualConditionIntent`, and `draftEditorAndPatchPreserveVisualConditionFields`.
- Migration/backward compatibility: Existing condition JSON is compatible because `.visual` is additive and all new draft fields are optional. Draft validator now blocks missing image refs for image appear/disappear, invalid color/threshold values, invalid `pixelSampleRadius` values outside 0...8, and pixel matches without either pixel coordinates or a regionRef. Region refs still warn as unresolved until UI/provider binding supplies concrete region data.
- Open UI questions: Owner 2 now has first-pass visual-condition authoring/rendering: Workflow Inspector can create visual waits, Task Inspector can edit region/image/baseline/pixel/color/pixel sample radius/threshold, draw bounds, and choose `pixelMatched` colors with a shared ColorPicker + hex/swatch control; AI Draft Preview can edit visual draft fields, choose package `visualAssets` region/image/baseline refs, register package-local image/baseline files into draft `visualAssets`, copy external image/baseline files into the draft package, and capture package-local baselines from a drawn screen region; Graph/Timeline/Inspector render `conditionProgress`. Package-root retention also has a first pass. Owner 2 still owes product screenshots/recordings, deeper evidence drill-in, and broader managed storage/migration policy.

### Capability: Visual Condition Progress Projection First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: UI 可以在 Graph、Resource Timeline 和 Inspector 中直接说明条件正在等待什么：OCR 文本、区域变化、图标出现/消失、像素颜色匹配、外部信号、上游 outcome 或手动审批。视觉条件会暴露 region/image/baseline/pixel/color/pixelSampleRadius/threshold/polling/timeout 信息，避免 SwiftUI 重新拆 `AutomationConditionKind`。
- New or changed types: `AutomationConditionProgressKind`, `AutomationConditionProgressProjection`, `AutomationTaskNodeProjection.conditionProgress`, `AutomationResourceTimelineItem.conditionProgress`。
- New or changed `AutomationAction` / `AutomationEffect`: None. This is projection-only and computed from workflow task condition specs plus the latest visible run.
- Projection fields UI should read: Node cards/inspectors read `AutomationTaskNodeProjection.conditionProgress`; Resource Timeline rows read `AutomationResourceTimelineItem.conditionProgress`. Fields include `kind`, `kindLabel`, `targetLabel`, `detail`, `pollingInterval`, `isActivelyPolling`, optional `timeoutCountdown`, and visual references such as `regionRef`, `imageRef`, `baselineRef`, `pixel`, `colorHex`, `pixelSampleRadius`, and `threshold`.
- Fixture/example state: OwnerC fixture now includes a running visual condition task named `Watch spinner disappearance` with `kind = imageDisappeared`, `regionRef = battle_result_area`, `imageRef = loading_spinner_template`, `baselineRef = battle_start`, `threshold = 0.91`, and a condition timeout countdown.
- Tests: `AutomationViewProjectionTests.visualConditionProgressIsProjectedOutsideSwiftUI` and `ownerCFixtureExposesVisualConditionProgressState`。
- Migration/backward compatibility: Adds optional projection fields only. Existing workflows/run history remain compatible; non-condition tasks project `conditionProgress = nil`.
- Open UI questions: Owner 2 now renders `conditionProgress` in FlowGraph nodes, Resource Timeline rows, and Task Inspector Run Status using restrained labels/badges. Screenshot/recording evidence, richer run evidence drill-in, template/baseline picker flows, and live matching progress detail remain open. The projection does not imply arbitrary `regionRef` package binding is complete; live evaluation first pass is tracked in the next capability.

### Capability: Live Visual Condition Evaluator First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: Live condition evaluation no longer rejects visual conditions by default. The app-edge provider captures the current display, resolves the same display/window/content search-region spaces as OCR, and evaluates `pixelMatched`, `imageAppeared`, `imageDisappeared`, and `regionChanged` without putting `CGImage`, ScreenCapture, or Vision dependencies into core.
- New or changed types: App target `AutomationVisualConditionEvaluatorClient`, `AutomationVisualImageProvider`, internal `LiveAutomationVisualConditionEvaluator`; core `AutomationVisualCondition.searchRegionResolution(in:)`, `AutomationConditionEvaluationResult`, and `AutomationConditionEvaluationEvidence`.
- New or changed `AutomationAction` / `AutomationEffect`: `.evaluateCondition` still routes through `AutomationConditionEvaluatorClient.live`; the runner now receives `AutomationConditionEvaluationResult` and dispatches `.conditionEvaluationCompleted`. The live factory defaults visual evaluation to `AutomationVisualConditionEvaluatorClient.live(...)` while keeping the optional injected visual callback for tests, previews, and future package-bound providers.
- Projection fields UI should read: None new. UI continues to read `conditionProgress` for display and sends normal condition specs through reducer actions.
- Fixture/example state: A `pixelMatched` condition with `targetColorHex`, optional `pixelSampleRadius` and either an explicit `pixel` or concrete `searchRegion` can match against a live screenshot immediately. `imageAppeared` / `imageDisappeared` work when `imageProvider(imageRef)` resolves a template image. `regionChanged` works when `baselineProvider(baselineRef)` resolves a baseline image. Missing image/baseline/color configuration returns a user-readable rejected outcome instead of silently polling forever.
- Tests: `swift build -Xswiftc -swift-version -Xswiftc 6` compiles the app-edge provider; `AutomationContractTests.visualConditionSearchRegionResolvesCoordinateSpaces` covers the shared region-resolution helper; `AutomationOwnerBClientTests.contextualConditionEvaluatorUsesContextAndProviders` still covers injected provider routing without live macOS APIs.
- Migration/backward compatibility: Existing workflow and draft JSON remain compatible. The new default makes live visual evaluation more capable but does not change reducer state, persistence, or draft schema. Template/baseline lookup remains provider-based so package/registry design can land separately.
- Open UI questions: Product screenshot/recording evidence, template/baseline preview artifact polish, and broader managed storage/migration policy remain open. The diagnostics payload below now saves last-sample and watched-region image references for live OCR/visual runs; UI can also select draft/package `visualAssets` refs, register package-local image/baseline files, copy external image/baseline files into the draft package, capture package-local baseline PNGs in AI Draft Preview, and rely on the package-root retention first pass after import. The current color picker only writes the existing `targetColorHex` / draft `colorHex` field.

### Capability: Visual Diagnostics Drill-In Payload First Pass

- Owner: Engine + Runtime, consumed by UI
- Status: ready-for-ui
- User-facing capability: 当 condition 没有按用户预期触发时，Run Detail 可以说明它依据了什么：OCR/visual 看了哪里、看到了什么、采样了几次、阈值是多少，或者 `previousOutcome` / external signal / manual approval 是按什么上下文判定的。这解决用户在 battle result / loading spinner / icon disappeared / pixel changed 以及多分支状态编排中无法排查等待条件的问题。
- New or changed types: `AutomationConditionEvaluationResult`, `AutomationConditionEvaluationEvidence`, `AutomationConditionDiagnosticField`, `AutomationConditionDiagnosticArtifact`, `AutomationConditionDiagnosticArtifactKind`, `AutomationConditionEvidenceKind`, and `AutomationTaskRun.conditionEvidence`。Evidence carries condition kind, run/workflow/task/condition IDs, outcome, evaluated/first/last sample time, sample count, display bounds, resolved search region, search-region space, target description, observed summary, optional score, optional threshold, stable diagnostic fields, and optional persisted artifact references.
- New or changed `AutomationAction` / `AutomationEffect`: Existing `.evaluateCondition(...)` effect is unchanged. `AutomationConditionEvaluatorClient` now exposes `evaluateResult` while preserving the legacy `evaluate` outcome-only helper for tests/fakes. `AutomationEffectRunner` dispatches `.conditionEvaluationCompleted(runID:result:at:)`; reducer persists `result.evidence` onto the terminal `AutomationTaskRun.conditionEvidence` before downstream branch resolution and `.persistRun`.
- Projection fields UI should read: Run Detail reads `AutomationTaskRun.conditionEvidence` directly from selected run history and renders it through `AutomationTaskRunConditionEvidenceView`; `conditionEvidence.outcome`, `observedSummary`, `fields`, `sampleCount`, `score`, `threshold`, `displayBounds`, `resolvedSearchRegion`, and `artifacts` are the accepted payload. `conditionEvidence.artifacts` lists relative App Support paths such as `AutomationEvidence/<runID>/condition-last-sample.png` and `AutomationEvidence/<runID>/condition-region-sample.png` when live evaluation saved a sample. Artifact preview/open/reveal must route through `AutomationConditionEvidenceArtifactPresenter`, which resolves only safe relative paths under App Support, reports loaded/missing/invalid/unreadable states, and returns action success/failure feedback for UI display; SwiftUI must not concatenate paths manually, accept absolute paths, or load arbitrary URLs from persisted JSON. Evidence readiness marks visual diagnostics durable when this payload exists and includes artifact counts when available. Graph/Timeline evidence indicators now treat `conditionEvidence` as evidence through `AutomationTaskNodeProjection.hasEvidence` and `AutomationResourceTimelineItem.hasEvidence`. Graph/Timeline should keep using `conditionProgress` for live waiting state and must not recompute OCR/template matching or call ScreenCapture in SwiftUI.
- Fixture/example state: A visual condition waits for `imageDisappeared(spinner)` in `battle_result_area`, polls every 0.5s, times out or matches, and stores diagnostics with resolved region, sample count, observed summary such as template similarity, best score, threshold, template/baseline/pixel/OCR fields, plus last display sample and watched-region crop references when the live evaluator can write PNGs. OCR conditions store detected text count, matched text or last text candidates, search region, sample count, and the same sample/crop references. Context-only conditions store predicate/signal/approval fields without artifacts, for example previous outcome count and labels, external signal active/inactive, or manual approval granted/rejected. Failure/rejected terminal paths are also real payloads: OCR capture failure records target/search-region/sample metadata even without an image; OCR/Vision failure after capture keeps the sample/crop artifacts; visual capture, bitmap decode, missing imageRef/baselineRef/color, and unreadable provider failures return evidence with outcome, target description, failure field, and any available sample artifacts. If visual screenshot capture succeeds but bitmap decode fails, the rejected payload still keeps the captured display sample and watched-region crop when the region can be resolved.
- Tests: `AutomationContractTests.conditionEvaluationActionRoundTripsDiagnostics`, `AutomationContractTests.conditionDiagnosticsDecodeOldPayloadsWithoutArtifacts`, `AutomationContractTests.conditionDiagnosticArtifactPathsStayRelative`, `AutomationContractTests.runLifecycleHelpersKeepRuntimeStateInRun`, `AutomationReducerTests.conditionEvaluationResultPersistsDiagnosticsBeforeBranchResolution`, `AutomationOwnerBClientTests.contextualConditionEvaluatorUsesContextAndProviders`, `AutomationOwnerBClientTests.effectRunnerForwardsConditionDiagnosticsThroughCompletedResult`, `AutomationOwnerBClientTests.repositorySavesWorkflowsAndAppendsRunHistoryInAutomationsJSON`, and `AutomationViewProjectionTests.conditionDiagnosticsMarkGraphAndTimelineEvidence` cover Codable, backward-compatible decoding, safe relative artifact path resolution, context-only evidence payloads, reducer persistence, effect boundary, repository round-trip, and UI projection indicators without real ScreenCapture/Vision. App-edge failure payload/sample-capture wiring is verified by Swift 6 build; live product capture recording remains a product-evidence task.
- Migration/backward compatibility: `AutomationTaskRun.conditionEvidence` is optional; old run history decodes with nil evidence, and condition evidence written before artifact references decodes with `artifacts = []`. Legacy outcome-only evaluator clients still compile through `AutomationConditionEvaluatorClient { request in outcome }`, but `evaluateResult` now carries diagnostics for context-only conditions and live OCR/visual evaluators now return result payloads for matched, not-matched, failed, and rejected terminal paths and attempt app-edge artifact persistence whenever a screenshot is available. No SwiftUI view calls ScreenCapture, OCR, image providers, artifact writers, or ad-hoc filesystem path builders directly for diagnostics.
- Product acceptance: `product-evidence/visual-diagnostics-drill-in.png` or equivalent clip must show the watched region, last sample image/crop preview, threshold/score, Open/Reveal affordances, action feedback, and next-check copy from a real App/fixture state. The fixture PNG now proves the drill-in preview path plus artifact action feedback; live capture/Open-Reveal recording is still future evidence, so visual diagnostics are ready-for-ui at the contract level but not full live-product-complete. Template/baseline thumbnail comparison remains polish on top of the current last-sample/region artifact references.

### Capability: Visual Asset/Region Registry For AI Drafts First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: AI drafts and workflow package JSON can carry a package-level visual asset registry. `regionRef` can now point to a declared region so import compiles it into concrete OCR/visual search bounds, and export can write internal concrete regions back into `visualAssets.regions` instead of losing them.
- New or changed types: `AutomationWorkflowDraftDocument.visualAssets`, `AutomationWorkflowDraftVisualAssets`, `AutomationWorkflowDraftVisualRegion`, `AutomationWorkflowDraftVisualImageAsset`, `AutomationWorkflowDraftIssueCode.duplicateVisualAssetKey`, `invalidVisualAsset`, and `missingVisualAsset`.
- New or changed `AutomationAction` / `AutomationEffect`: None. This is draft/package schema, validator, import, and export behavior only. It does not start Player, read files, capture screen, or mutate app repository outside existing import/export paths.
- Projection fields UI should read: None directly. AI Draft Preview and import/export UI can read `AutomationWorkflowDraftDocument.visualAssets`. Runtime UI should still render `conditionProgress`; SwiftUI should not re-resolve image/baseline files.
- Fixture/example state: A draft with `visualAssets.regions[{ key: "battle_result_area", bounds, space: "displayNormalized" }]` and a visual condition `regionRef: "battle_result_area"` imports into `AutomationVisualCondition.searchRegion` with `.displayNormalized`. A workflow with concrete OCR region bounds exports a draft condition `regionRef: "<task>_region"` plus a matching `visualAssets.regions` entry.
- Tests: `AutomationWorkflowDraftTests.draftVisualAssetsMaterializeRegionRefsDuringImport`, `draftValidatorChecksVisualAssetRegistry`, and `workflowDraftExporterConvertsInternalWorkflowToAIDraft` cover region materialization, missing/invalid asset warnings, and export round trip. `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'AutomationWorkflowDraftTests'` passed with 32 tests; `swift build -Xswiftc -swift-version -Xswiftc 6` passed.
- Migration/backward compatibility: `visualAssets` is optional, so existing `sparkle.workflow.draft.v1` documents continue to decode. Missing `visualAssets` keeps old compatibility behavior; unresolved `regionRef` remains a warning and imports without concrete bounds. When `visualAssets` is present, missing referenced region/image/baseline assets are surfaced as warnings.
- Open UI questions: Owner 2 now exposes native Picker choices for draft/package `visualAssets.regions/images/baselines` inside AI Draft Preview condition editing, can register package-local image/baseline files from the draft source directory into safe relative `visualAssets` paths, can import-copy external files into `assets/images` / `assets/baselines`, and can capture a drawn screen region into a package-local baseline PNG. Package-root retention has a first pass. Managed storage/migration policy and product screenshot/recording evidence remain open; UI should not claim package assets are copied into global app-managed storage until that policy exists.

### Capability: Visual Assets Persistence And Package Provider Binding First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: draft/package `visualAssets` 可以从 AI draft import/export 进入 internal `AutomationWorkflow` 并随 workflow package round-trip。App edge 也可以按 `workflowID` 把 package-local `visualAssets.images` / `visualAssets.baselines` 转成 live visual evaluator 可注入的 image/baseline providers。这样 `imageAppeared`、`imageDisappeared` 和 `regionChanged` 不再只停留在 draft refs，而有了 workflow-scoped package lookup 的第一版边界。
- New or changed types: `AutomationWorkflow.visualAssets`; App target `AutomationVisualAssetWorkflowPackage`, `AutomationVisualAssetImageProviders.draftPackage(visualAssets:packageDirectory:)`, `AutomationVisualAssetImageProviders.workflowPackage(workflowID:visualAssets:packageDirectory:)`, `AutomationVisualAssetImageProviders.workflowPackages(_:)`, and `AutomationVisualAssetImageProviders.workflowPackageRoots(loadPackages:)`; request-aware `AutomationVisualImageProvider`; `AutomationWorkflowDraftVisualAssets.imagePath(for:)`, `baselinePath(for:)`, and `normalizedRelativeAssetPath(_:)`; provider injection parameters on `AutomationConditionEvaluatorClient.live(...)` and `LiveAutomationRuntimeHost.visualAssetPackages`.
- New or changed `AutomationAction` / `AutomationEffect`: None. This is an app-edge provider factory and live factory injection point only.
- Projection fields UI should read: None. UI should continue to write/read draft `visualAssets` refs and render `conditionProgress`; runtime host wiring owns provider injection.
- Fixture/example state: A package with `workflowID = A`, `visualAssets.images[{ key: "leave_button", path: "assets/leave-button.png" }]`, and package directory `/.../Battle.sparkrec_workflow` can create a provider that resolves `"leave_button"` only for condition evaluation requests from workflow A. Paths using absolute roots, `..`, URL schemes, home expansion, backslashes, or empty components are rejected before loading.
- Tests: `AutomationContractTests.workflowContractRoundTrips`, `AutomationWorkflowDraftTests.draftVisualAssetPathsStayInsidePackage`, `draftValidatorChecksVisualAssetRegistry`, `draftImportAndExportPreserveVisualConditionIntent`, `draftVisualAssetsMaterializeRegionRefsDuringImport`, and `AutomationOwnerBClientTests.workflowPackageRoundTripsStaticWorkflowsWithoutRunHistory` cover workflow/package persistence, relative path normalization, invalid asset paths, and visual asset round trips; `swift build -Xswiftc -swift-version -Xswiftc 6` covers the app-edge ImageIO provider.
- Migration/backward compatibility: Defaults stay nil providers, so existing workflows and live sessions behave as before unless a host explicitly injects package-bound providers.
- Open UI questions: AI Draft Preview now has package-local image/baseline registration, external image/baseline import-copy, and baseline capture first passes for drafts opened from disk; runtime host can accept workflow-scoped package bindings, and package-root retention has a first pass through the visual asset roots manifest. Future work still needs to decide whether package assets should also be copied into global app-managed storage or only re-associated by local root.

### Capability: Visual Asset Package-Root Retention First Pass

- Owner: Engine
- Status: ready-for-ui
- User-facing capability: confirmed workflow imports and package imports can retain the local directory that owns package-local visual assets, so `visualAssets.images` and `visualAssets.baselines` can resolve again after app restart/reopen when the original files are still present.
- New or changed types: `AutomationVisualAssetPackageRoot`, `AutomationVisualAssetPackageRootDocument`, `AutomationVisualAssetPackageRoots`, `AutomationVisualAssetPackageRootStore`, `AutomationInMemoryVisualAssetPackageRootStore`, and `AutomationVisualAssetPackageRootClient`; app-edge `AutomationVisualAssetImageProviders.workflowPackageRoots(loadPackages:)`; `LiveAutomationRuntimeHost.visualAssetPackageRootClient`.
- New or changed `AutomationAction` / `AutomationEffect`: None. This is package/import/runtime-host wiring, not reducer state. Confirmed CLI import, AI Draft Preview import, and workflow package import record or remove roots while workflow persistence still goes through existing repository/reducer boundaries.
- Projection fields UI should read: None. UI authors `visualAssets` refs and renders `conditionProgress`; runtime host owns package-root restoration.
- Fixture/example state: A draft imported from `/Users/me/Battle.sparkrec_workflow/workflow.json` with `visualAssets.images[{ key: "leave_button", path: "assets/leave.png" }]` records the package directory in `automation-visual-asset-roots.json`. A later runtime host reads repository workflows plus that manifest and rebuilds a workflow-scoped provider for `leave_button`.
- Tests: `AutomationOwnerBClientTests.visualAssetPackageRootsTrackWorkflowsWithPackageFileAssets`; CLI smoke for `workflow import --confirm --visual-assets-root`; `swift build -Xswiftc -swift-version -Xswiftc 6`.
- Migration/backward compatibility: Missing manifest means no retained package roots are restored, but workflows still load and visual conditions fail with provider-facing missing asset messages rather than corrupting workflow data. This first pass records local paths; it does not copy external files, create security-scoped bookmarks, migrate packages, or heal moved/deleted assets.
- Open UI questions: Owner 2 can describe package-local image/baseline refs as restart-safe for retained local package roots. It must not present this as a managed asset library. External copy/import-to-library policy, missing-file recovery, sandbox/bookmark behavior if needed, and product evidence remain future work.

## Contract Surfaces

| Surface | Owned By | Consumed By | Rule |
| --- | --- | --- | --- |
| Core types | Engine | UI | 保持 Codable/Equatable/Sendable，破坏性迁移必须写迁移说明。 |
| Reducer actions | Engine | UI | UI/provider/scheduler/player 只能通过 accepted action 进入状态机。 |
| Effects | Engine | Engine runtime | Reducer 只描述请求，runtime/adapter 执行真实副作用并回传 action。 |
| Live clients | Engine runtime | UI indirectly | Runtime 不绕过 reducer 改 state，UI 不直接调用 live clients。 |
| Projection | Engine + UI | UI | UI 渲染 projection，不重新实现状态语义。 |
| Persistence/package | Engine | UI/AI importer | UI 只用 accepted codec 和 reducer persistence。 |
| AI draft schema | Engine | CLI/UI | 外部稳定 schema 编译到内部 workflow，不直接等同内部 Codable；本阶段只实现 CLI 接口。 |

## Needed Backend Contracts For Next UI

| Capability | Owner | Needed Contract | UI Depends On |
| --- | --- | --- | --- |
| Repeating schedule occurrence | Engine | First pass: 给定 clock tick 创建下一个已到期且未表示的 run，不重复；future multi-occurrence preview 仍需后续合同 | Timeline 能显示下一次/未来多次计划。 |
| Resource wait queue | Engine | First pass: resource busy 时进入 `waitingForResource`，release/tick 会重新请求资源；max-wait 可让等待过久的 run 变为 `.timedOut(deadline:)`；`resourceWaiting` projection exposes reason, resources, priority, waited duration, deadline/remaining/fraction, and visible active-lease blockers; priority/preemption/cross-process policy 后续补 | UI 显示“等待鼠标键盘空闲 / 被哪个任务占用 / 还会等多久”，而不是失败或内部 lease 状态。 |
| Timeout watchdog | Engine | First pass: `.clockTick` 会让 queued/running task 超时为 `.timedOut`，宏先 `.cancelPlayer`，再释放资源、持久化、触发 timeout branch；`timeoutCountdown` projection first pass 已可用 | UI 能画 timeout 分支和克制倒计时，不在 SwiftUI 重算 deadline。 |
| Retry policy | Engine | First pass: failure/timeout 终态按 `AutomationRetryPolicy` 创建同 execution 的下一 attempt，直到 attempts 用完才走 failure/timeout downstream；fixed/exponential backoff 通过 planned retry run 表达；`retryAttemptSummary` projection first pass 已可用 | UI 用紧凑 badge/timeline 文案表达 attempt，不在 SwiftUI 扫 run history。 |
| Join policy | Engine | First pass: `AutomationTask.joinPolicy` supports `all` / `any` / `firstMatched`, reducer applies it, draft import/export/editor/patch/CLI carry `joinPolicy`, and node projection exposes policy + label + incoming count | FlowGraph/Inspector 能表达分支合流；Task Inspector 已有 If/Then/Else panel first pass；UI 不在 SwiftUI 推导 enum 文案。 |
| Visual conditions | Engine | First pass: `AutomationConditionKind.visual` and draft `regionChanged` / `imageAppeared` / `imageDisappeared` / `pixelMatched` import/export/editor/patch/CLI fields exist, including configurable `pixelSampleRadius`; default live visual evaluator now captures display screenshots, handles pixel/color matching directly with the same sample-radius semantics, and supports image/baseline matching through injected providers; node/timeline `conditionProgress` projection is ready; draft/package `visualAssets` registry can preserve and materialize `regionRef` bounds; workflow visualAssets persistence, workflow-scoped package provider binding, and package-root retention first passes can resolve package-local image/baseline assets after import records a root | Inspector 能提供直觉条件，pixel color picker/sample radius、draft/package visual asset picker、AI Draft Preview package-local image/baseline registration、external image/baseline import-copy 和 package-local baseline capture 已有 UI first pass；region picker polish、managed storage/迁移策略和产品验收证据仍需后续合同。 |
| Workflow draft editing | Engine | edit external draft JSON through stable commands/envelopes; first pass covers init/inspect/normalize/patch/task add/task set/task remove/schedule set/condition set/dependency add/dependency set/dependency remove | AI 生成入口可以逐步修改或批量修改草稿，不直接重写内部 Codable；UI preview 已消费 OCR condition、schedule、dependency set/remove、task remove 和 batch patch 的 in-memory 编辑路径。 |
| Workflow draft import/export/status/runtime | Engine | validate/resolve/compile draft JSON 到 internal workflow; dry-run, confirmed write, workflow list/show/status, draft-json export, `workflow run/cancel/runs`, `workflow run/cancel --handoff app`, next scheduled occurrence projection, repeating scheduled run generation, resource waiting queue/resume, and resource waiting reason projection first passes are ready | AI 生成入口和 CLI validator/importer/exporter/runtime control 共享；UI 可消费只读 status、next schedule projection 和 waiting resource reason；Task Inspector 已通过 existing reducer action 做 App 内 run/cancel 确认式 first pass；App-host mailbox handoff 有 first pass，仍需 daemon/background session、复杂 runtime projection 和批量 export/review polish。 |
| Simulation | Engine | fake clock + fake outcomes 输出预计 runs/timeline/warnings | UI 导入前预览和错误提示。 |
| CLI result envelope | Engine | stable `sparkle.cli.result.v1` JSON for list/show/status/export/edit/validate/simulate/import dry-run/import confirm | UI draft preview 和 AI 代理读取同一套结果。 |

## Frontend Request Protocol

UI owner 如果发现页面需要新字段或动作，不直接改 reducer。按以下流程：

1. 在 [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md) 写 `Interface Request` 摘要。
2. 标明用户场景、现有 projection/action 缺口、期望字段、默认值、失败状态。
3. 在本文件写完整请求，等待 Engine owner 接受、拒绝或提出替代合同。
4. 合同接受后，UI owner 先用 fixture 做 UI，再接 live projection。
5. 合同测试存在后，UI 才能移除临时 fixture guard。

## Status Labels For UI

后端 projection 应优先提供用户语言，而不是让 UI 翻译内部 case：

| Internal | Preferred User Label |
| --- | --- |
| planned | 已计划 |
| waitingForDependencies | 等待上一步 |
| waitingForResource | 等待鼠标键盘空闲 |
| queued | 准备执行 |
| running | 正在执行 |
| completed/succeeded | 已完成 |
| completed/failed | 失败 |
| completed/timedOut | 超时 |
| completed/cancelled | 已取消 |
| resourceConflict | 资源冲突 |
| missingMacro | 缺少宏 |

## Fixture Requirement

每个 ready-for-ui 能力至少提供一个 fixture：

- one happy path。
- one failure or timeout path。
- one conflict or missing-reference path if applicable。

Fixture 可以是 Swift test helper、projection fixture 或 docs JSON，但必须能让 UI owner 在 live 后端不稳定时开发页面。

# Automation Engine Swift Testing Plan

## 目标

用 Swift Testing 在毫秒级验证编排状态机，不移动真实鼠标，不等待真实时间，不调用真实 OCR。

## Test Doubles

需要以下 fake client：

- `MockPlayerClient`
- `MockSchedulerClient`
- `MockResourceArbiter`
- `MockConditionEvaluator`
- `MockAutomationRepository`

这些 mock 应该是 actor 或 Sendable-safe fixture，避免 Swift Testing 并行执行时共享可变状态出问题。

## 第一批测试

| Test | Expectation |
| --- | --- |
| `clockTickStartsDueTaskWhenResourceFree` | due task 进入 waitingForResource，再 acquire 后 running |
| `clockTickDoesNotStartTaskBeforeEarliestStart` | 未到 earliestStartTime 不启动 |
| `successEdgeStartsDownstreamTask` | A succeeded 后 B 变为 eligible |
| `failureEdgeStartsFallbackTask` | A failed 后 C 变为 eligible |
| `timeoutEdgeStartsTimeoutBranch` | A timedOut 后走 timeout edge |
| `cancelReleasesLeaseAndStopsDownstreamSuccess` | cancel 后 panic release，不走 success edge |
| `sessionStopCancelsActiveRuns` | runtime stop 通过 reducer/effects 取消 active Player、释放 lease、持久化 cancelled run |
| `resourceBusyQueuesTask` | 资源忙时 task 留在 waitingForResource |
| `resourceWaitTimesOutAfterMaxWaitDuration` | waitingForResource 超过 max wait 后走 `.timedOut(deadline:)`，触发 timeout branch/retry |
| `batchResourceLeasesStartOnceAndReleaseAllOnTerminalOutcome` | 多资源 task 只在整组 lease 到达后启动，终态释放全部 lease |
| `partialMultiResourceAcquisitionReleasesAcquiredLeases` | 多资源获取中途失败时释放已拿到的 lease |
| `startProgressAndFinishUpdateSnapshots` | Player run lifecycle 的 generation、loop、progress、finish snapshot 由纯状态机决定 |
| `stopInvalidatesStalePlaybackUpdates` | Player stop 后旧 playback task 的 loop/progress/finish 回调不能污染新状态 |
| `completionMapsTerminalOutcomes` | Player success/failure/cancel 归一化成 `AutomationPlayerCompletion`，不再散落在 UI Player 内部 |
| `engineRunsLoopAndReportsProgress` | live 播放外层 loop 负责 window refresh、step runner 调用、loop/progress callback |
| `engineRefreshesMissingTargetFrameBeforeStep` | step 前缺少目标 surface frame 时只刷新该 surface，并在成功解析后激活 |
| `engineBuildsFailureEvidenceOnStepFailure` | step runner 失败时由 `PlaybackRunEngine` 构造 `PlaybackFailureEvidence` 并停止后续 loop |
| `engineAbortsBeforeStepOnConflict` | 冲突监控命中时在执行 step 前中断，不触发真实输入 |
| `synchronousEngineRunsLoopsAndReportsProgress` | CLI 阻塞式播放外层 loop 负责 window refresh、step runner 调用、loop/progress callback |
| `synchronousEngineBuildsFailureEvidenceOnStepFailure` | CLI step runner 失败时由 `PlaybackSynchronousRunEngine` 构造 evidence 并停止后续 loop |
| `synchronousEngineAbortsBeforeStepOnConflict` | CLI 冲突监控命中时在执行 step 前中断 |
| `synchronousEngineTreatsContinuousPlansAsNoOp` | CLI 同步 engine 不接受无限 loop，continuous plan 安全 no-op |
| `locatorCacheKeyIncludesAnchorIdentity` | OCR locator cache key 包含 surface/text/match/observed/search/fallback 身份 |
| `locatorCacheKeyPrefersContentNormalizedFields` | OCR locator cache key 优先使用 content-normalized anchor 字段 |
| `locatorCacheOnlyReusesMatchingEntries` | locator cache 只在同一 loop、同一 key、1 秒窗口内复用定位点 |
| `locatorCacheIgnoresNilKeyStores` | 无 text anchor/cache key 时不写入可复用 locator cache |
| `delayedUpstreamPushesDownstreamEarliestStart` | A 延迟完成后 B earliestStartTime 级联顺延 |
| `sameMacroCreatesIndependentRuns` | 同一 macroID 多次运行生成多个 runID |
| `conditionNotMatchedTakesFalseBranch` | 条件未命中走 false branch |
| `conditionEffectIncludesCompletedUpstreamOutcomes` | reducer 把已完成上游 outcome 放入 `evaluateCondition.previousOutcomes` |
| `workflowEditActionsPersistStaticWorkflows` | workflow/task/dependency 编辑 action 只改纯 state，并通过 `persistWorkflows` effect 持久化 |
| `workflowEditActionsRejectInvalidDependencyGraphs` | reducer 拒绝自依赖/无效依赖图 |
| `moveTaskPersistsGraphPosition` | FlowGraph 节点移动写入 `AutomationTask.graphPosition` 并持久化 workflows |
| `contextualConditionEvaluatorUsesContextAndProviders` | B 侧 condition evaluator 支持 previous outcome、external signal provider、manual approval provider 和 OCR closure |
| `ocrConditionKeepsLegacyJSONCompatible` | 新增 OCR search region 字段不破坏旧 workflow JSON |
| `ocrSearchRegionResolvesCoordinateSpaces` | OCR `searchRegion` 可解析 display/window/content 坐标空间，供 live evaluator 使用 |
| `ocrConditionEditingPreservesExistingRegionBounds` | OCR condition 表单编辑 text/match/space 时不会清掉已有 `searchRegion` bounds |
| `ocrRegionPickerSelectionWritesBoundsForCoordinateSpaces` | 任意框选结果可写成 display/window/content 各坐标空间的 `searchRegion` bounds |
| `ocrRegionPickerSelectionReportsMissingFrames` | 任意框选在缺少 window/content frame 时不会写入不可解析的相对区域 |
| `effectRunnerPersistsWorkflowEdits` | B 侧 effect runner 把 `persistWorkflows` 写入 repository |
| `repositoryRefreshClientExposesLoadingAndPreviousSnapshot` | B 侧 repository refresh state 支持 loading 和失败时保留上一份 snapshot |
| `workflowPackageRoundTripsStaticWorkflowsWithoutRunHistory` | `.sparkrec_workflow` 只 roundtrip 静态 workflows，不夹带 run history |
| `workflowPackageValidatesImportBoundaries` | `.sparkrec_workflow` decode/import 校验 version、空包、重复 workflow ID 和无效 workflow DAG |

## 测试规则

- 使用 `@Suite` 和 `@Test`。
- 后续状态依赖的 optional 用 `try #require`。
- 不用 `Task.sleep`。
- 不依赖测试顺序。
- 每个测试建立自己的 workflow fixture。
- 不使用真实 `Player`、`CGEvent`、`Vision`、文件系统 Application Support。

## 验收条件

- Reducer 测试可以单独编译并在 Swift Testing runner 中通过。
- 测试能覆盖成功、失败、取消、超时、资源忙、条件真假分支。
- 测试能覆盖 panic release 优先级。
- 测试能覆盖 `cancelPlayer` effect 与 runtime graceful shutdown。
- 测试能覆盖 Player run lifecycle 的纯状态机语义。
- 测试能覆盖 Player live run engine 的 loop、window refresh、conflict、progress 和 failure evidence handoff。
- 测试能覆盖 Player synchronous run engine 的 blocking loop、conflict、progress 和 failure evidence handoff。
- 测试能覆盖 live OCR locator cache key/reuse 语义，不依赖真实 Vision 或鼠标事件。
- 测试能覆盖 batch lease handoff 和 partial-acquire cleanup。
- 测试能覆盖 condition evaluator 的上下文/provider handoff。
- 测试能覆盖 condition diagnostics payload 的 Codable、旧 payload 无 `artifacts` 字段时的兼容解码、安全相对路径规范化/拒绝规则，以及 reducer/repository 持久化边界；live PNG artifact writer、failure/rejected payload wiring 和 artifact presenter 通过 Swift 6 build、fixture/product验收覆盖，不在 unit test 里触发真实 ScreenCapture 或任意 Application Support 文件副作用。
- 测试能覆盖资源等待 max-wait 的 reducer timeout、projection deadline/remaining/fraction、draft import/export/edit/patch/CLI schema 和旧 JSON 兼容。
- 测试能覆盖 OCR region picker 的纯坐标转换，不依赖真实 OCR 或鼠标事件。
- 测试能覆盖 workflow edit action 和 `persistWorkflows` effect handoff。
- 测试能覆盖 repository refresh state 的 loading/error/previous snapshot handoff。
- 测试能覆盖 workflow package codec 和 import validation。
- 测试能覆盖 App-host handoff payload/status 语义，包括 pending/dispatched/failed/missing、receipt run IDs、repository-backed `runs` snapshots / `workflowStatus` readback，以及旧 status JSON 缺少这些新字段时的兼容解码。
- 测试能覆盖 `SavedMacro` 与 `AutomationTaskRun` 分离。

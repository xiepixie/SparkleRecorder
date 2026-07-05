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
| `resourceBusyQueuesTask` | 资源忙时 task 留在 waitingForResource |
| `delayedUpstreamPushesDownstreamEarliestStart` | A 延迟完成后 B earliestStartTime 级联顺延 |
| `sameMacroCreatesIndependentRuns` | 同一 macroID 多次运行生成多个 runID |
| `conditionNotMatchedTakesFalseBranch` | 条件未命中走 false branch |

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
- 测试能覆盖 `SavedMacro` 与 `AutomationTaskRun` 分离。

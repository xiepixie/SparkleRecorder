# Reducer And State Machine Workstream

状态（2026-07-05）：Owner A 已落地第一版 `AutomationReducer.reduce(state:action:environment:)`、`AutomationReducerResult`、`AutomationEffect` 和 `AutomationReducerTests`。本文保留状态机语义说明；后续新增 reducer 行为应继续从这里和 `workstreams/owner-a-core-reducer.md` 对齐。

## 目标

建立 AutomationEngine 的核心状态机，让时间、依赖、资源和结果都通过纯 reducer 转移。

## 当前现状

- `Player` 有自己的播放状态，但不适合直接作为 workflow 状态。
- `RunReport` 已存在，但 outcome 类型不够表达编排级分支。
- `SavedMacro.chainTo` 只能表达简单串联，无法表达失败分支、等待资源、条件判断。

## 第一版状态

```swift
public enum AutomationTaskRunStatus: Codable, Equatable, Sendable {
    case idle
    case scheduled
    case waitingForDependencies
    case waitingForResource
    case running
    case evaluatingCondition
    case completed(AutomationOutcome)
    case failed(AutomationOutcome)
    case cancelled
    case blocked(String)
}
```

## Reducer 职责

- `clockTick` 找到 due task。
- 未满足依赖的 task 进入 `waitingForDependencies`。
- 满足依赖但需要前台输入的 task 进入 `waitingForResource`。
- 拿到 resource lease 后进入 `running`。
- 收到 Player/Condition outcome 后进入终态。
- 启动 condition task 时，`evaluateCondition` effect 会携带 `previousOutcomes`，来源是当前 run 的 `upstreamRunIDs` 对应终态 outcome。
- `cancelRun` 对 queued/running macro 先产生 `cancelPlayer` effect，再走终态 release/persist/downstream 处理。
- 终态先 release resource，再 resolve downstream。
- 级联更新下游 `earliestStartTime`。

## 级联顺延规则

当 A 延迟完成，B 的启动时间应使用：

```text
B.earliestStartTime = max(
  B.scheduledStartTime,
  A.completedAt + dependency.delay,
  all other upstream requirements
)
```

如果 B 继续延迟，B 的下游也需要同样推导。这应由 pure DAG function 处理：

```swift
func propagateEarliestStartTimes(
    from completedTaskID: UUID,
    completedAt: Date,
    state: inout AutomationRunState
)
```

## 验收条件

- [x] `clockTick` 不直接启动 Player，只产生 state/effect。
- [x] A 成功后只触发 `onSuccess` / `always` 边。
- [x] A 失败后只触发 `onFailure` / `always` 边。
- [x] A timeout 后只触发 `onTimeout` / `always` 边。
- [x] 下游 task 的 `earliestStartTime` 会随着上游延迟级联顺延。
- [x] condition effect 携带 completed upstream outcomes，不让 adapter 回读 reducer state。
- [x] reducer 可以在无真实系统 API 的 Swift Testing 中跑完。

# Reducer And State Machine Workstream

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

- `clockTick` 不直接启动 Player，只产生 state/effect。
- A 成功后只触发 `onSuccess` / `always` 边。
- A 失败后只触发 `onFailure` / `always` 边。
- A timeout 后只触发 `onTimeout` / `always` 边。
- 下游 task 的 `earliestStartTime` 会随着上游延迟级联顺延。
- reducer 可以在无真实系统 API 的 Swift Testing 中跑完。

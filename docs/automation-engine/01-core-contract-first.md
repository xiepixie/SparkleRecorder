# Automation Core Contract First

状态（2026-07-05）：Phase 0 contract 已在 `AutomationContract.swift` 和 `AutomationContractTests` 中落地。本文继续作为合同语义说明；后续 reducer、ResourceArbiter、Player/Scheduler client 不应重新定义这些核心类型。

此文件定义必须先完成、不可与下游大规模并行的核心合同。目标是在不触发真实鼠标键盘、不写 UI 的情况下，先把编排状态和事件语言固定下来。

## 为什么必须先做合同

AutomationEngine 会连接这些已有边界：

- `MacroLibrary` / `SavedMacro`
- `Player`
- `RunReport` / `PlaybackFailureEvidence`
- 调度 tick
- 前台输入资源
- OCR/条件判断
- SwiftUI FlowGraph / Resource Timeline

如果没有统一合同，下游模块会产生多套状态解释，例如“失败”“超时”“资源冲突”“取消”在 UI、Player、Scheduler、测试中含义不同。

## 核心类型

### `AutomationWorkflow`

工作流静态定义。包含任务节点和依赖边。

```swift
public struct AutomationWorkflow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var tasks: [AutomationTask]
    public var dependencies: [AutomationDependency]
}
```

### `AutomationTask`

工作流里的节点定义，不是某一次运行。

```swift
public struct AutomationTask: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: AutomationTaskKind
    public var schedule: AutomationSchedule?
    public var resourceRequirement: AutomationResourceRequirement
    public var graphPosition: AutomationGraphPoint?
}
```

建议第一版 task kind：

```swift
public enum AutomationTaskKind: Codable, Equatable, Sendable {
    case macro(macroID: UUID)
    case condition(ConditionSpec)
    case delay(TimeInterval)
    case notification(message: String)
}
```

### `AutomationTaskRun`

某个 task 的一次具体运行实例。它是运行态，不能写回 `SavedMacro`。

```swift
public struct AutomationTaskRun: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID                 // runID
    public var executionID: UUID
    public var workflowID: UUID
    public var taskID: UUID
    public var macroID: UUID?
    public var scheduledStartTime: Date?
    public var earliestStartTime: Date?
    public var actualStartTime: Date?
    public var completedAt: Date?
    public var status: AutomationTaskRunStatus
    public var outcome: AutomationOutcome?
    public var evidenceID: UUID?
    public var leaseID: UUID?
    public var upstreamRunIDs: [UUID]
}
```

字段语义：

- `scheduledStartTime`: 用户原始计划时间。
- `earliestStartTime`: 依赖、资源和级联顺延后的最早可启动时间。
- `actualStartTime`: 真正开始时间。
- `completedAt`: 终态时间。
- `outcome`: 运行结果。
- `upstreamRunIDs`: 解锁当前 run 的上游终态 run，用于 condition context。

### `AutomationDependency`

表示 task 之间的边。边不仅是 A -> B，还带触发条件。

```swift
public struct AutomationDependency: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var fromTaskID: UUID
    public var toTaskID: UUID
    public var trigger: AutomationDependencyTrigger
    public var delay: TimeInterval
}
```

```swift
public enum AutomationDependencyTrigger: Codable, Equatable, Sendable {
    case onSuccess
    case onFailure
    case onTimeout
    case onCancelled
    case onConditionMatched
    case onConditionNotMatched
    case always
}
```

### `AutomationOutcome`

编排层用 outcome，而不是直接复用 Player 内部布尔值。

```swift
public enum AutomationOutcome: Codable, Equatable, Sendable {
    case succeeded(report: RunReport?)
    case failed(report: RunReport?)
    case cancelled(reason: String?)
    case timedOut(deadline: Date?)
    case resourceConflict(resource: AutomationResource?)
    case permissionDenied(permission: AutomationPermission, message: String)
    case conditionMatched
    case conditionNotMatched
    case missingMacro(macroID: UUID)
    case rejected(reason: String)
}
```

### `AutomationAction`

所有外部事件都进入 reducer。

```swift
public enum AutomationAction: Equatable, Sendable {
    case clockTick(Date)
    case manualStart(workflowID: UUID, taskID: UUID, requestedAt: Date)
    case scheduledStartDue(workflowID: UUID, taskID: UUID, scheduledAt: Date)
    case upsertWorkflow(AutomationWorkflow, at: Date)
    case deleteWorkflow(workflowID: UUID, at: Date)
    case upsertTask(workflowID: UUID, task: AutomationTask, at: Date)
    case deleteTask(workflowID: UUID, taskID: UUID, at: Date)
    case moveTask(workflowID: UUID, taskID: UUID, position: AutomationGraphPoint, at: Date)
    case upsertDependency(workflowID: UUID, dependency: AutomationDependency, at: Date)
    case deleteDependency(workflowID: UUID, dependencyID: UUID, at: Date)
    case runCreated(AutomationTaskRun)
    case resourceLeaseAcquired(runID: UUID, lease: AutomationResourceLease, at: Date)
    case resourceLeasesAcquired(runID: UUID, leases: [AutomationResourceLease], at: Date)
    case resourceLeaseDenied(runID: UUID, resource: AutomationResource, at: Date)
    case playerStarted(runID: UUID, at: Date)
    case playerFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
    case conditionEvaluated(runID: UUID, outcome: AutomationOutcome, at: Date)
    case taskFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
    case cancelRun(runID: UUID, at: Date)
    case panicRelease(runID: UUID, at: Date)
}
```

### `AutomationEffect`

Reducer 不调用真实系统 API，只把副作用请求交给 Owner B。

```swift
public enum AutomationEffect: Codable, Equatable, Sendable {
    case requestResource(runID: UUID, requirement: AutomationResourceRequirement)
    case releaseResource(runID: UUID, lease: AutomationResourceLease)
    case startPlayer(runID: UUID, workflowID: UUID, taskID: UUID, macroID: UUID)
    case cancelPlayer(runID: UUID)
    case evaluateCondition(
        runID: UUID,
        workflowID: UUID,
        taskID: UUID,
        condition: AutomationConditionSpec,
        previousOutcomes: [AutomationOutcome]
    )
    case wait(runID: UUID, workflowID: UUID, taskID: UUID, duration: TimeInterval)
    case sendNotification(runID: UUID, workflowID: UUID, taskID: UUID, notification: AutomationNotificationSpec)
    case persistWorkflows([AutomationWorkflow])
    case persistRun(AutomationTaskRun)
}
```

## 非目标

第一阶段不做：

- SwiftUI FlowGraph 交互。
- 真实 `Player` 接入。
- 真实后台 scheduler。
- OCR 实际执行。
- workflow 包格式。

第一阶段只做 pure model + reducer + tests。

## 验收条件

- `AutomationWorkflow`, `AutomationTask`, `AutomationTaskRun`, `AutomationDependency`, `AutomationOutcome`, `AutomationAction` 均 `Sendable`。
- `SavedMacro` 没有新增运行态字段。
- 同一个 `macroID` 可生成多个独立 `AutomationTaskRun`。
- 所有 action 都能被 reducer 纯函数处理。
- Swift Testing 覆盖基础状态转移。

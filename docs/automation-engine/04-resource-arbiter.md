# Resource Arbiter Workstream

状态（2026-07-05）：Owner B 已落地 `AutomationResourceArbiterClient`、`AutomationResourceLeaseStore`、`AutomationResourceRequest` 和 `AutomationResourceLeaseResult`。A/B 已增加 `resourceLeasesAcquired` 批量 handoff，多资源 task 不再因为第一张 lease 提前启动。

## 目标

中心化管理 SparkleRecorder 的独占资源：前台键盘鼠标控制权。

## 为什么需要它

当前 `Player` 内部有冲突监控，但 AutomationEngine 需要在 Player 启动前就知道任务是否能运行。多个 workflow 或多个宏不能同时抢鼠标。

## 资源模型

第一版资源集合：

```swift
public enum AutomationResource: Codable, Equatable, Sendable {
    case foregroundInput
    case screenCapture
    case accessibility
    case network
}
```

`AutomationResourceRequirement` 是资源集合。单资源仍可用 `resourceLeaseAcquired`，多资源必须用 `resourceLeasesAcquired(runID:leases:at:)` 一次性交给 reducer；reducer 只有收到整组 leases 后才启动 task。任一资源被拒绝时，Owner B effect runner 会释放已拿到的 lease，再发 `resourceLeaseDenied`。

任务声明资源需求：

```swift
public struct AutomationResourceRequirement: Codable, Equatable, Sendable {
    public var resources: Set<AutomationResource>
}
```

lease：

```swift
public struct AutomationResourceLease: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var runID: UUID
    public var resource: AutomationResource
    public var acquiredAt: Date
}
```

## Panic Release

必须采纳。任何终态都先释放 lease：

- completed
- failed
- cancelled
- timedOut
- permissionDenied
- resourceConflict
- player crashed / no callback timeout

Reducer 处理终态顺序：

```text
terminal outcome received
  -> emit releaseLease(runID)
  -> mark run terminal
  -> resolve downstream edges
  -> schedule next eligible tasks
```

## Live 实现建议

`AutomationResourceArbiterClient` 是可注入 client：

```swift
struct AutomationResourceArbiterClient: Sendable {
    var acquire: @Sendable (AutomationResourceRequest) async -> AutomationResourceLeaseResult
    var release: @Sendable (UUID) async -> Void
    var panicRelease: @Sendable (UUID) async -> Void
}
```

live 版可以先用 actor：

```swift
actor ForegroundInputLeaseStore {
    private var currentLease: ResourceLease?
}
```

## 验收条件

- 同时两个 foreground task 只能有一个拿到 lease。
- 多资源 task 必须等整组 lease 都拿到后才启动。
- 多资源获取中途失败时必须释放已经拿到的 lease。
- resource busy 时 task 进入 queue/waitingForResource。
- cancel running task 会通过 reducer 终态路径 release lease。
- timeout running task 会通过 reducer 终态路径 release lease。
- Player 没回调时可以由 watchdog 触发 panic release。
- Swift Testing 用 fake arbiter 验证状态，不触发真实输入。

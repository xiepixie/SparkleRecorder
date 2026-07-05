# Resource Arbiter Workstream

## 目标

中心化管理 SparkleRecorder 的独占资源：前台键盘鼠标控制权。

## 为什么需要它

当前 `Player` 内部有冲突监控，但 AutomationEngine 需要在 Player 启动前就知道任务是否能运行。多个 workflow 或多个宏不能同时抢鼠标。

## 资源模型

第一版只建一个资源：

```swift
public enum AutomationResource: Codable, Equatable, Sendable {
    case foregroundInput
}
```

任务声明资源需求：

```swift
public enum AutomationResourceRequirement: Codable, Equatable, Sendable {
    case none
    case foregroundInput
}
```

lease：

```swift
public struct ResourceLease: Codable, Equatable, Sendable, Identifiable {
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

`ResourceArbiterClient` 应是可注入 client：

```swift
struct ResourceArbiterClient: Sendable {
    var acquire: @Sendable (UUID, AutomationResource) async -> ResourceLease?
    var release: @Sendable (ResourceLease.ID) async -> Void
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
- resource busy 时 task 进入 queue/waitingForResource。
- cancel running task 会触发 panic release。
- timeout running task 会触发 panic release。
- Player 没回调时可以由 watchdog 触发 panic release。
- Swift Testing 用 fake arbiter 验证状态，不触发真实输入。

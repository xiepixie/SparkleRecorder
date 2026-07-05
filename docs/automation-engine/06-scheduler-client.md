# Scheduler Client Workstream

## 目标

把定时启动设计成 action source，而不是让 timer 直接调用 Player。

## 当前现状

- 现有宏可通过 UI、热键、CLI 触发。
- 尚无 workflow 级 scheduler。

## 第一版 SchedulerClient

```swift
public struct SchedulerClient: Sendable {
    public var events: @Sendable () -> AsyncStream<SchedulerEvent>
}
```

```swift
public enum SchedulerEvent: Equatable, Sendable {
    case clockTick(Date)
    case manualTrigger(workflowID: UUID, taskID: UUID, at: Date)
}
```

Scheduler 只做两件事：

- 定期发 `clockTick(Date)`。
- 用户手动触发时发 `manualTrigger`。

它不判断依赖，不抢资源，不启动 Player。

## macOS 后台策略

第一版：

- App 运行中使用 timer。
- 菜单栏前台常驻时即可工作。

后续：

- `NSBackgroundActivityScheduler` 用于低频后台唤醒。
- LaunchAgent / login item 用于更强后台能力。

## 验收条件

- Scheduler 可被 fake。
- `clockTick` 测试可用固定 Date。
- Timer 不直接引用 `Player`。
- Scheduler 不修改 persistence。
- 手动触发和定时触发走同一个 reducer path。

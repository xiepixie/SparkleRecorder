# Scheduler Client Workstream

状态（2026-07-05）：Owner B 已落地 `AutomationSchedulerClient` 和 `AutomationSchedulerEvent`。client 只输出 event/action，不启动 `Player`；`AutomationRuntimeSession` 和 `LiveAutomationRuntimeHost` 已把 timer scheduler 接入菜单栏 app lifecycle。

## 目标

把定时启动设计成 action source，而不是让 timer 直接调用 Player。

## 当前现状

- 现有宏可通过 UI、热键、CLI 触发。
- workflow 级 scheduler 第一版是 timer-driven `clockTick`，由 reducer 判断 due task；尚未使用 `NSBackgroundActivityScheduler` 或 login item。

## 第一版 AutomationSchedulerClient

```swift
public struct AutomationSchedulerClient: Sendable {
    public var events: @Sendable () -> AsyncStream<AutomationSchedulerEvent>
}
```

```swift
public enum AutomationSchedulerEvent: Equatable, Sendable {
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

- App 运行中使用 `AutomationSchedulerClient.timer`。
- `LiveAutomationRuntimeHost` 在 `MenuBarController` 初始化时启动 session，退出时取消后台 task。
- 菜单栏常驻时即可发 `clockTick`；workflow authoring 和 UI refresh 已通过 runtime projection/repository refresh 边界接线。

后续：

- `NSBackgroundActivityScheduler` 用于低频后台唤醒。
- LaunchAgent / login item 用于更强后台能力。

## 验收条件

- Scheduler 可被 fake。
- `clockTick` 测试可用固定 Date。
- Timer 不直接引用 `Player`。
- Scheduler 不修改 persistence。
- 手动触发和定时触发走同一个 reducer path。

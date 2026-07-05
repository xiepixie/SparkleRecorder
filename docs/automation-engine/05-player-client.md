# Player Client Workstream

状态（2026-07-05）：Owner B 已落地 `AutomationPlayerClient`、`AutomationPlayerStartRequest`、`AutomationPlayerStartResult`、`AutomationPlayerCompletion`、Player completion action stream 和 `LiveAutomationPlayerClient`。`LiveAutomationRuntimeHost` 已把 Player completion stream 接入菜单栏 app lifecycle。`PlaybackRunStateMachine` 已抽出 Player run lifecycle 的 generation、loop/progress snapshot、stale update rejection 和 terminal completion mapping。`PlaybackRunEngine` 已抽出 live 播放的外层 plan loop、窗口激活/刷新、冲突中断、progress 节流、失败 evidence 构造和 async step-runner 边界。`LivePlaybackRunStepClient` 已抽出 live locator/OCR step runner 与真实 event posting handoff。`PlaybackSynchronousRunEngine` 和 `LivePlaybackSynchronousRunStepClient` 已抽出 CLI 阻塞式播放路径。`PlaybackPowerAssertion` 在 app 层为 live/CLI 播放持有显示器和系统 idle assertions，并周期性声明本地 user activity，避免合成 CGEvent 不刷新 macOS 空闲/锁屏计时器。

## 目标

把现有 `Player` 包成可 mock 的执行依赖，让 AutomationEngine 不直接依赖 `ObservableObject` UI Player。

## 当前现状

- `Player` 已能播放宏，处理窗口刷新、OCR、冲突、失败证据。
- `PlaybackStepExecutor` 已抽出普通输入执行。
- `PlaybackFailureEvidenceBuilder` 已抽出失败证据构造。
- `PlaybackRunStateMachine` 已抽出 run lifecycle 状态，防止 stale task epilogue 覆盖新 playback，并把 success/failure/cancel 归一化成 `AutomationPlayerCompletion`。
- `PlaybackRunEngine` 已抽出 live 外层执行 loop：循环次数、窗口激活/刷新、缺失 surface frame 补刷新、冲突中断、step runner 调用、progress callback 和失败 evidence 构造都有纯 Swift Testing 覆盖。
- `LivePlaybackRunStepClient` 已抽出 live wait/verify text、locator fallback、OCR-backed point resolution、event posting handoff；`PlaybackLocatorCache` 负责 locator cache key/reuse 语义并有纯测试。
- `PlaybackSynchronousRunEngine` 已抽出 CLI 阻塞式外层 loop，`LivePlaybackSynchronousRunStepClient` 已抽出 CLI wait/verify text、locator fallback、OCR-backed point resolution 和 event posting handoff。
- `PlaybackPowerAssertion` 留在 app target：播放期间除了 `ProcessInfo` activity，还创建 IOKit display/system idle assertions，并定时调用 `IOPMAssertionDeclareUserActivity`。合成鼠标/键盘事件可以驱动目标 app，但不能可靠地等价于真实 HID 用户活动，所以不能依赖鼠标移动本身防止屏保/锁屏。
- `Player` 现在主要负责 observable UI state、run lifecycle apply、client 组装和 evidence 持久化触发；不再承载 Automation reducer 语义。

## 第一版 Client

```swift
public struct AutomationPlayerClient: Sendable {
    public var start: @Sendable (AutomationPlayerStartRequest) async -> AutomationPlayerStartResult
    public var cancel: @Sendable (UUID) async -> Void
    public var events: @Sendable () -> AsyncStream<AutomationAction>
}
```

```swift
public struct AutomationPlayerStartRequest: Sendable {
    public var runID: UUID
    public var macro: SavedMacro
    public var scheduledStartTime: Date?
    public var context: PlaybackContext
}
```

```swift
public enum AutomationPlayerStartResult: Equatable, Sendable {
    case started
    case rejected(AutomationOutcome)
}
```

播放结束不要直接改 Automation state，而是发 action：

```swift
case playerFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
```

`AutomationEngineRuntime.runPlayerEvents()` 会消费 `AutomationPlayerClient.events()`，把 completion action 再送回 reducer。`LiveAutomationPlayerClient` 把现有 `Player` 的完成/失败/取消转成这个 action stream，不能直接改 `AutomationRunState`。

Owner B 在 `AutomationEffectRunner` 和 `LiveAutomationPlayerClient` 两层都拒绝空宏/不可播放宏，返回 `.rejected(reason: "Macro has no playable events")`，避免 reducer 收到 `playerStarted` 后永远等不到 completion。

`AutomationRuntimeSession` 在启动时消费 `AutomationPlayerClient.events()`，所以 live Player completion 不需要 UI 手动轮询。停止 runtime 时，session 会先让 reducer 对 active run 发 `cancelRun`；queued/running macro 会产生 `cancelPlayer` effect，由 Owner B 调用 `AutomationPlayerClient.cancel`，再由 reducer 释放 lease 和持久化 cancelled run。`LiveAutomationRuntimeHost` 只负责把现有 `Player` 实例注入 session。

## Live 接入策略

第一版不要重写 `Player`。只做 adapter：

```text
AutomationEngine -> PlayerClient.live -> existing Player.play(...)
```

`Player.play` 的 live execution loop 已委托给 `PlaybackRunEngine`，live locator/OCR step runner 已委托给 `LivePlaybackRunStepClient`。`Player.playSynchronously` 已委托给 `PlaybackSynchronousRunEngine` 和 `LivePlaybackSynchronousRunStepClient`。

## 验收条件

- AutomationEngine 可以用 `MockPlayerClient` 完整测试。
- `PlayerClient` 不暴露 `ObservableObject`。
- `PlayerClient` 不直接写 workflow state。
- 同一个 `SavedMacro` 多次 start 会使用不同 `runID`。
- `Player` failure/cancel/timeout 都能映射为 `AutomationOutcome`。
- Runtime shutdown can cancel in-flight Player work without bypassing reducer terminal handling.
- Playback run lifecycle has pure tests for start/progress/finish, stale generation rejection, and completion outcome mapping.
- Playback live run engine has pure tests for loop callbacks, window refresh handoff, conflict abort, progress throttling, and failure evidence construction.
- Playback locator cache key/reuse semantics have pure tests, keeping live OCR locator caching out of `Player`.
- Playback synchronous run engine has pure tests for blocking loop/progress callbacks, conflict abort, failure evidence, and continuous-plan no-op behavior.

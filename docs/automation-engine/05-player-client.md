# Player Client Workstream

## 目标

把现有 `Player` 包成可 mock 的执行依赖，让 AutomationEngine 不直接依赖 `ObservableObject` UI Player。

## 当前现状

- `Player` 已能播放宏，处理窗口刷新、OCR、冲突、失败证据。
- `PlaybackStepExecutor` 已抽出普通输入执行。
- `PlaybackFailureEvidenceBuilder` 已抽出失败证据构造。
- 但 `Player` 仍不是纯状态机，不能直接作为 Automation reducer 的组成部分。

## 第一版 Client

```swift
public struct PlayerClient: Sendable {
    public var start: @Sendable (PlayerStartRequest) async -> PlayerStartResult
    public var cancel: @Sendable (UUID) async -> Void
}
```

```swift
public struct PlayerStartRequest: Equatable, Sendable {
    public var runID: UUID
    public var macro: SavedMacro
    public var scheduledStartTime: Date?
    public var context: PlaybackContext
}
```

```swift
public enum PlayerStartResult: Equatable, Sendable {
    case started
    case rejected(AutomationOutcome)
}
```

播放结束不要直接改 Automation state，而是发 action：

```swift
case playerFinished(runID: UUID, outcome: AutomationOutcome, at: Date)
```

## Live 接入策略

第一版不要重写 `Player`。只做 adapter：

```text
AutomationEngine -> PlayerClient.live -> existing Player.play(...)
```

中期再把 `Player` 内部的 run loop 抽成 `PlaybackRunEngine`。

## 验收条件

- AutomationEngine 可以用 `MockPlayerClient` 完整测试。
- `PlayerClient` 不暴露 `ObservableObject`。
- `PlayerClient` 不直接写 workflow state。
- 同一个 `SavedMacro` 多次 start 会使用不同 `runID`。
- `Player` failure/cancel/timeout 都能映射为 `AutomationOutcome`。

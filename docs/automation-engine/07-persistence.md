# Automation Persistence Workstream

## 目标

持久化 workflow 静态定义和运行历史，同时保持 `SavedMacro` 是静态模板。

## 第一版格式

建议先使用：

```text
~/Library/Application Support/SparkleRecorder/automations.json
```

不要第一版就做 `.sparkrec_workflow` 包。包格式等 UI、状态机和运行历史稳定后再做。

## 数据拆分

静态定义：

```swift
AutomationWorkflow
AutomationTask
AutomationDependency
AutomationSchedule
```

运行历史：

```swift
AutomationTaskRun
AutomationOutcome
RunEvidence reference
```

不要写回：

- `SavedMacro.events`
- `SavedMacro.surfaces`
- `SavedMacro.loops`
- `SavedMacro.speed`

可以写回宏统计的是既有宏库层逻辑，例如 play count，但 workflow run evidence 不应污染宏模板。

## Repository Client

```swift
public struct AutomationRepositoryClient: Sendable {
    public var loadWorkflows: @Sendable () async throws -> [AutomationWorkflow]
    public var saveWorkflows: @Sendable ([AutomationWorkflow]) async throws -> Void
    public var appendRun: @Sendable (AutomationTaskRun) async throws -> Void
}
```

## 验收条件

- workflow JSON 可 Codable roundtrip。
- 同一个 macroID 三次运行产生三个 run records。
- 删除 workflow 不删除 SavedMacro。
- 删除 SavedMacro 时 workflow task 可以进入 missing-macro 状态，而不是崩溃。
- Repository 测试使用临时目录，不碰真实 Application Support。

# Automation Persistence Workstream

状态（2026-07-05）：Owner B 已落地 `AutomationRepositoryClient`、`AutomationRepositorySnapshotClient`、`AutomationRepositoryRefreshClient`、`AutomationJSONRepository`、`AutomationPersistenceDocument` 和 `.sparkrec_workflow` package codec。`AutomationRuntimeSession` 启动时会加载 `automations.json` 的 workflows/run history；产品层保存/打开/分享面板、selected/all workflow 导出与分享、冲突处理 UI 和缺失本地宏提醒已由 Owner C second pass 接线。

## 目标

持久化 workflow 静态定义和运行历史，同时保持 `SavedMacro` 是静态模板。

## App Repository Format

App 内部运行态使用：

```text
~/Library/Application Support/SparkleRecorder/automations.json
```

`automations.json` 是本机 repository 文档，包含静态 workflows 和 append-only run history。它不是分享文件，Owner C 不直接读写它。

## Workflow Package Format

`.sparkrec_workflow` 是 Owner B 暴露给产品导入/导出的纯 workflow 交换格式：

```swift
public struct AutomationWorkflowPackageDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var workflows: [AutomationWorkflow]
}
```

规则：

- `version` 必须等于 `AutomationWorkflowPackage.currentVersion`。
- `workflows` 必须至少包含一个 workflow。
- 同一个 package 内不能出现重复 `AutomationWorkflow.id`。
- 每个 workflow 必须通过 `AutomationWorkflow.validationIssues()`，包括 dependency source/target、自依赖、重复 dependency ID 和 cycle 校验。
- package 只承载静态 `AutomationWorkflow`；不承载 `AutomationTaskRun`、evidence、`SavedMacro.events` 或 `.sparkrec` 宏资源包。
- codec 使用 `AutomationWorkflowPackage.encode/decode/validate`；产品 UI 只拿 `Data` 或 `AutomationWorkflowPackageDocument`，不自行解释 JSON 字段。
- 导入冲突策略、保存/打开/分享面板、selected/all workflow 导出与分享、缺失本地宏提醒属于产品/UI 接线，不改变 package 文档语义；当前 second pass 支持选中 workflow 导出/分享、全部 workflows 导出/分享、package 导入、duplicate workflow 的 Add Copies / Replace Existing 冲突选择，以及 referenced macro 不在本地宏库时的确认提示。

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
    public var loadRunHistory: @Sendable () async throws -> [AutomationTaskRun]
    public var appendRun: @Sendable (AutomationTaskRun) async throws -> Void
}
```

`AutomationRuntimeSession.start()` 会调用 `loadWorkflows` 和 `loadRunHistory` 创建初始 `AutomationRunState`。完成的 run 仍通过 `AutomationEffect.persistRun` 追加回同一个 repository，不写回 `SavedMacro`。

UI refresh 不直接调用 throws API，而是通过 snapshot boundary：

```swift
public struct AutomationRepositorySnapshotClient: Sendable {
    public var refresh: @Sendable () async -> AutomationRepositoryRefreshResult
}
```

`AutomationRepositorySnapshot.state` 会把 workflows/run history 转成 read-only projection 可用的 `AutomationRunState`；失败则返回 `AutomationRepositoryRefreshFailure`，供 UI 展示错误状态。

需要 loading/error 展示时，Owner C 使用 stateful boundary：

```swift
public enum AutomationRepositoryRefreshState: Equatable, Sendable {
    case idle
    case loading(startedAt: Date, previousSnapshot: AutomationRepositorySnapshot?)
    case loaded(AutomationRepositorySnapshot)
    case failed(AutomationRepositoryRefreshFailure, previousSnapshot: AutomationRepositorySnapshot?)
}

public struct AutomationRepositoryRefreshClient: Sendable {
    public var currentState: @Sendable () async -> AutomationRepositoryRefreshState
    public var refresh: @Sendable () async -> AutomationRepositoryRefreshState
}
```

`loading` 和 `failed` 都保留 previous snapshot，方便 UI 保持旧 projection 可见，同时显示 refresh progress 或 error。

## 验收条件

- workflow JSON 可 Codable roundtrip。
- `.sparkrec_workflow` 可 roundtrip 静态 workflows，且不包含 run history。
- `.sparkrec_workflow` decode/import 校验 version、空包、重复 workflow ID 和无效 workflow DAG。
- 同一个 macroID 三次运行产生三个 run records。
- Repository snapshot 可生成 reducer/projection state。
- Repository refresh failure 可作为值返回，不要求 SwiftUI 捕获 throw。
- Repository refresh state 可表达 idle/loading/loaded/failed，并在失败时保留上一份 snapshot。
- 产品 UI 可通过 `.sparkrec_workflow` 保存/打开面板导入导出静态 workflows，导入后仍通过 reducer edit actions 持久化。
- 产品 UI 可通过同一 codec 生成临时 `.sparkrec_workflow` 并交给 macOS share sheet 分享。
- 产品 UI 可在导入前提示 package 引用的本地缺失 macro，但 package 仍不携带 macro payload。
- 删除 workflow 不删除 SavedMacro。
- 删除 SavedMacro 时 workflow task 可以进入 missing-macro 状态，而不是崩溃。
- Repository 测试使用临时目录，不碰真实 Application Support。

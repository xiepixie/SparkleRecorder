# SparkleRecorder 2026 架构与测试现代化报告

> 文档状态（2026-07-05）：主规划仍然有效，但早期“当前现状”段落是审计快照。已经落地或基本落地的项目以 [DOCUMENTATION_STATUS.md](DOCUMENTATION_STATUS.md) 和 [automation-engine/00-current-status.md](automation-engine/00-current-status.md) 为准；编排引擎的后续执行计划维护在 [automation-engine/README.md](automation-engine/README.md)。

本文基于当前工作区 `/Applications/SparkleRecorder` 的代码阅读结果，给出 SparkleRecorder 后续大重构的架构与测试演进计划。本文只讨论设计与计划，不要求立即改动产品代码。

## 1. 当前结论

SparkleRecorder 已经不是一个简单的“屏幕坐标点击器”。它现在包含：

- 原始事件录制：`RecordedEvent`
- 语义动作分组：`ActionGroup` / `EventGrouper`
- 宏库和元数据：`SavedMacro` / `MacroLibrary`
- 窗口绑定和坐标映射：`PlaybackSurface` / `PlaybackContext` / `PointResolver`
- OCR 文本锚点：`TextAnchor` / `LocatorEngine` / `VisionDetector`
- 菜单栏、Dock、HUD、编辑器和导入导出 UI

它正在向桌面 RPA 工具演进。下一阶段最重要的事情不是继续往现有 controller 里塞功能，而是把项目拆成可测试、可并发隔离、可打包资源、可状态编排的架构。

编排引擎的执行计划已经拆分到 [automation-engine/README.md](automation-engine/README.md)。该目录维护当前状态、先合同后并行的任务拆分、每条并行线的验收条件，以及 AutomationEngine 的 reducer、资源仲裁、Player/Scheduler client、持久化和 FlowGraph/Resource Timeline 规划。

## 2. 当前代码架构画像

### 2.1 SwiftPM 模块现状

当前 `Package.swift` 使用 Swift tools 6.0，产品分成：

| Target | 当前职责 |
| --- | --- |
| `SparkleRecorderCore` | `RecordedEvent`, `SavedMacro`, `TextMacroFormat`, `MacroImport`, `PointResolver`, `EventGrouper`, `CoordinateMapper` |
| `SparkleRecorder` | AppKit/SwiftUI UI、录制器、播放器、窗口/OCR、宏库、编辑器 |
| `SparkleRecorderTests` | Swift Testing 单元测试 |

现状问题：

- package 顶层仍是 `swiftLanguageModes: [.v5]`，只有测试 target 显式使用 Swift 6。
- Core target 包含了一些依赖 AppKit 的逻辑，例如 `PointResolver` 在可用时 import AppKit 并查询 running apps。
- 录制、播放、窗口追踪、OCR 仍在 app target 内，导致核心行为难以用纯单元测试覆盖。

### 2.2 状态管理现状

当前主要状态对象：

| 类型 | 技术 | 风险 |
| --- | --- | --- |
| `AppState` | `ObservableObject` + `@Published` + `UserDefaults` | 设置、权限轮询、声音副作用混在一起 |
| `MacroLibrary` | `ObservableObject` + 直接文件读写 | 宏数据、迁移、排序、过滤、持久化耦合 |
| `Recorder` | `ObservableObject` + `EventTapThreadDelegate` + `OSAllocatedUnfairLock` | UI 状态和事件 tap 线程共享可变状态 |
| `Player` | `ObservableObject` + detached task + conflict monitor | 播放调度、OCR、窗口激活、失败截图、状态发布耦合 |
| `MenuBarController` | `@MainActor NSObject` | App 编排中心过大，承担录制、播放、库、热键、导入导出、UI 生命周期 |

这套结构短期能跑，但继续扩展到实图、定时任务、状态编排后，复杂度会集中爆炸在 `MenuBarController`、`Player` 和 `Recorder`。

### 2.3 数据模型现状

当前数据层已经有不错的基础：

- `RecordedEvent` 保留原始事件、坐标、滚轮 payload、Unicode、窗口坐标、内容区坐标、OCR 文本锚点。
- `SavedMacro` 存储 loops、speed、surfaces、tags、favorite、hotkey、notes、chainTo 和统计信息。
- `ActionGroup` 是编辑器语义层，用于把 raw events 折叠成点击、拖拽、滚动、快捷键、文本输入、等待、OCR 等动作。

主要问题：

- `RecordedEvent` 逐渐承担太多职责，已经混合 raw event、locator 参数、编辑器行为分组和回放策略。
- `SavedMacro` 是单文件 JSON 模型，未来承载截图、模板、OCR cache、运行证据会很吃力。
- `ActionGroup` 是运行时派生结构，还不是持久化的“语义动作计划”。

### 2.4 录制链路现状

当前录制链路：

```text
CGEventTap -> EventTapThread -> Recorder.eventTapThread -> pending buffer -> 30Hz flush -> @Published events
```

优点：

- event tap 独立线程，避免直接卡主线程。
- pending buffer + 30Hz flush 避免每个事件触发 SwiftUI 更新。
- drag downsampling 和 surface tracking 已经开始处理性能问题。

风险：

- 回调仍直接调用 `Recorder`，通过 delegate 跨线程访问对象。
- `Recorder` 通过 lock 保护局部状态，但对象整体不是 actor-isolated。
- 回调里仍构造完整 `RecordedEvent`，包括窗口 surface、内容坐标、滚轮 payload 和 Unicode，录制职责偏大。
- 未来 Swift 6 complete concurrency 打开后，这部分大概率是主要警告来源。

### 2.5 播放链路现状

当前播放链路：

```text
MenuBarController -> Player.play -> Task.detached loop
                 -> WindowTracker resolve
                 -> PointResolver / LocatorEngine
                 -> MouseKeyboardSynthesizer / CGEventPoster
                 -> PlaybackConflictMonitor
```

优点：

- 已支持 loops、speed、窗口激活、窗口 frame 重解析、OCR wait/verify、失败截图、用户输入冲突监控。
- `PointResolver` 和 `MouseKeyboardSynthesizer` 有一定单元测试基础。

风险：

- `Player` 同时承担调度、状态、OCR、窗口、失败证据、冲突监控和 UI 发布。
- 使用 `Task.detached` 和 busy-wait 精确等待，测试难度高，也不利于可控时间模拟。
- `PlaybackContext` 是 mutable struct，在播放循环内被持续修改；需要明确 actor/ownership 边界。
- `ScreenCaptureService` 是 actor，但调用点仍散在播放器中。

### 2.6 测试现状

当前测试已经使用 Swift Testing：

- `import Testing`
- `@Suite`
- `@Test`
- `#expect`

覆盖范围包括：

- 文本宏格式 roundtrip
- legacy `.rec` 空文件错误
- `SavedMacro` 兼容解码
- `MouseKeyboardSynthesizer` dry run
- `PointResolver`
- `EventGrouper`
- OCR strategy 编码/解码
- 滚轮 payload 和 playback delta 规则

不足：

- 没有状态机测试。
- 没有录制引擎 fake event stream 测试。
- 没有播放器时间调度和取消/冲突测试。
- 没有宏库 repository 级别的文件系统测试。
- 没有 `.sparkrec` 包格式测试。
- 没有 SwiftUI 组件快照测试。
- 没有关键 App 启动/权限链路的最小 XCUITest。

## 3. 2026 技术基线

基于 2026 年 Swift 生态，建议以这些原则作为重构基线：

| 领域 | 建议 |
| --- | --- |
| 测试框架 | 继续使用 Swift Testing，扩大参数化测试和 trait 使用 |
| 并发 | 分模块逐步迁移到 Swift 6 language mode 和 strict concurrency |
| 状态观察 | 新代码优先用 `@Observable`，旧 `ObservableObject` 分阶段迁移 |
| 状态管理 | 采用 Actor-Isolated UDF；复杂 UI/工作流可引入 TCA 或 TCA-style reducer |
| 依赖注入 | 用显式 client/protocol + test implementation，不让测试触发真实 CGEvent |
| 时间控制 | 引入 clock abstraction，测试里用 `TestClock` 风格快进 |
| UI 测试 | 少量 XCUITest + 更多组件级快照/状态测试 |

参考资料：

- Apple Swift Testing documentation: <https://developer.apple.com/documentation/testing>
- Apple Swift Testing overview: <https://developer.apple.com/xcode/swift-testing/>
- Swift 6 migration guide: <https://www.swift.org/migration/>
- Swift 6 concurrency incremental adoption: <https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/>
- Apple Observation framework: <https://developer.apple.com/documentation/observation>
- Apple `@Observable` macro: <https://developer.apple.com/documentation/observation/observable%28%29>
- TCA `TestStore`: <https://pointfreeco.github.io/swift-composable-architecture/1.9.0/documentation/composablearchitecture/teststore/>

## 4. 推荐目标架构

### 4.1 总体形态

建议目标是“Actor-Isolated UDF + 可选 TCA-style Feature”：

```text
SwiftUI/AppKit Views
        |
        v
AppStore / Feature Reducers
        |
        v
Dependency Clients
        |
        +-- RecordingEngine actor
        +-- PlaybackEngine actor
        +-- MacroRepository actor
        +-- WindowLocator actor/client
        +-- VisionClient actor
        +-- SchedulerClient
        +-- EventPosterClient
```

核心原则：

- UI 只发送 `Action`，不直接调用 CGEvent、ScreenCaptureKit、AX、文件系统。
- 引擎是 actor 或明确 global actor 隔离。
- 底层回调通过 `AsyncStream` 进入系统。
- 宏数据和动作计划是 pure value / `Sendable`。
- 所有副作用通过 client 注入，测试替换为 fake。

### 4.2 模块拆分建议

建议逐步拆为：

| 模块 | 内容 |
| --- | --- |
| `SparkleRecorderDomain` | `RecordedEvent`, `SavedMacro`, `ActionPlan`, `WorkflowState`, package manifest，全部尽量 `Sendable` |
| `SparkleRecorderEngine` | 录制、播放、调度、坐标解析、动作解释器 |
| `SparkleRecorderVision` | OCR、template matching、截图证据、视觉资源索引 |
| `SparkleRecorderPersistence` | `.tinyrec`, `.sparkrec`, macro library repository |
| `SparkleRecorderApp` | AppKit/SwiftUI UI、menu bar、windows、commands |
| `SparkleRecorderTestSupport` | fake clients、fixtures、sample macros、test clocks |

这样能把可测试核心从 macOS UI 中抽出来。

### 4.3 状态模型建议

定义明确的 app state：

```swift
struct AppModel: Sendable {
    var library: LibraryState
    var recorder: RecorderState
    var player: PlayerState
    var permissions: PermissionState
    var editor: EditorState?
    var scheduler: SchedulerState
}
```

定义 action：

```swift
enum AppAction: Sendable {
    case recordButtonTapped
    case recording(RecordingAction)
    case playback(PlaybackAction)
    case library(LibraryAction)
    case editor(EditorAction)
    case permissionsChanged(PermissionState)
    case engineEvent(EngineEvent)
}
```

这不要求一开始就引入 TCA。可以先实现一个轻量 reducer：

```text
reduce(state:inout AppModel, action:AppAction) -> [Effect<AppAction>]
```

等核心状态稳定，再决定是否正式引入 TCA。

### 4.4 录制引擎建议

把当前 `EventTapThread -> Recorder delegate` 改成：

```text
EventTapClient.events(mask) -> AsyncStream<SystemInputEvent>
RecordingEngine actor consumes stream -> RecordedEventBatch
MainActor store receives RecordingAction.batchRecorded
```

拆分职责：

| 当前职责 | 目标归属 |
| --- | --- |
| event tap lifecycle | `EventTapClient` |
| time normalization | `RecordingEngine` |
| drag sampling | `RecordingEngine` or `TrajectorySampler` |
| surface tracking | `WindowContextClient` |
| pending batch | `RecordingEngine` emits batches |
| UI live stats | reducer 从事件批量派生 |

收益：

- 回调不直接碰 UI object。
- Swift 6 数据隔离更清晰。
- 可以用 fake `AsyncStream` 测录制流程。

### 4.5 播放引擎建议

把 `Player` 拆成：

| 新组件 | 职责 |
| --- | --- |
| `PlaybackPlanner` | 把 `SavedMacro` / `ActionPlan` 转为可执行 step |
| `PlaybackEngine actor` | 执行 loop、speed、取消、暂停、恢复 |
| `ClockClient` | 控制等待和测试快进 |
| `PointLocationClient` | 坐标、OCR、template fallback |
| `EventPosterClient` | 发送 CGEvent，测试中不动鼠标 |
| `EvidenceRecorder` | 保存失败截图、运行结果 |
| `ConflictMonitorClient` | 用户输入冲突流 |

不要让播放器直接保存截图或查询 UI。播放器应该只发出：

```swift
enum PlaybackEvent: Sendable {
    case started(runID: UUID)
    case stepStarted(index: Int)
    case stepCompleted(index: Int)
    case waitingForText(String)
    case failed(PlaybackFailure)
    case completed
    case cancelled
}
```

### 4.6 宏格式建议

当前 `.tinyrec` 保留兼容。下一代 `.sparkrec` 作为 Spark Record 包格式：

```text
macro.sparkrec
├── manifest.json
├── macro.json
├── actions.json
├── raw-events.json
├── surfaces.json
├── assets/
│   ├── templates/
│   ├── screenshots/
│   └── ocr/
├── schedules/
└── state/
```

关系：

- `.tinyrec`：v3 单 JSON，继续导入导出。
- `.sparkrec`：v4 包格式，一个完整录制。
- `.sparkflow`：未来复杂编排，多宏、多状态、多调度。

详见 `docs/FormatEvolutionPlan.md`。

## 5. 测试策略

### 5.1 测试金字塔

建议分层：

| 层级 | 工具 | 覆盖 |
| --- | --- | --- |
| Pure unit tests | Swift Testing | parser、grouper、resolver、planner、package manifest |
| Reducer/state tests | Swift Testing + TestStore 或自研 TestStore | action -> state/effect |
| Engine tests | fake clients + test clock | recording stream、playback timing、cancel、pause、failure |
| Repository tests | temp directory | library migration、atomic save、corrupt backup、`.sparkrec` import/export |
| Vision tests | image fixtures | OCR scoring、template matching、fallback |
| Component snapshot | SwiftUI snapshot testing | library cards、editor sidebar、HUD states |
| Minimal E2E | XCUITest | app launch、permission banner、import sample macro |

### 5.2 当前测试应扩展的清单

优先新增：

1. `TextMacroFormat` 参数化测试：空行、注释、旧 header、无效 verb、Unicode、flags。
2. `LegacyRecImporter` fixture 测试：真实 `.rec` 样本，键盘、鼠标、滚轮。
3. `PointResolver` 参数化测试：content normalized、window local、out-of-bounds、多屏。
4. `EventGrouper` 参数化测试：multiPointClick、scroll segment、shortcut、textInput、behavior binding。
5. `MacroLibrary` temp directory 测试：迁移、corrupt backup、delete/chain cleanup、hotkey uniqueness。
6. `PlaybackPlanner` 测试：loop、speed、chain、防循环、locator fallback policy。
7. `RecordingEngine` fake stream 测试：ignored hotkey、drag sampling、surface lock、batch flush。
8. `.sparkrec` package roundtrip 测试。

### 5.3 不应该大量做的测试

- 不要在单元测试里真实移动鼠标。
- 不要依赖真实 System Settings 权限状态。
- 不要用 `Task.sleep` 等待异步状态。
- 不要用大量 XCUITest 测编辑器细节。

## 6. 分阶段迁移计划

### Phase 0：稳定当前提交前状态

目标：先让项目在新工作区下可持续构建。

任务：

- 确认 `swift test` 通过。
- 确认 `swift build -c release` 在无人编辑文件时通过。
- 清理当前工作树里旧路径删除和新路径新增的提交状态。
- 保持 Apache-2.0 LICENSE。
- 不在这个阶段做架构重写。

验收：

- `swift test`
- `swift build -c release`
- `rg "TinyRecorder|TinyTask" .` 仅允许在提交计划说明旧路径时出现。

### Phase 1：核心模型 Sendable 化

目标：让 domain 层适配 Swift 6 strict concurrency。

任务：

- 把纯模型拆到 `SparkleRecorderDomain`。
- 给 `RecordedEvent`, `SavedMacro`, `PlaybackSurface`, `ActionGroup` 等补齐 `Sendable` 审计。
- 移除 domain 层对 AppKit/NSWorkspace 的依赖。
- `PointResolver` 中需要 AppKit 的窗口查询抽为 dependency。

验收：

- Domain target 使用 Swift 6 language mode。
- Domain tests 无并发警告。

### Phase 2：依赖客户端化

目标：所有系统副作用可替换。

新增 clients：

- `EventTapClient`
- `EventPosterClient`
- `WindowContextClient`
- `VisionClient`
- `PermissionClient`
- `MacroRepositoryClient`
- `ClockClient`
- `EvidenceClient`

验收：

- 单元测试不触发真实 CGEvent、ScreenCaptureKit、AX、UserDefaults。
- 录制和播放测试用 fake clients 跑通。

### Phase 3：录制引擎 actor 化

目标：消除 event tap callback 直接触碰 UI object。

任务：

- `EventTapThread` 只产生 `AsyncStream<SystemInputEvent>`。
- `RecordingEngine actor` 消费 event stream。
- `Recorder` 退化为 MainActor view model 或 store adapter。
- pending/batch flush 变成 engine output。

验收：

- fake stream 可测录制完整流程。
- 开启 Swift 6 strict concurrency 后无核心 data race 警告。

### Phase 4：播放引擎 actor 化

目标：让播放可取消、可暂停、可测试、可恢复。

任务：

- 抽 `PlaybackPlanner`。
- 抽 `PlaybackEngine actor`。
- 用 `ClockClient` 取代硬编码 sleep/busy wait。
- 失败截图从播放器中移到 `EvidenceClient`。
- 用户冲突监控变成 async event stream。

验收：

- 播放 loop/speed/cancel/conflict/failure 都有 Swift Testing 覆盖。
- 测试耗时不依赖真实 sleep。

### Phase 5：`.sparkrec` 包格式

目标：支持视觉资源、OCR cache、运行证据和未来状态编排。

任务：

- 实现 `RecordingPackageManifest`。
- 实现 package reader/writer。
- `.tinyrec` 继续支持。
- `.sparkrec` 导出先不包含复杂状态机，先保存 `raw-events.json`, `macro.json`, `surfaces.json`。

验收：

- `.sparkrec` roundtrip tests。
- package 缺失 assets 时可正常导入。
- manifest schema version 测试。

### Phase 6：状态编排和定时任务

目标：从“宏播放器”升级为可编排 RPA。

任务：

- 定义 `ActionPlan`。
- 定义 `WorkflowStateMachine`。
- 定义 scheduler trigger：time、interval、app active、file changed、manual。
- 支持 retry、timeout、branch、assert、evidence。

验收：

- reducer/TestStore 测 action/state/effect。
- 调度测试使用 fake clock。
- E2E 只保留核心 happy path。

## 7. 风险和注意事项

### 7.1 不建议一次性上完整 TCA

TCA 对复杂状态机很强，但当前项目还有 AppKit、CGEvent、ScreenCaptureKit、热键、状态栏等底层复杂性。建议先做 TCA-style 的 UDF 和 dependency clients。等领域模型稳定后，再决定是否正式引入 TCA。

### 7.2 不建议立即移除 `.tinyrec`

`.tinyrec` 已经是用户可见兼容格式。应新增 `.sparkrec`，而不是破坏旧文件。

### 7.3 不建议继续扩大 `MenuBarController`

它已经是编排中心。新增定时任务、状态机、云同步、视觉资源时，不应继续往这里加核心逻辑。

### 7.4 不建议把 OCR/template 直接塞进 `Player`

播放器应该依赖 `PointLocationClient`，不关心 OCR、模板还是 AX。

### 7.5 当前工作树仍在编辑中

当前仓库有大量未提交改动，包含旧路径删除和新路径新增。提交前应先完成用户正在做的修改，再跑：

```bash
swift test
swift build -c release
git status --short
```

## 8. 建议的下一步

最实际的下一步不是直接写新功能，而是建立重构护栏：

1. 新建 `SparkleRecorderDomain` target。
2. 把纯模型迁入 domain target。
3. 将 domain target 切 Swift 6 language mode。
4. 给 domain 模型补 `Sendable`。
5. 引入 dependency client 协议，但先保持实现仍调用旧类。
6. 把 `TextMacroFormat`, `EventGrouper`, `PointResolver` 测试扩成参数化。
7. 再开始录制/播放 actor 化。

这个顺序可以让项目每一步都可编译、可测试、可回退，不会陷入“一口气重写引擎”的泥坑。

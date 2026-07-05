# SparkleRecorder 项目架构

> 文档状态（2026-07-05）：这是当前产品心智模型和架构快照。Swift 6、录制边界、播放器失败证据等底座已经继续推进；定时启动、依赖编排、资源仲裁和 FlowGraph 还没有进入产品代码，后续以 [DOCUMENTATION_STATUS.md](DOCUMENTATION_STATUS.md) 与 [automation-engine/README.md](automation-engine/README.md) 跟踪。

本文记录 SparkleRecorder 当前的数据结构、动作设计、用户使用逻辑和功能边界，便于后续继续重构或扩展。

## 1. 项目定位

SparkleRecorder 是一个原生 macOS 宏录制和回放工具。它的核心目标是把用户在桌面上的输入行为录制为结构化事件，保存到本地宏库，再按原始时间轴、窗口上下文、坐标策略或 OCR 文本锚点进行回放。

主要技术栈：

| 层级 | 技术 |
| --- | --- |
| App 壳 | AppKit、SwiftUI、NSStatusItem、NSWindowController |
| 输入录制 | `CGEventTap`、独立 `EventTapThread`、mach timestamp |
| 输入回放 | `CGEvent` post、Carbon key codes、synthetic event loopback marker |
| 全局快捷键 | Carbon `RegisterEventHotKey` |
| 窗口定位 | CoreGraphics window list、Accessibility、ScreenCaptureKit |
| OCR | Vision text recognition |
| 持久化 | Codable JSON，Application Support 本地文件 |

## 2. 模块划分

| 模块 | 关键文件 | 职责 |
| --- | --- | --- |
| 应用入口 | `main.swift`, `AppDelegate.swift` | App/CLI 分发、菜单、文件打开、帮助入口 |
| 状态编排 | `MenuBarController.swift`, `AppState.swift` | 录制/播放/导入/导出流程，权限状态，用户偏好 |
| 宏库 | `MacroLibrary.swift`, `SavedMacro.swift` | 保存宏、筛选、统计、标签、收藏、链式播放 |
| 录制引擎 | `Recorder.swift`, `EventTapThread.swift`, `RecordingSurfaceTracker.swift` | 监听输入事件，计算时间戳，采集窗口 surface，批量刷新 UI |
| 播放引擎 | `Player.swift`, `MouseKeyboardSynthesizer.swift` | 按时间轴调度事件，发送合成输入，检测用户打断 |
| 坐标解析 | `PointResolver.swift`, `CoordinateMapper.swift`, `WindowTracker.swift` | 将录制时坐标映射到当前屏幕或当前窗口 |
| OCR/定位 | `ScreenCaptureService.swift`, `VisionDetector.swift`, `LocatorEngine.swift` | 截图、识别文字、按文本锚点定位点击目标 |
| 编辑器 | `MacroEditor.swift`, `MacroTransformer.swift`, `Components/Editor/*` | 时间线、动作列表、侧边栏、文本/坐标 picker、批量编辑 |
| 导入导出 | `MacroImport.swift`, `TextMacroFormat.swift` | native JSON、legacy `.rec`、TRM 文本格式转换 |

## 3. 核心数据结构

### 3.1 `RecordedEvent`

`RecordedEvent` 是最底层的录制单位，表示一个可回放的输入事件。

关键字段：

| 字段 | 含义 |
| --- | --- |
| `kind` | 事件类型，例如鼠标、键盘、滚轮、等待文本、校验文本 |
| `time` | 从录制开始计算的相对秒数 |
| `x`, `y` | 录制时的全局屏幕坐标 |
| `keyCode`, `flags` | 键盘 key code 与修饰键位 |
| `mouseButton`, `clickCount` | 鼠标按钮与点击次数 |
| `scrollDeltaX`, `scrollDeltaY`, `scrollPayload` | 滚轮方向、像素/行滚动、滚动阶段 |
| `windowLocalX/Y` | 相对目标窗口外框的坐标 |
| `windowNormalizedX/Y` | 相对目标窗口外框归一化坐标 |
| `contentLocalX/Y` | 相对窗口内容区的坐标 |
| `contentNormalizedX/Y` | 相对窗口内容区归一化坐标 |
| `coordinateBinding` | 事件绑定到目标窗口、全局屏幕或未绑定 |
| `coordinateStrategy` | 播放时优先使用窗口坐标、归一化坐标、绝对坐标或 locator |
| `locatorFallbackPolicy` | OCR/定位失败后是否允许坐标兜底 |
| `surfaceId` | 事件关联的窗口 surface |
| `textAnchor` | OCR 文本锚点 |
| `textTimeout`, `verifyMustExist` | 文本等待/校验参数 |
| `behaviorGroupID`, `behaviorGroupName` | 编辑器语义动作分组标识 |

`RecordedEvent.Kind` 当前覆盖：

| 类别 | Kind |
| --- | --- |
| 鼠标 | `leftMouseDown`, `leftMouseUp`, `rightMouseDown`, `rightMouseUp`, `mouseMoved`, `leftMouseDragged`, `rightMouseDragged`, `otherMouseDown`, `otherMouseUp`, `otherMouseDragged` |
| 键盘 | `keyDown`, `keyUp`, `flagsChanged` |
| 滚轮 | `scrollWheel` |
| OCR/语义 | `waitForText`, `verifyText` |

### 3.2 `SavedMacro`

`SavedMacro` 是宏库中的一个完整条目，包住事件列表和用户配置。

| 字段 | 含义 |
| --- | --- |
| `id`, `name`, `createdAt`, `modifiedAt`, `version` | 宏身份与版本 |
| `events` | `RecordedEvent` 数组 |
| `loops`, `speed` | 回放次数与速度 |
| `surfaces` | 录制时捕获到的窗口 surface 字典 |
| `followWindowOffset` | 是否随当前窗口位置偏移回放 |
| `icon`, `accent`, `tags`, `favorite` | 库卡片展示和筛选元数据 |
| `hotkey` | 每个宏自己的全局快捷键 |
| `notes` | 用户备注 |
| `chainTo` | 播放结束后自动串联的下一个宏 |
| `playCount`, `lastPlayedAt`, `totalRunTime` | 使用统计 |

库文件位置：

```text
~/Library/Application Support/SparkleRecorder/library.json
```

### 3.3 `PlaybackSurface` 与 `PlaybackContext`

`PlaybackSurface` 描述录制时的目标窗口，包括 bundle id、窗口标题、窗口 id、显示器 id、窗口外框和内容区。播放时 `PlaybackContext` 会携带：

| 字段 | 含义 |
| --- | --- |
| `surfaces` | 录制时保存的 surface |
| `currentSurfaceFrames` | 播放前解析到的当前窗口外框 |
| `currentContentFrames` | 播放前解析到的当前内容区 |
| `currentTitleBarHeights` | 标题栏高度缓存 |
| `coordinateMode` | 全局绝对坐标、窗口偏移、归一化窗口坐标等策略 |

### 3.4 `TextAnchor`

`TextAnchor` 用来把动作绑定到可见文本，而不是固定坐标。

| 字段 | 含义 |
| --- | --- |
| `text` | 要匹配的文本 |
| `matchMode` | `contains` 或 `exact` |
| `observedFrame` | 录制时文本所在屏幕区域 |
| `searchRegion` | 回放时搜索区域 |
| `occurrenceHint` | 多个匹配项时选择第几个 |
| `coordinateFallback` | OCR 失败时可选坐标兜底 |
| `observedContentNormalizedFrame` | 内容区归一化文本区域 |
| `searchContentNormalizedRegion` | 内容区归一化搜索区域 |

## 4. 动作设计

SparkleRecorder 把动作分成两层：底层事件和语义动作组。

底层事件来自 `RecordedEvent.Kind`，保留精确时间、坐标、按键、滚轮等原始信息。播放引擎直接消费这一层。

语义动作组来自 `EventGrouper`，用于编辑器展示和批量操作：

| `ActionGroupKind` | 设计意图 |
| --- | --- |
| `click`, `doubleClick`, `repeatedClick` | 合并 down/up 和多次连续点击 |
| `longPress` | 鼠标按住超过阈值 |
| `drag` | down、dragged、up 组成的拖拽路径 |
| `scroll` | 时间接近的滚轮事件合并成滚动 burst |
| `keyPress`, `keyHold`, `keyRepeat` | 单键、长按、重复键 |
| `shortcut`, `modifierHold` | 修饰键组合与修饰键保持 |
| `textInput` | 连续文本输入 |
| `wait` | 两个事件间超过阈值的空档 |
| `mouseMove` | 原始移动事件 |
| `waitForText`, `verifyText` | OCR 等待与校验 |
| `sequence` | 编辑器显式组合的行为块 |

分组阈值集中在 `EventGroupingOptions`，例如点击合并距离、长按阈值、滚动 burst 间隔和等待阈值。

## 5. 录制流程

1. 用户触发 Record。
2. `MenuBarController` 检查权限、展示倒计时和 HUD。
3. `Recorder.startRecording()` 清空当前事件、启动 `RecordingSurfaceTracker`。
4. `EventTapThread` 在独立线程创建 listen-only `CGEventTap`。
5. 每个输入事件进入 `Recorder.eventTapThread(_:didReceive:event:)`。
6. Recorder 计算 mach timestamp 相对时间，补充坐标、窗口 surface、滚轮信息和按键字段。
7. 事件先进入 `pending` 缓冲，再由 30Hz timer 刷新到 `@Published events`，避免高频输入导致 SwiftUI 频繁重绘。
8. Stop 时停止 event tap，flush pending，更新 `liveDuration` 和统计。
9. `MacroLibrary` 将事件保存为 `SavedMacro`。

## 6. 播放流程

1. 用户触发 Play、宏卡片播放或宏专属热键。
2. `MenuBarController` 选择当前 `SavedMacro` 并构建 `PlaybackContext`。
3. `Player.play()` 启动异步播放任务，按 loop/speed 调度。
4. 播放每一轮之前尝试激活目标 app，并通过 `WindowTracker` 更新当前窗口外框和内容区。
5. 对每个事件，`PointResolver` 先尝试窗口/归一化/绝对坐标解析。
6. 如果事件带 `TextAnchor`，`LocatorEngine` 会调用 `ScreenCaptureService` 和 `VisionDetector` 通过 OCR 查找当前文本位置。
7. 解析出目标点后，`MouseKeyboardSynthesizer` 发送合成输入。
8. 合成事件写入 `"SPARKLE!"` loopback marker，录制 tap 和播放冲突监控会忽略这些事件。
9. 如果用户在播放期间真实输入，`PlaybackConflictMonitor` 会标记冲突，播放可提前停止。
10. 播放自然结束后更新统计，并按 `chainTo` 继续下一个宏。

## 7. 导入导出

| 格式 | 入口 | 说明 |
| --- | --- | --- |
| `.tinyrec` / `.json` | `SavedMacro`, `Macro` Codable | 原生 JSON，保留完整元数据 |
| `.rec` | `LegacyRecImporter` | 解析 20 字节 EVENTMSG 记录，映射 Windows VK 到 macOS key code |
| `.txt` / `.trm` | `TextMacroFormat` | 人可编辑的文本格式，当前 header 为 `SPARKLERECORDER 1` |
| `.command` | `MenuBarController.exportCommandScript` | 内嵌 base64 JSON，通过 CLI `--play` 自运行 |
| `.sparkrec` | 规划中 | 下一代 Spark Record 包格式，用于保存截图、OCR、模板、调度和状态编排资源 |

CLI 支持：

```bash
SparkleRecorder --play macro.tinyrec
SparkleRecorder --convert input.rec output.tinyrec
SparkleRecorder --convert input.tinyrec output.txt
```

格式演进建议见 [FormatEvolutionPlan.md](FormatEvolutionPlan.md)。

## 8. 用户功能清单

| 功能 | 用户价值 |
| --- | --- |
| 录制/停止/播放 | 快速捕获并复用重复操作 |
| 全局热键 | 不切换到 SparkleRecorder 也能控制宏 |
| 宏库筛选 | 按全部、收藏、最近、播放最多、热键和标签组织 |
| 宏卡片菜单 | 重命名、复制、删除、导出、标签、收藏、绑定窗口 |
| 时间线编辑 | 修剪、移动、缩放时间、插入等待、编辑单个事件 |
| OCR 文本 picker | 将动作绑定到界面文字，提高窗口变化后的稳定性 |
| 坐标 picker | 手动设置动作目标点 |
| 窗口绑定 | 按当前窗口偏移或内容区坐标回放 |
| 链式播放 | 一个宏结束后自动触发另一个宏 |
| 导入导出 | 在原生 JSON、legacy `.rec`、文本和脚本之间转换 |
| 欢迎流程 | 引导权限和基础热键 |
| 偏好设置 | 控制热键、声音、菜单栏模式、鼠标移动录制等 |

## 9. 已优化的问题

本次品牌迁移同时处理了以下问题：

- 模块、target、Xcode scheme、源码目录、测试目录统一为 SparkleRecorder 命名。
- 用户可见文案、本地化、Info.plist、脚本变量、README 中的旧品牌名已替换。
- `.rec` 导入器从品牌名改为 `LegacyRecImporter`，避免把外部兼容格式误认为 SparkleRecorder 自有格式。
- 文本宏导出 header 改为 `SPARKLERECORDER 1`，导入仍兼容改名前的旧 header。
- Application Support 目录改为 `SparkleRecorder`，并在新库文件不存在时自动复制旧库，降低升级后数据丢失风险。
- 合成事件 loopback marker 从旧的短标记改为 `"SPARKLE!"`，并同步录制 tap、播放冲突监控和事件发送器。
- 失败截图路径从旧目录迁移到 `Application Support/SparkleRecorder`。

## 10. 后续建议

- 将 loopback marker 提取为一个共享常量，避免多个文件重复硬编码。
- 为 `LegacyRecImporter` 增加真实 `.rec` 样本测试，覆盖滚轮、修饰键和非 US 键盘边界。
- 为 OCR 定位增加 UI 自动化测试或截图 fixture，验证多语言匹配和 fallback 逻辑。
- 将 template matching 的能力边界明确为实验功能，或者补齐正式实现。

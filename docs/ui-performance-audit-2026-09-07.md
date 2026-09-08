# 宏库与自动化编辑性能审阅与优化结果

Updated: 2026-09-08

Baseline: `b0f02850b`

Role: 已完成代码级性能修复、回归测试与 Release 构建验证；真实窗口移动 / resize / Back 的 Instruments 帧时间仍需要在交互式 App 会话中采集，不能用单元测试替代。

## 已完成优化

### 1. 宏库卡片不再逐卡重复生成整库链式数据

`Components/Library/LibraryMainView.swift` 现在只在窗口卡片列表层生成一次 `chainCandidates` 和 `chainNameByID`，再把同一份值传给可见卡片。原审阅中“compactMacroRow 也传入 chainCandidates”的说法已纠正：紧凑行本来就没有这条开销。

`MacroCard.chainSubmenu` 也不再先为每张卡创建一份过滤后的候选数组，而是在菜单内容中跳过自身。

另外，未选择任何宏时不再为了求可见选择集而构造完整 `Set(filtered.map(\.id))`。

### 2. 侧栏计数与统计合并为单次扫描投影

新增 `LibrarySidebarProjection`：一次遍历宏即可得到：

- All / Favorites / Recent / Most Played / With Hotkey 计数；
- tag / accent 计数与名称集合；
- total macros / plays / saved time。

这移除了侧栏逐行 `library.macros(for:search:).count`，因此 `Most Played` 计数不再先排序整库，也移除了 StatsSummary 的重复 reduce。

`Recent` 仍以每次视图投影时的当前时间计算 7 天 cutoff，没有引入会过期的长期缓存。

### 3. Automation 返回目录路径减少编辑态派生工作

`AutomationMainContentView` 在 catalog 模式下不再生成：

- selected workflow / timeline 编辑数据；
- authoring repair signature；
- workflow ID repair 输入。

这些派生工作只在 editor 模式启用。

`AutomationOverviewModel.publish` 新增语义状态相等保护：runtime revision 即使变新，如果 `AutomationRunState` 与 working state 完全相同，也不再启动新的 projection build。对应回归测试已加入。

### 4. Catalog 最近运行改为预构建索引

新增 `AutomationCatalogRunIndex`。它随离主线程构建的 Overview projection set 一起生成，按 workflow 预存：

- execution 总数；
- 最近 5 条；
- 最新 needs-attention execution。

Catalog 详情页不再每次选择 workflow 都扫描完整 `runs.executions` 再只显示前 5 条。

完整 workflow history 的筛选仍保留在“用户真正打开 History sheet”时执行。这不是返回目录热路径，继续缓存会增加无必要的长期状态与失效复杂度。

新增 10,000 executions 回归测试，验证 100 个 workflow 的计数与最近 5 条索引语义。

### 5. 大型 FlowGraph 启用真实 viewport 裁剪

新增 `AutomationFlowGraphViewportProjection`。当节点数 >= 80 且 VoiceOver 未启用时：

- 通过 `onScrollGeometryChange` 跟踪 ScrollView 可见区域；
- 只 materialize 可见区域 + 320pt 预取边界内的节点；
- edge Canvas 和 edge Button/context menu 列表也只接收可见边；
- selected / dragged / linking source task 和 selected dependency 强制保留；
- VoiceOver 启用时完全关闭裁剪，保留辅助功能导航语义。

同一 body 中 `dynamicEdges` 只计算一次，不再分别为 Canvas 与 edge interaction list 重算。

新增 10 / 100 / 500 node 语义测试；500-node 固定夹具下 viewport working set 保持小于 20 个节点。

### 6. 修正 Automation 窄窗口布局契约

主窗口最小宽度仍为 720。

Catalog HSplitView 从 310 + 560 的不可满足组合调整为 280 + 360，使声明最小宽度可落入主窗口契约。

Editor 在窄窗口下按可用宽度自动隐藏次要侧栏：

- 在不足以同时容纳主体与双侧栏时优先保留编辑主体；
- 双栏都请求显示时，右侧 inspector 只有足够宽度才出现；
- 左侧 workflow list 同样受可用宽度约束。

这消除了 720–870 区间内原本必然发生的布局压力。

### 7. 降低窗口合成层成本

保留产品的视觉材质，但减少重复桌面背景采样：

- `AutomationMainContentView` 内层 visual effect 从 `.behindWindow` 改为 `.withinWindow`；
- `LibrarySidebar` 内层 visual effect 同样改为 `.withinWindow`；
- 外层窗口材质仍负责窗口级背景。

MacroCard 普通静止状态不再保留常驻阴影，也不再创建透明 hover/focus 描边层；这些效果只在真实 hover / focus / lifted 状态出现。

这直接针对纯窗口移动时的 compositor / WindowServer 压力，但真实帧时间改善幅度必须由 Instruments 或 WindowServer 采样确认，不能仅凭代码推断数值。

## 验证结果

### 相关性能回归测试

以下重点套件通过：

- `LibrarySidebarProjectionTests`
- `AutomationFlowGraphViewportProjectionTests`
- `AutomationCatalogRunIndexTests`
- `AutomationOverviewModelTests`
- `AutomationViewProjectionScalingTests`
- `AutomationWorkflowAuthoringStateTests`
- `SavedMacroPreviewCacheTests`

合计 30 tests / 7 suites 全部通过。

### 全量测试

执行：

`swift test --scratch-path .build-test --enable-swift-testing --disable-xctest`

结果：**1204 tests / 183 suites passed**。

### 构建

- Swift 6 Debug build：通过。
- Swift 6 Release build：通过。
- `git diff --check`：通过。

`swift format lint` 仍报告仓库既有文件的大量格式 warning；此次修改的产品代码没有引入编译或测试失败，不把无关的全仓格式清理混入性能任务。

## 仍需真实 App 会话完成的验收

以下项目不是代码优化遗漏，而是必须在可交互运行中的 App 上测量：

- [ ] Release 构建下分别录制纯窗口移动、resize、Back-to-catalog、大图拖动的 Time Profiler / SwiftUI Instruments；
- [ ] 固定宏数量 10 / 100 / 1000，节点 10 / 100 / 500，历史 0 / 10,000，记录 p50 / p95 frame time；
- [ ] 同时观察 App CPU、main-thread stall 与 WindowServer / compositor 指标，验证 `.withinWindow` 和卡片层级调整是否命中纯移动瓶颈；
- [ ] 手工验收 720 / 870 / 1080 宽度下的侧栏显示、滚动、菜单、拖放、键盘焦点和 VoiceOver。

在没有真实交互 trace 前，不宣称具体 FPS 或百分比提升；当前可以确认的是热点算法与视图构造路径已经按审阅结论完成结构性修复，并通过完整测试与 Release 构建。

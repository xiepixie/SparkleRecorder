# Automation Engine Planning Index

本文档目录记录 SparkleRecorder 从“单个宏录制/播放器”走向“可编排桌面自动化引擎”的规划。这里不是产品说明页，而是工程执行索引：哪些已经完成、哪些必须串行、哪些可以并行、验收条件是什么。

## 阅读顺序

1. [00-current-status.md](00-current-status.md)
   当前工程状态、已完成迁移、还缺的关键能力。
2. [01-core-contract-first.md](01-core-contract-first.md)
   必须先冻结的 Automation Core 合同。其他并行任务都依赖它。
3. [02-parallel-workstreams.md](02-parallel-workstreams.md)
   三人并行模式、任务边界和协作规则。
4. 三个 owner 的工作文件：
   - [workstreams/owner-a-core-reducer.md](workstreams/owner-a-core-reducer.md)
   - [workstreams/owner-b-adapters-persistence.md](workstreams/owner-b-adapters-persistence.md)
   - [workstreams/owner-c-ui-performance.md](workstreams/owner-c-ui-performance.md)
5. 具体能力规划文件：
   - [03-reducer-state-machine.md](03-reducer-state-machine.md)
   - [04-resource-arbiter.md](04-resource-arbiter.md)
   - [05-player-client.md](05-player-client.md)
   - [06-scheduler-client.md](06-scheduler-client.md)
   - [07-persistence.md](07-persistence.md)
   - [08-ui-flowgraph-timeline.md](08-ui-flowgraph-timeline.md)
   - [09-testing-plan.md](09-testing-plan.md)
6. [10-acceptance-checklist.md](10-acceptance-checklist.md)
   阶段验收清单。每个阶段结束时按此检查。

## 核心原则

- `SavedMacro` 是静态模板，不保存运行实例状态。
- 编排层生成 `AutomationTaskRun`，每次运行都有自己的 `runID`、时间、outcome 和 evidence。
- UI 只能展示 `AutomationTaskRun` 的 run history、outcome 和 evidence metadata，不直接打开 Player internals、截图或 evidence payload。
- 定时启动不是直接调用 `Player`，而是向 reducer 发送 `clockTick(Date)`。
- 前台键鼠控制权是唯一资源，所有终态必须优先释放 lease。
- 条件判断通过 reducer effect 交给 Owner B；`previousOutcome` 只使用 effect 携带的上游 outcome，不让 adapter 回读 state。
- external signal / manual approval 通过 Owner B provider client 注入 runtime host；SwiftUI 只提供 signal source / approval presenter，不直接调用 condition evaluator。
- OCR `searchRegion` 支持 display/window/content 坐标空间解析；产品 authoring 已能通过文字区域 picker、任意 Draw Region、bounds 预览/微调和坐标上下文提示写入 bounds。
- `.sparkrec_workflow` 包格式由 Owner B codec 冻结；产品 UI 负责导入/导出/分享面板、selected/all workflow package、冲突提示和缺失本地宏提醒，仍不能扩展或解释 package JSON 字段。
- Repository refresh 通过 value state 暴露 loading/loaded/failed，不让 SwiftUI 直接捕获文件 IO throw。
- FlowGraph/Inspector 交互只能提交已接受的 reducer action 或 provider source；节点移动、拉线、删线、schedule/condition 表单编辑都不绕过 reducer。
- UI 只展示 reducer projection，不在 SwiftUI view 里实现调度逻辑。
- Swift Testing 优先覆盖 pure reducer 和 clients，不触发真实鼠标、键盘、OCR 或文件系统副作用。

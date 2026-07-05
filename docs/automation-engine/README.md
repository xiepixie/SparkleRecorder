# Automation Engine Planning Index

本文档目录记录 SparkleRecorder 从“单个宏录制/播放器”走向“可编排桌面自动化引擎”的规划。这里不是产品说明页，而是工程执行索引：哪些已经完成、哪些必须串行、哪些可以并行、验收条件是什么。

## 阅读顺序

1. [00-current-status.md](00-current-status.md)
   当前工程状态、已完成迁移、还缺的关键能力。
2. [01-core-contract-first.md](01-core-contract-first.md)
   必须先冻结的 Automation Core 合同。其他并行任务都依赖它。
3. [02-parallel-workstreams.md](02-parallel-workstreams.md)
   可并行/不可并行任务划分和依赖关系。
4. 具体并行任务文件：
   - [03-reducer-state-machine.md](03-reducer-state-machine.md)
   - [04-resource-arbiter.md](04-resource-arbiter.md)
   - [05-player-client.md](05-player-client.md)
   - [06-scheduler-client.md](06-scheduler-client.md)
   - [07-persistence.md](07-persistence.md)
   - [08-ui-flowgraph-timeline.md](08-ui-flowgraph-timeline.md)
   - [09-testing-plan.md](09-testing-plan.md)
5. [10-acceptance-checklist.md](10-acceptance-checklist.md)
   阶段验收清单。每个阶段结束时按此检查。

## 核心原则

- `SavedMacro` 是静态模板，不保存运行实例状态。
- 编排层生成 `AutomationTaskRun`，每次运行都有自己的 `runID`、时间、outcome 和 evidence。
- 定时启动不是直接调用 `Player`，而是向 reducer 发送 `clockTick(Date)`。
- 前台键鼠控制权是唯一资源，所有终态必须优先释放 lease。
- UI 只展示 reducer projection，不在 SwiftUI view 里实现调度逻辑。
- Swift Testing 优先覆盖 pure reducer 和 clients，不触发真实鼠标、键盘、OCR 或文件系统副作用。

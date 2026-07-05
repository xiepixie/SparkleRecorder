# Automation Engine Current Status

本文记录截至当前工作树的迁移状态。状态以代码事实为准，不把规划当完成。全局文档角色和完成标记见 [../DOCUMENTATION_STATUS.md](../DOCUMENTATION_STATUS.md)。

## 已完成或基本完成

| Area | Status | Evidence |
| --- | --- | --- |
| Swift 6 baseline | Done | `Package.swift` target 和 package language modes 已对齐 `.v6` |
| Swift Testing baseline | Done | `Tests/SparkleRecorderTests` 主要使用 `import Testing`, `@Test`, `#expect` |
| 录制边界拆分 | Mostly done | `RecordingEngineClient`, `LiveRecordingEngineClient`, `RawInputEvent`, `RecordingEventPipeline`, `RecordingSessionProcessor` |
| Event tap 启动反馈 | Done | `EventTapThread.startAndWait`, `RecordingEngineClient.start() -> Bool`, `Recorder.startRecording() -> Bool` |
| 高频录制缓冲 | Done | `RecordingEventBuffer`, `RecordingSessionProcessor`, `AsyncStream(bufferingNewest:)` |
| 播放普通 step 执行器 | Mostly done | `PlaybackStepExecutor` 和对应 Swift Testing |
| 播放失败证据纯值化 | Mostly done | `PlaybackFailureEvidence`, `PlaybackFailureEvidenceBuilder`, `PlaybackEvidenceClient`, `EvidenceClient.recordFailure` |
| SwiftUI selection 重算收敛 | Done | `ActionGroupSelectionSnapshot` 和 `ActionGroupProjectionTests` |

## 未完成且会阻塞编排层质量

| Gap | Why It Matters |
| --- | --- |
| Player 状态机未抽出 | `Player` 仍负责调度、OCR、窗口刷新、冲突监控、证据记录和 UI 发布 |
| Workflow reducer 未建立 | 还没有统一处理 tick、依赖、资源、完成、失败、取消的状态机 |
| ResourceArbiter 未建立 | 前台键鼠控制权还没有中心化 lease 和 panic release 机制 |
| AutomationTaskRun 未建立 | 同一个 `SavedMacro` 多次运行还没有独立 run instance |
| SchedulerClient 未建立 | 定时启动还没有变成 reducer action |
| ConditionEvaluator 未建立 | OCR 条件分支还没有抽象为可 mock 的条件判断 client |
| Persistence 未建立 | `automations.json` / workflow 包格式尚未定义 |
| FlowGraph/Resource Timeline 未建立 | UI 还没有编排入口和可视化状态投影 |

## 当前可进入下一阶段的依据

当前底座已经足够开始 Automation Core 设计，因为：

- 宏模板已有 `SavedMacro`。
- 播放结果已有 `RunReport` / `PlaybackFailureEvidence` 基础。
- 播放和录制核心行为已有若干 pure clients，可继续向 reducer 注入。
- Swift Testing 已能快速覆盖 pure value 和 fake client。

但不能直接做可视化 FlowGraph。必须先冻结 Core 合同，否则 UI、调度器、Player adapter、测试会各自发明状态。

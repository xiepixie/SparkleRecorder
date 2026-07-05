# Automation Engine Parallel Workstreams

本文件说明哪些任务可以并行、哪些必须串行。核心判断标准：是否依赖 Automation Core 合同。

## Phase 0: 不可并行的合同冻结

必须先完成：

- `AutomationWorkflow`
- `AutomationTask`
- `AutomationTaskRun`
- `AutomationDependency`
- `AutomationOutcome`
- `AutomationAction`
- `AutomationRunState`
- reducer 基本签名

完成后才能让不同模块并行开发。

## Phase 1: 可并行任务

| Workstream | Can Parallelize | Depends On | Output |
| --- | --- | --- | --- |
| Reducer/State Machine | Yes, after contract | Core contract | Pure state transition |
| ResourceArbiter | Yes | `ResourceRequirement`, `runID` | Lease client + panic release |
| PlayerClient | Yes | `AutomationOutcome`, `runID` | Mockable playback adapter |
| SchedulerClient | Yes | `AutomationAction.clockTick` | Tick/manual trigger adapter |
| Persistence | Yes | Codable workflow/run types | `automations.json` repository |
| SwiftUI FlowGraph/Timeline | Limited | Projection types from reducer | Read-only UI first |
| Swift Testing | Yes | Contract + reducer signature | Deterministic test suite |

## 不建议并行的工作

- FlowGraph 交互和 reducer 合同同时重写。
- OCR 条件识别和通用 `ConditionEvaluator` 同时深做。
- `.sparkrec_workflow` 包格式和 `automations.json` 同时做。
- Player 大重构和 AutomationEngine 第一版同时做。
- 真实 scheduler 与 reducer 测试同时跑真实时间。

## 推荐开发顺序

1. Core contract。
2. Reducer + Swift Testing。
3. ResourceArbiter mock/live skeleton。
4. PlayerClient mock/live skeleton。
5. SchedulerClient mock/manual trigger。
6. Persistence with `automations.json`。
7. Read-only UI projection。
8. FlowGraph edit interactions。
9. OCR condition evaluator。
10. Background scheduling and launch integration。

## 并行协作约束

- 所有模块只能通过 `AutomationAction` 改变 reducer state。
- UI 不直接调用 `Player`。
- Scheduler 不直接调用 `Player`。
- ResourceArbiter 不知道宏内容，只知道 run 和 resource。
- Persistence 不保存 volatile UI state。
- Tests 先验证 reducer，不依赖真实 time、mouse、keyboard、OCR。

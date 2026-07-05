# Automation Engine Workstream Files

本目录是三人并行开发的工作台。每个 owner 只在自己的文件里维护规划、接口请求、阶段风险和验收记录；跨 owner 的合同变更必须双向记录，避免“口头约定”漂走。

## Owner Map

| Owner | File | Primary Question |
| --- | --- | --- |
| A: Core/Reducer | [owner-a-core-reducer.md](owner-a-core-reducer.md) | 状态到底如何确定性变化？ |
| B: Adapters/Persistence | [owner-b-adapters-persistence.md](owner-b-adapters-persistence.md) | 真实世界如何被包装成 action 和持久化记录？ |
| C: UI/Performance | [owner-c-ui-performance.md](owner-c-ui-performance.md) | 用户如何直觉地看见、编辑和理解编排状态？ |

## Shared Rules

- 任何模块都不能绕过 `AutomationAction` 修改编排状态。
- `SavedMacro` 继续作为静态模板，运行态只进入 `AutomationTaskRun` / run history。
- Player、Scheduler、ResourceArbiter、Repository 只能作为 client 注入。
- UI 第一版只读 projection；拖拽编辑等交互必须等 reducer projection 稳定。
- 每个 owner 合并前要更新自己的 `Planning Log` 和 `Handoff Checklist`。

# Current Status

更新时间：2026-07-06

本文只记录下一阶段 Workflow 页面的真实状态。已经有代码和测试的底层能力可以称为 first pass，但用户不可用的页面不能称为完成。

## 已经可以作为输入的底座

| Area | Status | Notes |
| --- | --- | --- |
| 静态工作流模型 | First pass available | `AutomationWorkflow` 表示一个工作流图，和 `SavedMacro` 分离。 |
| 静态任务节点 | First pass available | `AutomationTask` 可以是 macro、condition、delay、notification。 |
| 运行实例 | First pass available | `AutomationTaskRun` 有独立 `runID`、`executionID`、时间、outcome、evidence metadata。 |
| 依赖边 | First pass available | `AutomationDependency` 支持 success/failure/timeout/cancel/condition 等触发。 |
| reducer/effect 边界 | First pass available | 所有运行刺激通过 `AutomationAction`，真实副作用通过 `AutomationEffect` 交给 runtime/adapter 边界。 |
| adapter/runtime 边界 | First pass available | Player、scheduler、condition、repository 已有 mockable client 和 runtime session。 |
| persistence | First pass available | `automations.json` 保存 workflows/run history，`.sparkrec_workflow` 保存静态 workflow package。 |
| projection/UI bridge | First pass available | UI 能读取 projection 并提交部分 reducer action。 |

## 当前不能按产品完成验收的缺口

| Gap | Owner | Why It Blocks Product UX |
| --- | --- | --- |
| Workflow 页面交互不可用 | UI | 用户无法稳定拖拽、拉线、编辑和理解运行状态。 |
| 重复调度只表达 anchor | Engine | 用户设定每天/每小时运行后，需要生成每一次独立 run，而不是只跑一次。 |
| 资源冲突缺少等待队列 | Engine | 前台键鼠只有一个，冲突任务应该等待并顺延，而不是直接失败。 |
| retry/timeout 没有完整运行语义 | Engine | 用户需要“等 120 秒还没出现就走失败分支/重试”，不能只保存字段。 |
| 条件合流只有隐式 all dependencies | Engine | 复杂分支需要 OR、first matched、all matched 等 join policy。 |
| 视觉条件不够 | Engine/UI | 实际自动化需要区域变化、图标出现/消失、像素变化，不只是 OCR 文本。 |
| AI 导入格式不稳定 | Engine | `.sparkrec_workflow` 是内部包，不适合让 AI 直接生成。 |
| 文档完成标记过度乐观 | Engine/UI | 旧 checklist 中部分 UI/package/picker 项已经标完成，但当前体验反馈显示不能作为真实完成态。 |

## 下一阶段目标

1. 冻结 Workflow 页面用户模型和 projection/action 合同。
2. 让 Engine owner 每完成一个能力，都产出 UI 可消费的 projection 字段、action、fixture 和测试证据。
3. UI owner 基于 fixture 和 live projection 并行重做页面，不在 SwiftUI 内实现状态机。
4. 建立 AI workflow draft schema，本阶段只交付 CLI validator/importer 作为 AI 可调用接口；MCP 暂缓，不和 CLI 并行开发。
5. 只在用户能完成核心链路后，才把 checklist 标为 done。

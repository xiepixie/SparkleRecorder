# Workflow Page Productization

本目录是 AutomationEngine 下一阶段的产品化工作台，目标是把已有的后端编排底座变成用户真正能理解、能拖、能连、能运行、能排查的 Workflow 页面。

旧的 [../automation-engine/](../automation-engine/) 继续作为底层引擎、reducer、adapter、persistence 和历史三 owner 合同的源头。本目录只负责下一阶段的页面设定、两人协作、AI 接口和验收。

## 当前判断

- 后端底座比前端成熟：`AutomationWorkflow` / `AutomationTask` / `AutomationTaskRun` / `AutomationDependency` 的方向正确。
- 前端页面当前不能按“可用产品”验收：拖拽、拉线、编辑反馈、资源时间轴、条件表达和错误解释都需要重新以用户流程为中心设计。
- Workflow 页面必须按 Pro 级 macOS 原生生产力工具验收：普通控件克制，用户数据和运行状态优先，避免 Web dashboard / Bootstrap 式高饱和全宽按钮。
- 主交互必须从 Macro Library source bin 拖入 graph/list、直接连线和可视化分支开始；按钮和右侧 Inspector 只是辅助路径。
- 后端仍有关键语义缺口：重复调度、资源等待队列、retry/timeout watchdog、OR/merge join、视觉条件扩展、AI 可导入草稿合同。
- 下一阶段必须前后端并行，但并行前要冻结一份页面合同：UI 展示什么 projection，提交什么 action，后端完成什么字段后如何通知前端。

## 本轮产品定调

SparkleRecorder 的 App 定位是 Pro 级 macOS 原生生产力工具，审查口径应接近 Xcode、Final Cut Pro 这类长时间工作的专业软件，而不是 Web dashboard。Workflow 页面在静止态应该让 UI 隐身：普通按钮、工具条和列表操作退到背景里，用户的自动化数据、依赖线、条件分支、资源时间轴和运行证据成为主视觉。

这带来三条硬约束：

- 不再把普通 `.controlSurface` 全宽强背景当默认按钮语言。高饱和大色块只允许服务短暂语义状态，例如 drop target、危险确认、选中、失败/超时或 live-running。
- Workflow 的主路径是所见即所得拖拽编排：从 Macro Library 拖出 `SavedMacro` 到中心画布或列表，生成独立 `AutomationTask`；直接通过节点连接点建立依赖；Inspector 只做精修和可访问性兜底。
- 工作流运行时必须“活起来”：当前 task、触发边、等待资源/条件、失败证据入口要在 graph、timeline、inspector 中同步反馈，用呼吸细描边、hairline progress、状态点和克制动画表达，不用整卡发光或整块填色。

## 阅读顺序

1. [00-current-status.md](00-current-status.md)
   当前真实状态、不能再标成 done 的缺口。
2. [01-page-model-and-user-flow.md](01-page-model-and-user-flow.md)
   Workflow 页面到底是什么，用户怎么从简单宏拼成复杂自动化。
3. [06-workflow-visual-ux-contract.md](06-workflow-visual-ux-contract.md)
   Pro 级 macOS 原生工具的视觉与交互合同：克制 UI、拖拽编排、依赖图和运行反馈。
4. [02-backend-frontend-contract.md](02-backend-frontend-contract.md)
   Engine owner 如何把能力交付给 UI owner，双方如何写接口请求和验收证据。
5. [03-ai-interface-mcp-cli.md](03-ai-interface-mcp-cli.md)
   AI 生成工作流时的接口选择。本阶段只做一个接口：CLI-first，MCP 暂缓。
6. [05-cli-product-contract.md](05-cli-product-contract.md)
   CLI 作为用户和 AI 共同操作 workflow 的产品合同。
7. [04-parallel-delivery-plan.md](04-parallel-delivery-plan.md)
   两人并行任务、阻塞关系和阶段节奏。
8. [product-evidence/README.md](product-evidence/README.md)
   idle、drag-link、task-reorder、running 以及 future drill-in 截图/录屏验收 artifact 的收集规则。
9. [acceptance-checklist.md](acceptance-checklist.md)
   下一阶段验收清单。未被代码、测试和体验同时证明的项不能打勾。
10. [08-current-architecture-and-future.md](08-current-architecture-and-future.md)
   当前暂停快照：整体架构、后端逻辑、文件结构、已完成边界和未来设计。
11. [07-owner2-current-state-and-future.md](07-owner2-current-state-and-future.md)
    Owner 2 前端暂停交接快照：Workflow UI 架构、前端逻辑、文件结构、first-pass 边界、产品债和后续设计构想。
12. Owner 工作文件：
   - [workstreams/engine-runtime-ai.md](workstreams/engine-runtime-ai.md)
   - [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md)

## 非目标

- 本目录不重构 Player 或 Recorder。
- 本目录不替代 `automation-engine/` 的底层合同。
- 本目录不把当前 FlowGraph UI 描述成完成态。
- 本目录不让 AI 直接写内部 Swift Codable JSON。

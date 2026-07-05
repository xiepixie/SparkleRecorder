# Workflow Page Productization

本目录是 AutomationEngine 下一阶段的产品化工作台，目标是把已有的后端编排底座变成用户真正能理解、能拖、能连、能运行、能排查的 Workflow 页面。

旧的 [../automation-engine/](../automation-engine/) 继续作为底层引擎、reducer、adapter、persistence 和历史三 owner 合同的源头。本目录只负责下一阶段的页面设定、两人协作、AI 接口和验收。

## 当前判断

- 后端底座比前端成熟：`AutomationWorkflow` / `AutomationTask` / `AutomationTaskRun` / `AutomationDependency` 的方向正确。
- 前端页面当前不能按“可用产品”验收：拖拽、拉线、编辑反馈、资源时间轴、条件表达和错误解释都需要重新以用户流程为中心设计。
- 后端仍有关键语义缺口：重复调度、资源等待队列、retry/timeout watchdog、OR/merge join、视觉条件扩展、AI 可导入草稿合同。
- 下一阶段必须前后端并行，但并行前要冻结一份页面合同：UI 展示什么 projection，提交什么 action，后端完成什么字段后如何通知前端。

## 阅读顺序

1. [00-current-status.md](00-current-status.md)
   当前真实状态、不能再标成 done 的缺口。
2. [01-page-model-and-user-flow.md](01-page-model-and-user-flow.md)
   Workflow 页面到底是什么，用户怎么从简单宏拼成复杂自动化。
3. [02-backend-frontend-contract.md](02-backend-frontend-contract.md)
   Engine owner 如何把能力交付给 UI owner，双方如何写接口请求和验收证据。
4. [03-ai-interface-mcp-cli.md](03-ai-interface-mcp-cli.md)
   AI 生成工作流时的接口选择。本阶段只做一个接口：CLI-first，MCP 暂缓。
5. [05-cli-product-contract.md](05-cli-product-contract.md)
   CLI 作为用户和 AI 共同操作 workflow 的产品合同。
6. [04-parallel-delivery-plan.md](04-parallel-delivery-plan.md)
   两人并行任务、阻塞关系和阶段节奏。
7. [acceptance-checklist.md](acceptance-checklist.md)
   下一阶段验收清单。未被代码、测试和体验同时证明的项不能打勾。
8. Owner 工作文件：
   - [workstreams/engine-runtime-ai.md](workstreams/engine-runtime-ai.md)
   - [workstreams/product-ui-ux.md](workstreams/product-ui-ux.md)

## 非目标

- 本目录不重构 Player 或 Recorder。
- 本目录不替代 `automation-engine/` 的底层合同。
- 本目录不把当前 FlowGraph UI 描述成完成态。
- 本目录不让 AI 直接写内部 Swift Codable JSON。

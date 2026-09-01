# Scheduler, Run, and Evidence UX

Updated: 2026-08-25

本目录记录 Workflow 从“能力存在”走向“用户可以顺畅完成任务”的专项审计与完整 UX 改造方案。范围覆盖：

> 创建与设定 → 启用前检查 → 定时触发 → 运行反馈 → 失败解释 → 证据查看 → 修复与重试

## 结论

当前产品已经有 schedule、reducer、runtime、run history、branch/condition/playback evidence 的 first pass，但体验按组件和技术概念组织。用户需要先理解 task、schedule、graph、resource、run、manifest 等内部模型，才能完成一个普通定时任务并解释失败。

目标不是增加一个“大而全”的向导，也不是隐藏专业能力，而是建立两层体验：

- **快速路径**：普通用户可在一个连续流程内设定常见计划、完成检查、启用并确认下一次运行。
- **专业路径**：高级用户仍可编辑 task 级 schedule、依赖、资源、条件和证据细节，并能从摘要逐层钻取。

## 文档导航

1. [00-current-state-audit.md](00-current-state-audit.md)：基于当前代码和文档的能力盘点、用户旅程和摩擦点。
2. [01-target-experience.md](01-target-experience.md)：目标信息架构、关键流程和交互规则。
3. [02-contract-and-delivery-plan.md](02-contract-and-delivery-plan.md)：需要冻结的 projection/intent 合同、owner 边界、分阶段实施方案。
4. [acceptance-checklist.md](acceptance-checklist.md)：可验证的体验、无障碍、测试和产品证据门槛。

## 设计原则

1. 用户先看到“什么时候运行、现在是否可靠、最近发生了什么”，再看到引擎术语。
2. 创建时采用渐进披露；诊断时采用摘要先行、证据逐层展开。
3. 每个状态都必须回答“发生了什么、为什么、我能做什么”。
4. schedule 仍属于 task；V1 的工作流级设置只是安全的编辑入口和摘要，不偷偷改变 core 语义。
5. UI 只渲染 projection、提交 intent/action；不从 View 直接访问 scheduler、repository、Player 或证据文件。
6. 不把 OS 后台唤醒描述为已支持；在实现前必须明确提示“App 需要保持运行”。

## 本轮交付边界

本轮只完成审计与方案冻结，不声称 UI、runtime 或持久化已经改造。所有实现项在验收清单中保持未勾选，后续应按阶段用代码、测试和产品证据关闭。

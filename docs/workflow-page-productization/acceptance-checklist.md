# Acceptance Checklist

未被代码、测试、文档和产品体验共同证明的项不能打勾。first pass 可以写在状态栏，不能冒充 done。

## Contract

- [x] 新阶段文档目录存在，并说明和 `automation-engine/` 的关系。
- [ ] Page model 被 Engine/UI 两个 owner 接受。
- [ ] AI draft schema 被 Engine/UI 两个 owner 接受。
- [ ] Backend Capability Notice 模板开始被使用。
- [ ] 旧 checklist 中和当前体验不符的完成项被降级或标注为 first pass。

## Owner 1: Engine / Runtime / AI CLI

- [ ] Repeating schedule 能生成独立 future runs。
- [ ] Resource waiting state 能被 reducer 表达并被 release 唤醒。
- [ ] Timeout watchdog 终态释放资源并触发 timeout branch。
- [ ] Retry policy 会创建下一 attempt，并保留 execution/run history。
- [ ] Join policy 支持 `all` / `any` / `firstMatched`。
- [ ] Visual condition spec 进入 core contract。
- [ ] Projection 提供 UI 所需状态，不让 SwiftUI 重新推导。

- [ ] Scheduler adapter 支持 occurrence generation 或可靠 tick handoff。
- [ ] Resource arbiter/runner 支持等待队列，不把 busy 直接当失败。
- [ ] Condition evaluator 支持 OCR 文本以外的首批视觉条件。
- [ ] CLI `workflow macros --json` 存在并返回 AI 可用宏目录。
- [ ] CLI `workflow draft task/dependency/condition set` 能逐步编辑草稿。
- [ ] CLI `workflow draft validate` 存在。
- [ ] CLI `workflow draft simulate` 存在。
- [ ] CLI `workflow import --dry-run` 存在。
- [ ] CLI `workflow import --confirm` 走 reducer/repository 合同。
- [ ] 本阶段没有并行开发 MCP server；MCP 只保留为后续包装选项。

## Owner 2: Product UI / UX

- [ ] Workflow 页面能用 fixture 完成创建、拖拽、连线、编辑、删除。
- [ ] Macro Library 能拖拽宏到画布或列表生成 task。
- [ ] 条件和依赖能通过箭头、缩进或 `If...Then...Else` 分组被直观看懂。
- [ ] 运行中的 task 有克制的实时反馈，不使用大面积高饱和底色。
- [ ] FlowGraph 拖拽稳定，不丢节点、不丢线、不需要刷新后才显示。
- [ ] 资源时间轴能解释 running/waiting/conflict/completed。
- [ ] Inspector 能编辑 schedule、timeout、retry、condition、dependency trigger。
- [ ] UI 不直接调用 Player、scheduler、repository、condition evaluator。
- [ ] 普通 Workflow 控件不使用 Web 风格高饱和全宽色块或无必要 `.controlSurface` 强调。
- [ ] 大量节点/连线下 Canvas 和 projection 渲染不卡顿。
- [ ] AI draft 导入前有 preview、validation warnings 和 macro resolution UI。

## Product Scenarios

- [ ] 串联两个宏并手动运行。
- [ ] 定时启动一个 workflow，并生成每次独立 run history。
- [ ] 两个前台输入任务冲突时，一个运行、一个等待，释放后继续。
- [ ] OCR 等待文本超时后走 timeout 分支。
- [ ] 区域变化或图标出现条件能触发下游。
- [ ] AI 根据宏库生成 draft，validate/simulate/import 后能在 UI 中运行。

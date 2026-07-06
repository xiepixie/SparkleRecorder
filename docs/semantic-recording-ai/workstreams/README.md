# Semantic Recording Workstreams

更新时间：2026-07-06
状态：并行协作入口

本目录存放 `08-parallel-workstreams.md` 拆出来的 owner 工作台。每个 workstream 文件记录自己的当前状态、接口请求、验收证据和实现日志；跨 owner 变更仍要同步回 `08-parallel-workstreams.md`、`06-current-work-and-next-tasks.md` 和 `acceptance-checklist.md`。

## Files

- [s0-workflow-evidence.md](s0-workflow-evidence.md)：S0 Workflow Evidence Closure，负责把现有 Workflow 证据闭环补到可被用户信任，并向 S1 提供 preview/ref 合同需求。
- [s1-contract-core.md](s1-contract-core.md)：S1 Contract And Core Schema，负责 semantic recording bundle、safe refs、timeline/events/suppression、S0 preview comparison 合同和 S2/S3/S4 fixture bundle。
- [s2-app-capture-visual-index.md](s2-app-capture-visual-index.md)：S2 App Capture And Visual Index，负责 live `.mov`、event-aligned keyframes、Vision/AX observations、suppression 和 bundle storage；当前 core session 与 app-edge ScreenCaptureKit/Vision/store/preflight skeleton first pass 已有，录制生命周期接线和产品证据未完成。

## Collaboration Rules

- 请求方先在自己的 workstream 写 `Interface Request`，再在受影响的合同文档里写完整需求。
- 接受方在自己的 workstream 写 accepted/deferred/rejected，不通过聊天记忆当合同。
- 能被打勾的条目必须有证据：代码/测试、真实产品截图或录屏、fixture sidecar，或者明确的 accepted contract note。
- S0 不定义 semantic bundle schema；S0 只定义当前 Workflow 证据 UI 需要 S1 暴露哪些稳定 refs、fields 和 comparison payload。
- 当任务看起来要提前进入 MCP、App Knowledge、全自动 AI agent 或全局视觉资产库时，先回到 [../10-next-stage-reality-check.md](../10-next-stage-reality-check.md) 做用户价值和过度设计检查，再写 owner workstream。

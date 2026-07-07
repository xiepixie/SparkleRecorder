# Semantic Recording Workstreams

更新时间：2026-07-06
状态：并行协作入口；S3 first-pass paused while S2 live bundle evidence is the next unblocker

本目录存放 `08-parallel-workstreams.md` 拆出来的 owner 工作台。每个 workstream 文件记录自己的当前状态、接口请求、验收证据和实现日志；跨 owner 变更仍要同步回 `08-parallel-workstreams.md`、`06-current-work-and-next-tasks.md` 和 `acceptance-checklist.md`。

## Files

- [s0-workflow-evidence.md](s0-workflow-evidence.md)：S0 Workflow Evidence Closure，负责把现有 Workflow 证据闭环补到可被用户信任，并向 S1 提供 preview/ref 合同需求。
- [s1-contract-core.md](s1-contract-core.md)：S1 Contract And Core Schema，负责 semantic recording bundle、safe refs、timeline/events/suppression、S0 preview comparison 合同和 S2/S3/S4 fixture bundle。
- [s2-app-capture-visual-index.md](s2-app-capture-visual-index.md)：S2 App Capture And Visual Index，负责 live `.mov`、event-aligned keyframes、Vision/AX observations、suppression 和 bundle storage；当前 core session、app-edge ScreenCaptureKit/Vision/store/preflight skeleton、experimental Recorder bridge、Settings preflight panel、live suppression context ingestion、Secure Input diagnostics、capture-level suppression、AI-safe semantic/OCR text redaction、playback-preserving playable macro save/export/status sanitization、pure frame/video redaction planning、app-edge redacted frame PNG writing hook、app-edge redacted `.mov` renderer/store hook、live finish redaction application、Review/CLI redacted-frame preference、retention settings/manual cleanup/scheduled cleanup first pass、pure retention confirmation projection、macro metadata link 和 cancel/failure cleanup first pass 已有，live 产品证据、默认 rollout、redacted frame/video 产品证据、reviewed text-anchor mutation 和 live cleanup product evidence 未完成。
- [s3-review-ux-evidence-editing.md](s3-review-ux-evidence-editing.md)：S3 Review UX And Evidence Editing，负责 fixture-first Review timeline、event -> before/after frame navigation、overlays、source/runtime comparison、frame-to-condition candidates 和 suggestion review；当前 first pass 已暂告一段落，已有 core projection、interactive SwiftUI review、Run Detail Macro Review entry、live bundle presenter、frame region selection、frame-to-condition draft patch、Draft Preview handoff、package-local Review asset materialization、Run Target provenance 和 pixel color picking。下一步不继续扩 S3 UI；等待 S2 live bundle / ordinary Recorder bridge 产品证据后，再补 installed-app linked Review、frame-to-condition live clip 和 Review -> Draft Preview live evidence。
- [s4-cli-ai-app-knowledge.md](s4-cli-ai-app-knowledge.md)：S4 CLI AI And App Knowledge，负责 fixture-first `recording` CLI、evidence query、suggestion、draft-from-recording 和 later App Knowledge；fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording` 以及 explicit stored-bundle/default-root read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search`、explicit-source frame-region asset extraction 已实现，product-ready live catalog、stored suggestion synthesis、image-byte visual similarity、product-ready stored/live draft-from-recording 和 App Knowledge 仍 open。

## Collaboration Rules

- 请求方先在自己的 workstream 写 `Interface Request`，再在受影响的合同文档里写完整需求。
- 接受方在自己的 workstream 写 accepted/deferred/rejected，不通过聊天记忆当合同。
- 能被打勾的条目必须有证据：代码/测试、真实产品截图或录屏、fixture sidecar，或者明确的 accepted contract note。
- S0 不定义 semantic bundle schema；S0 只定义当前 Workflow 证据 UI 需要 S1 暴露哪些稳定 refs、fields 和 comparison payload。
- 当任务看起来要提前进入 MCP、App Knowledge、全自动 AI agent 或全局视觉资产库时，先回到 [../10-next-stage-reality-check.md](../10-next-stage-reality-check.md) 做用户价值和过度设计检查，再写 owner workstream。
- S4 的任何 CLI 输出必须引用 S1 evidence refs，并和 S3 Review 的接受/拒绝语义保持一致；MCP 只能在 CLI/shared service 稳定后包装同一套逻辑。
- S3 first pass 暂停期间，新增能力优先落到 S2 live bundle 生产和证据捕获；如果要恢复 S3 或 S4 product-ready live work，先对照 [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md) 确认 live input、root policy 和验收证据是否已经存在。
- S2 live evidence capture 使用 [../15-s2-live-evidence-playbook.md](../15-s2-live-evidence-playbook.md)；该文档只定义操作路径和 handoff 包，不把 debug-smoke、blocked preflight、synthetic rehearsal 或 explicit temp bundle 自动视为 product-ready。

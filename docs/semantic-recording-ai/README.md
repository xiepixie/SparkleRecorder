# Semantic Recording And AI Roadmap

更新时间：2026-07-06
状态：主动规划文档
Owner：Recording / Vision / Workflow AI shared planning

本目录记录 SparkleRecorder 下一阶段的语义录制愿景：录制一次，不只得到可回放的鼠标键盘宏，也得到可解释的视频母带、关键帧、OCR/视觉索引、窗口上下文、用户意图和 AI 可消费的 workflow draft evidence。

这不是当前已实现能力说明。当前已实现的是 `RecordingEngineClient` / `RawInputEvent` / `RecordingEventPipeline` / `RecordingSessionProcessor` 的低层录制拆分，以及 Workflow visual condition、AI Draft Preview、CLI-first workflow draft 的 first pass。本文定义的是如何把视频、视觉理解和 AI 接口吸收进现有架构。

## Product North Star

SparkleRecorder 不只是录制一串 `CGEvent`。它应该把用户的一次真实操作沉淀成一个可执行、可解释、可演化的自动化资产：

- `RecordedEvent` 负责高保真回放。
- 视频母带和关键帧负责记录当时真实上下文。
- OCR、图像、像素、AX/window metadata 负责把画面变成可检索的语义证据。
- AI 通过 CLI 查询本地索引、解释宏、修正等待和定位、生成 `sparkle.workflow.draft.v1`。
- Workflow UI 让用户审阅 AI 提议，而不是让 AI 直接写内部 Swift Codable JSON 或直接运行未知动作。

目标不是复制 OpenAI Record & Replay，而是吸收它的 demo-to-skill 思想，再叠加 SparkleRecorder 自己的本地视频证据、精确回放、视觉条件和 workflow 编排能力。

## Research Inputs

本规划参考了两类资料：

- OpenAI Record & Replay / Skills 的产品方向：用户演示 workflow，Codex 观察 actions 和 window content，录制后生成 reusable skill。
- 本地调研的 Linux Record & Replay 参考实现：它把一次演示保存为 bundle，包含 `manifest.json`、`timeline.jsonl`、`events.jsonl`、`suppressed.jsonl`、screenshots、accessibility snapshots、browser traces、speech/audio context、desktop snapshots、OCR evidence、Skysight rolling summaries 和 skill draft prompt。

从参考实现里得到的关键启发：

- 录制不是单一路径，而是多 provider evidence bundle。
- `timeline.jsonl` 是内部全量事实，`events.jsonl` 是 AI-safe 事件流，`suppressed.jsonl` 记录被隐私或能力边界挡下的内容。
- Replay 不应该以 raw coordinate macro 作为 AI 主架构；AI 应产出 skill/draft/semantic plan，由本地工具和用户审核落地。
- Skysight/Chronicle 类能力的价值在于周期性截屏、窗口/AX/OCR 证据和滚动摘要，而不是把完整视频每次丢给模型。

## Record & Replay Capability Mapping

SparkleRecorder 不应把 OpenAI 官方 Record & Replay 插件作为产品内依赖。官方插件是 Codex app 的插件和 MCP 能力；SparkleRecorder 应实现同类产品能力的本地版本，并让 CLI/未来 MCP 暴露稳定接口。

| Record & Replay Capability | SparkleRecorder Target |
| --- | --- |
| 用户演示一次 workflow | 用户录制一次 macro / app task，并保存 playable events + video evidence |
| 捕获 window content 和 actions | 捕获 `RecordedEvent`、视频/keyframes、AX/window metadata、OCR、visual index |
| 录制后生成 reusable skill | 录制后生成 macro explanation、cleanup suggestions、visual assets、`sparkle.workflow.draft.v1` |
| AI 通过 skill 复现任务 | AI 通过 CLI 查询本地索引，组合已有宏和 workflow draft，不重复消耗完整视频 token |
| 事件流作为主证据 | `timeline.jsonl` / `events.jsonl` / `suppressed.jsonl` 作为 recording bundle 证据层 |
| Computer Use 执行不稳定 UI | SparkleRecorder 优先使用本地 playback/locator/condition/runtime，必要时未来再包装 MCP |

因此，“包含 Record & Replay 能力”在 SparkleRecorder 里应理解为：内建 demo-to-automation compiler，而不是嵌入官方插件。

## Document Map

- [00-current-status.md](00-current-status.md)：当前项目能力、缺口和设计边界。
- [01-video-recording-bundle.md](01-video-recording-bundle.md)：录制视频母带、关键帧、证据包和隐私闸门。
- [02-visual-understanding-and-patterns.md](02-visual-understanding-and-patterns.md)：OCR、文字定位、pattern/image matching、像素、Vision 能力和补充技术。
- [03-cli-ai-contract.md](03-cli-ai-contract.md)：先做 CLI 的 AI 接口，MCP 暂缓；定义 AI 能查询和生成什么。
- [04-ux-application-knowledge.md](04-ux-application-knowledge.md)：用户使用场景、宏编辑 UX、应用知识库、同应用宏组织和自然语言生成宏。
- [05-workflow-continuation-and-direction-review.md](05-workflow-continuation-and-direction-review.md)：方向评审、当前 Workflow 剩余缺口承接、用户行为逻辑、可行性和过度设计风险。
- [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)：当前工作状态、剩余任务账本、立即可执行顺序和过度设计审计。
- [07-apple-api-implementation-path.md](07-apple-api-implementation-path.md)：2026 Apple API 可行性调研、macOS 15+ ScreenCaptureKit/Vision/AX 路线和 `SCRecordingOutput` 默认视频路径。
- [08-parallel-workstreams.md](08-parallel-workstreams.md)：下一阶段并行工作人物、Owner 范围、交付物和跨线接口规则。
- [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md)：S0 提给 S1 的 template/baseline source-frame/runtime-sample preview refs 合同；S1 已接受 first-pass core contract。
- [10-next-stage-reality-check.md](10-next-stage-reality-check.md)：下一阶段现实校准；按用户行为逻辑整理剩余任务、过度设计风险、可行性和可维护性规则。
- [11-user-logic-roadmap-and-scope-audit.md](11-user-logic-roadmap-and-scope-audit.md)：从用户行为、剩余任务、过度设计和可维护性角度重新审查下一阶段；明确 action vocabulary、P0-P4 顺序、CLI-first/MCP-deferred 和 App Knowledge later。
- [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)：当前方向控制台；把剩余任务、用户路径、过度设计裁剪、P0-P4 队列和“做/不做”决策收敛到一页。
- [13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md)：本轮方向纠偏记录；把当前方向是否正确、用户行为逻辑、剩余 Slice A-E、过度设计边界和工作状态维护成可继续执行的决策记录。
- [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)：S3 first pass 暂告一段落后的 S0-S4 最终差距对齐和 UI owner 聚焦说明；明确 S0 strict gate 已闭合、S1 合同 first pass 已完成、S2 是当前 live bundle/product evidence unblocker、S3/S4 暂停等待 live evidence 解锁，并把后续 UI/UX 打磨收敛到 evidence-first、mutation-boundary-visible 和 Review/Teach 用户路径。
- [15-s2-live-evidence-playbook.md](15-s2-live-evidence-playbook.md)：S2 live evidence capture playbook；把授权 macOS 15+ preflight、debug-smoke、ordinary Recorder bridge、安全/cleanup、S3/S4 handoff 和 checklist 更新规则写成可执行闭环，但不把任何 live gate 自动标完成。
- [16-visual-repeat-until-design.md](16-visual-repeat-until-design.md)：视觉 Repeat-Until 设计对齐；明确首版 live 图像源必须是 ScreenCaptureKit `SCStreamOutput` / `CMSampleBuffer`，OCR 只负责文字，图标/pattern/区域变化/像素走 visual detector，Repeat-Until 采用 Workflow 画布里的结构化 loop node 而不是任意 dependency cycle。
- [live-evidence/README.md](live-evidence/README.md)：未来 S2/S3/S4 live evidence 的收件目录规则；固定 sidecar/clip/bundle 命名、隐私注意事项、accepted/non-accepted evidence 和 gate mapping，本身不关闭任何 live gate。
- [workstreams/](workstreams/README.md)：S0/S1/S2/S3/S4 owner 工作台；当前已建立 S0 Workflow Evidence Closure、S1 Contract/Core、S2 App Capture/Visual Index、S3 Review UX 和 S4 CLI/AI/App Knowledge 文件。S1 提供 `SemanticRecordingFixture.checkoutBundle()` 给 S2/S3/S4 原型复用，S2 core session、app-edge ScreenCaptureKit/Vision/store/preflight skeleton、experimental Recorder bridge、macro metadata link、Settings preflight panel、live suppression context ingestion、Secure Input diagnostics、capture-level suppression、AI-safe semantic/OCR text redaction、playback-preserving playable macro save/export/status sanitization、pure frame/video redaction planning、app-edge redacted frame PNG writing hook、app-edge redacted `.mov` renderer/store hook、live finish redaction application、sidecar-aware bundle loading/catalog、default root、Review/CLI redacted-frame preference、retention settings/manual cleanup/scheduled cleanup first pass、pure retention confirmation projection 和 cancel/failure cleanup first pass 已有但 live `.mov` 产品证据、默认 rollout、redacted frame/video 产品证据、reviewed text-anchor mutation 和 live cleanup product evidence 未完成，S3 Macro Review / Run Detail entry、live bundle presenter、frame region selection、frame-to-condition draft patch、Draft Preview handoff 和 pixel color picking first pass 已有但自动 run->bundle 绑定、package materialization 与 live 产品证据未完成，S4 fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording`、explicit stored-bundle/default-root read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search` 和 explicit-source frame-region asset extraction 已实现，但 product-ready live catalog、stored suggestion synthesis、image-byte visual similarity、product-ready stored/live draft-from-recording 和 App Knowledge 仍未实现。
- [acceptance-checklist.md](acceptance-checklist.md)：验收边界和后续切片。

## Current Workflow Bridge

当前 Workflow 页面已经有 source bin、FlowGraph、runtime projection、AI Draft Preview、visual condition authoring、run evidence 和 product-evidence fixture first pass。真实 task reorder live clip、branch consistency live clip、visual diagnostics Open/Reveal live clip 和 macro evidence Open/Reveal live clip 已经补齐；它接下来仍有一个 S3 Review UI 缺口：

- S0 strict live evidence gate 已由 `workflow product-evidence audit --require-live --json` 验证为 13/13。
- branch consistency strict gate 已由 App-host handoff run payload 与 live App window capture 关闭；更完整的手动 Run Detail drill-in 录屏可作为后续补充。
- template/baseline preview refs 已有 S1 core contract 和 S0 fixture artifact；真实 Review UI 还需要把同样的 source-frame、runtime sample、score/diff 接入用户流程。

这些缺口不应通过继续堆普通按钮解决。它们正好说明下一阶段需要 semantic recording：录制时留下 frame、OCR、visual asset、surface 和用户意图证据，运行失败时能对照 baseline/sample，AI 生成 draft 时能引用本地证据而不是猜测。

下一阶段优先级是：在 S0 strict evidence gate 已关闭、S1 合同 first pass 已完成、S3 first pass 暂告一段落、S4 fixture OCR/visual/suggestion CLI 和 explicit/default-root read-only CLI 已完成的基础上，先推进 S2 live semantic bundle 和 recording-start guidance/product evidence，再让 S3 用真实 bundle 补 installed-app Review -> Draft Preview 证据，最后再打开 S4 product-ready live catalog/search/suggestion。不要先做大型 App Knowledge 或 MCP。

当前执行账本维护在 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)，并行 owner 边界维护在 [08-parallel-workstreams.md](08-parallel-workstreams.md)，方向现实校准维护在 [10-next-stage-reality-check.md](10-next-stage-reality-check.md)，用户逻辑与剩余任务审计维护在 [11-user-logic-roadmap-and-scope-audit.md](11-user-logic-roadmap-and-scope-audit.md)。下一阶段开工前先读 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)、[13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md) 和 [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)：前者是一页式控制台，中间是本轮方向纠偏和剩余 Slice A-E 的决策记录，后者是 S3 暂停后 S0-S4 product-ready 差距、验收姿态和 UI/UX owner 聚焦总表。S0-S4 具体工作台维护在 [workstreams/](workstreams/README.md)。任何把 Workflow evidence、semantic recording schema、Recording CLI 或 App Knowledge 状态向前推进的工作，都应该同步更新相关 workstream、执行账本和验收清单；不要把规划描述当成已完成实现。

## Relationship To Existing Docs

本目录连接但不替代以下现有文档：

- `docs/RecordingEngineRefactoringPlan.md`：低层录制和事件管线。
- `docs/VisionArchitecturePlan.md`：coordinate-first、vision-assisted 的定位策略。
- `docs/WindowBoundAutomationPlan.md`：窗口绑定、视觉定位、AX/CGEvent/AppleEvent 执行边界。
- `docs/workflow-page-productization/03-ai-interface-mcp-cli.md`：Workflow AI draft 的 CLI-first 原则。
- `docs/workflow-page-productization/08-current-architecture-and-future.md`：AutomationEngine 与 Workflow UI 当前 pause snapshot。

## Non-Goals

- 不把 AI 放到实时录制热路径里。
- 不让 AI 直接操作内部 `.sparkrec_workflow` 或 Swift Codable JSON。
- 不把完整视频作为每次 AI 请求的默认上下文。
- 不承诺完全后台、不可见窗口、跨 Space 的无焦点自动化。
- 不用视频语义替代可测试的 reducer、locator、condition evaluator 和 playback engine。
- 不让 semantic recording 发明一套与 Workflow `visualAssets` / artifact presenter 不兼容的 asset ref 系统。

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
- [acceptance-checklist.md](acceptance-checklist.md)：验收边界和后续切片。

## Current Workflow Bridge

当前 Workflow 页面已经有 source bin、FlowGraph、runtime projection、AI Draft Preview、visual condition authoring、run evidence 和 product-evidence fixture first pass。它接下来仍有三类真实产品验收缺口：

- live visual diagnostics 的真实 capture / Open / Reveal 录屏。
- branch evidence drill-in 在真实 run 中和 FlowGraph edge、selected run、Run Detail 保持一致。
- template/baseline preview refs 从字符串引用升级成可审阅的缩略图、diff 或 source-frame 证据。

这些缺口不应通过继续堆普通按钮解决。它们正好说明下一阶段需要 semantic recording：录制时留下 frame、OCR、visual asset、surface 和用户意图证据，运行失败时能对照 baseline/sample，AI 生成 draft 时能引用本地证据而不是猜测。

下一阶段优先级是：先关掉 Workflow 产品证据缺口，再冻结最小 recording bundle 合同和 macOS 15+ Apple API 策略，然后做 frame-to-condition，而不是先做大型 App Knowledge 或 MCP。

当前执行账本维护在 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)，并行 owner 边界维护在 [08-parallel-workstreams.md](08-parallel-workstreams.md)。任何把 Workflow evidence、semantic recording schema、Recording CLI 或 App Knowledge 状态向前推进的工作，都应该同步更新该文件和验收清单；不要把规划描述当成已完成实现。

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

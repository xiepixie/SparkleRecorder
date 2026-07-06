# Current Status

更新时间：2026-07-06
状态：规划快照

## What Exists

Recording 已经有可继续扩展的底座：

- `EventTapThread` 将 `CGEventTap` 放到独立线程。
- `RecordingEngineClient.live(mask:)` 把 AppKit/CoreGraphics 事件桥接为 `AsyncStream<RawInputEvent>`。
- `RawInputEvent` 保留输入类型、时间戳、坐标、keyCode、flags、unicode、scroll sample。
- `RecordingEventPipeline` 负责 mouse move 过滤、ignored key、drag sampling、scroll payload、surface binding 和 `RecordedEvent` 生成。
- `RecordingSessionProcessor` 用锁保护 pipeline，并把输出存进 `RecordingEventBuffer`。
- `RecordedEvent` 已有 screen/window/content 坐标、surfaceId、scrollPayload、unicodeString、TextAnchor 等字段。
- `SemanticRecordingCaptureSession` / `SemanticRecordingCaptureClient` 已有 pure first pass，可用 fake movie/frame/index clients 生成 validating bundle、video segment、event-aligned keyframes、semantic events 和 observations。
- `LiveSemanticCaptureClient`、`ScreenCaptureKitMovieRecorder`、`ScreenCaptureKitFrameSource`、`RecordingBundleStore`、`VisionRecordingIndexer`、`SemanticRecordingPreflightClient.live` 已有 app-edge skeleton first pass，并通过 Swift 6 build。

Workflow / Vision / Evidence 侧也已有 first pass：

- `AutomationWorkflowDraft*` 支持 AI draft validate/simulate/import/edit/patch。
- `AutomationVisualCondition` 支持 image/baseline/pixel/regionChanged 等视觉条件模型。
- `LiveAutomationConditionEvaluatorClient` 和 `AutomationVisualConditionEvaluatorClient` 已可做 live visual/OCR condition first pass。
- `AutomationTaskRun.conditionEvidence` 和 `AutomationConditionEvidenceArtifactPresenter` 已形成 run evidence 的安全预览/open/reveal 边界。
- `AutomationConditionEvaluationEvidence.contextual` 已覆盖 `previousOutcome`、external signal、manual approval 这类非视觉条件的可解释 diagnostics。
- CLI-first AI 方向已经确定，MCP 暂缓。

## What Is Missing

当前还没有“语义录制资产”：

- 没有把 semantic capture 接入普通宏录制生命周期；当前 app-edge capture/store/indexer/preflight 只是 first pass skeleton。
- 没有把每个 `RecordedEvent` 和同一时间附近的帧、OCR、AX 元素、窗口元数据绑定。
- 没有可搜索的 visual index。
- 没有 recording bundle 层面的 `timeline.jsonl` / `events.jsonl` / `suppressed.jsonl` 分流。
- 没有从录制资产生成 workflow draft 的 CLI。
- 没有把录制帧一键转成 visual asset、baseline、template、pixel sample 或 OCR region 的产品流。
- 没有同应用宏集合的知识组织，用来让 AI 判断“已有宏是否足够组合出新任务”。

当前 Workflow 页面也暴露了 semantic recording 必须补上的产品缺口：

- visual diagnostics 目前已有 `AutomationTaskRun.conditionEvidence`、live sample artifact refs、安全 preview/open/reveal presenter、fixture 截图，以及 `live-visual-diagnostics-open-reveal.mov` / `.md` 证明 App-host OCR condition run payload 和真实 App Support artifact file actions。
- branch evidence 目前已有 durable `AutomationTaskRun.branchEvidence`、fixture drill-in，以及 `live-branch-evidence-consistency.mov` / `.md` 证明 App-host handoff run payload 中 source run、target run、dependency trigger 和 live App window capture 一致；更完整的手动 Run Detail drill-in 录屏可后续补充。
- template/baseline refs 目前能作为 visual condition / draft asset 字段流转；fixture 已能渲染 source/runtime/decision，仍缺真实 Review UI 中来自录制帧或运行样本的 thumbnail / diff / source-frame preview，让用户知道这个 ref 真实指向什么。
- Product evidence 已证明 UI 可读，但还没有把“录制时的基准画面”和“运行时看到的样本”连成一条用户能理解的证据链。

这些缺口说明 semantic recording 的第一价值不是生成更炫的 AI，而是把宏从坐标脚本升级成有来源、有证据、可修正、可组合的自动化资产。

当前剩余任务、优先级和过度设计审计维护在 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)、[10-next-stage-reality-check.md](10-next-stage-reality-check.md) 和 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)。本文件只记录快照，不单独作为执行队列。

## Target Architecture

目标是双轨录制：

```text
CGEventTap
  -> RawInputEvent
  -> RecordingEventPipeline
  -> RecordedEvent
  -> playable macro

ScreenCaptureKit / AX / Vision / Window metadata / User markers
  -> SemanticRecordingTimeline
  -> VisualIndex
  -> RecordingBundle
  -> AI CLI queries and workflow draft suggestions
```

低层事件轨保持快、稳、可测试。语义轨可以异步、降采样、可关闭，并且必须有隐私闸门。两条轨通过统一 `recordingTime` / `eventID` / `frameID` / `surfaceID` 关联。

## Layer Boundaries

Core target should own:

- recording bundle value model
- semantic timeline value model
- visual index metadata model
- AI-safe event payload schema
- draft-generation request/result types
- pure scoring and matching helpers

App target should own:

- ScreenCaptureKit video/keyframe capture
- AXUIElement snapshots
- Vision OCR and image requests
- file storage, privacy prompts, reveal/open/picker UI
- live adapters for recording session capture

SwiftUI should own:

- timeline/video review UI
- frame picker and region editor
- AI suggestion review
- intent marker and correction flows

SwiftUI should not do file IO, run Vision directly from view bodies, or infer workflow semantics by scanning raw run history.

## Design Principle

`RecordedEvent` remains the execution truth. Video and semantic evidence make the macro understandable, editable, optimizable and composable; they do not replace deterministic playback or reducer tests.

## Direction Guardrails

- 先服务录制后 review、失败后诊断、frame-to-condition、workflow draft 审阅，不先做大型 AI agent。
- 第一版按 macOS 15+ 设计，semantic recording 默认保存 `.mov` 视频母带和 event-aligned keyframes；keyframe-only 只作为轻量/隐私模式。
- AI 默认查询本地 summary、OCR、visual index 和 selected crop，不默认读取完整视频。
- Semantic recording 的 visual assets 必须能进入现有 `AutomationWorkflowDraftVisualAssets` / package provider / artifact presenter 边界。
- App Knowledge 先做轻量 app/surface/macro grouping；自然语言组合要等证据资产足够后再推进。
- 当前阶段已关掉 S0 Workflow strict live evidence gate，下一步扩展 `SemanticRecordingBundle` 的 live 产品路径；不要在真实 Review UI、frame-to-condition、S2 live `.mov`/keyframes 和 CLI suggestion 未可信前启动完整 MCP/App Knowledge 大路线。

# Workflow Continuation And Direction Review

更新时间：2026-07-06
状态：方向评审与承接任务
Owner：Workflow UI / Recording / Vision / AI shared planning

本文把 `workflow-page-productization/` 当前剩余验收缺口接到 semantic recording 路线图里。它不是替代 Workflow checkpoint，也不是宣布语义录制已经实现；它回答三个问题：

- 当前剩余任务应该放到下一阶段哪里。
- 从用户使用逻辑看，未来方向是否正确。
- 从工程角度看，哪些设计会过度、不可维护或不可落地。

## 1. Direction Judgment

当前方向总体正确，但必须保持一个边界：semantic recording 是证据层和教学层，不是新的执行真相。

正确的产品路线是：

```text
用户演示一次
  -> SparkleRecorder 保存可回放宏
  -> 同步保存视频/关键帧/OCR/视觉/窗口证据
  -> 用户在 Review 中修正意图和等待条件
  -> AI 基于本地证据提出 workflow draft
  -> 用户审阅、导入、运行
  -> run evidence 反哺诊断和下一轮改进
```

不正确的路线是：

```text
录一段视频
  -> 让 AI 猜整个 UI 和所有意图
  -> 直接生成可运行自动化
  -> 跳过用户审阅、跳过 reducer/locator/condition 测试
```

SparkleRecorder 的优势不是“让 AI 看视频后随便操作电脑”，而是把本地可验证的事件、帧、OCR、视觉资产、runtime evidence 和 workflow reducer 组合起来，让用户逐步把一次演示教成可靠自动化。

## 2. User Behavior Logic

用户真正的工作流不是“录制 -> 保存文件”这么短。更真实的路径是五段：

1. Capture：用户演示一次真实任务。此时用户的目标是快，不想配置条件、分支或变量。
2. Review And Teach：录制结束后，用户才有精力告诉系统哪些等待是有意的，哪些输入是变量，哪些点击应该绑定到文字、图像或区域。
3. Compose：用户或 AI 把多个已知宏、等待、通知、manual approval、external signal 组合成 workflow。
4. Run And Diagnose：运行失败时，用户需要知道系统看到了什么、为什么走这条分支、应该打开哪个证据。
5. Reuse：同一应用的宏、视觉锚点、变量和失败经验逐渐变成 app knowledge，下一次不需要重新录完整流程。

这说明当前 Workflow 剩余任务和 semantic recording 不是两条线。Workflow 的 branch evidence、visual diagnostics、template/baseline preview、Open/Reveal action，都应该成为未来 recording evidence 的用户语言。

## 3. Current Workflow Carryover Tasks

这些任务来自当前 Workflow checkpoint。它们应该先补齐，再进入更大的 semantic recording implementation。原因很简单：如果现有 run evidence 都不能被用户信任，录制语义层只会放大混乱。

| Task | Current State | Next Acceptance |
| --- | --- | --- |
| Live visual diagnostics Open/Reveal | Fixture UI 已证明 artifact preview、Open/Reveal affordance 和 inline feedback；live evaluator 可写 sample/crop refs | 用真实 App 运行一次 visual/OCR condition，录屏证明 Run Detail 显示 watched region、last sample/crop、score/threshold，并且 Open/Reveal 打开真实 App Support artifact |
| Branch evidence real-run consistency | `AutomationTaskRun.branchEvidence` durable payload 已有；fixture drill-in 已有 | 用真实 workflow 运行一次 success/failure/timeout branch，录屏证明 FlowGraph edge 状态、selected run、Run Detail branch evidence 三者一致 |
| Template/baseline preview refs | draft/package refs、provider、baseline capture、fixture last-sample/region artifact first pass 已有 | 定义 template/baseline preview artifact ref，Run Detail 同屏展示 recorded template/baseline、runtime sample、score/diff；没有 ref 时明确 fallback |
| Real drag/reorder WYSIWYG evidence | idle/drag-link/task-reorder/running fixture PNG 已有 | 录屏证明 macro drag, task reorder, connector link 的 preview 与真实 reducer mutation 一致 |
| Managed visual asset storage policy | package-root retention first pass，可解析 package-local refs | 决定哪些资产留在 package、哪些复制到 app-managed store、如何迁移/删除/恢复 missing asset |
| Evidence presenter consistency | Macro evidence 和 condition artifact presenter 都已有 Open/Reveal feedback first pass | 统一 action feedback 文案、missing/unreadable/unsafe path 状态、product evidence 录屏规则 |
| Resource/runtime product evidence | resource waiting/max wait/timeout/retry projection first pass 已有 | 补多 workflow resource queue、runtime health、handoff result readback 的产品证据，不在 UI 中重写调度语义 |

## 4. How This Connects To Semantic Recording

当前剩余缺口可以自然落到 semantic recording 的前三个能力上：

- Template/baseline preview refs 应该优先从 recorded frame extraction 里来，而不是先做一个孤立的全局视觉资产管理器。
- Live visual diagnostics 的 artifact viewer 应该复用 recording bundle 的 safe relative artifact ref 和 app-edge presenter 边界。
- Branch evidence drill-in 应该成为 future timeline 的一部分：用户能从 run branch decision 跳回当初录制/导入时的证据和目标条件。

因此，下一阶段不要把 semantic recording 做成大而全的“视频理解系统”。先做一条薄而真实的竖切：

1. 录制 playable macro 时保存 `.mov` 视频母带和 event-aligned keyframes。
2. Macro Review 能从某一帧框选 OCR region / image template / baseline / pixel sample。
3. 这些 visual assets 能进入现有 `AutomationWorkflowDraft` 和 visual condition。
4. 运行后 Run Detail 能对比 recorded asset 与 runtime sample。
5. CLI 只暴露 frame/ocr/asset/suggestion 的结构化查询，不发送完整视频。

## 5. What Is Overdesigned

以下能力不是错，但现在做会拖垮实现和维护：

- 默认录完整高帧率视频并对每帧跑 OCR/AX/视觉理解。先做关键帧和可开关 rich diagnostics。
- 一开始就构建“完整应用知识图谱”。先按 app bundle ID、surface、macro、visual asset 做轻量索引。
- 让 AI 直接生成最终可运行 workflow。AI 只生成 draft/suggestion，仍走 validate/simulate/dry-run/import。
- 独立实现 MCP、daemon、AI service、UI 语义引擎四套逻辑。先用 CLI/shared service，一套 JSON envelope。
- 为 template/baseline 做复杂全局资产库，再反过来接 recording。更稳的顺序是从 recorded frame extraction 和 package-local assets 开始。
- 在 SwiftUI 里做 OCR、文件 IO、path 拼接、DAG 推导或视觉匹配。SwiftUI 只渲染 projection 和 presenter result。
- 追求“AI 自动理解所有用户意图”。产品应鼓励用户在 Review 阶段轻量教学和确认。

## 6. Feasibility

这个方向可实现，因为现有底座已经覆盖关键边界：

- 可回放真相：`RecordedEvent`、recording pipeline、playback engine。
- Workflow 真相：`AutomationWorkflow`、`AutomationTask`、`AutomationTaskRun`、reducer/effect/runtime。
- AI draft 真相：`sparkle.workflow.draft.v1`、validate/simulate/dry-run/import。
- 视觉条件真相：OCR/visual condition、visual asset refs、package-root retention。
- 证据真相：run evidence presenter、condition artifact presenter、safe relative artifact paths。

需要新增的是 recording bundle/schema、event-frame alignment、keyframe extraction、visual observations、recording CLI 和 Review UI。它们应该接入现有边界，不应复制 workflow/reducer/runtime 语义。

## 7. Maintainability Rules

未来实现必须守住这些规则：

- `RecordedEvent` 是 execution truth；semantic evidence 是 explanation and authoring truth。
- Bundle schema 版本化，所有 artifact refs 使用相对路径和安全 resolver。
- App target 执行 ScreenCaptureKit、Vision、AX、file IO、NSWorkspace Open/Reveal。
- Core target 保存值类型、schema、pure projection、matching/scoring helper 和 mockable client contract。
- SwiftUI 不直接读 Application Support，不拼路径，不运行 Vision，不重算 workflow 语义。
- CLI 和 UI 消费同一套 service/result envelope，避免 AI 和用户看到两套事实。
- 每个 AI suggestion 必须带 evidence refs、confidence、risk、fallback 和 user-review state。
- 每个新增 capability 都要有 fixture、targeted tests、product evidence，才能从 first pass 升级。

## 8. Extensibility Direction

可扩展的设计不是把所有未来能力一次性做完，而是让每一层可替换：

| Layer | First Provider | Future Provider |
| --- | --- | --- |
| Keyframes | ScreenCaptureKit target window / display crop | richer video segments, app-specific capture policy |
| OCR | Apple Vision | OCR provider registry, language tuning |
| Template/baseline | CoreGraphics/CoreImage/vImage/Accelerate | feature print, OpenCV/custom matcher, model-assisted detector |
| AX/window context | AppKit + AX snapshots | app-specific semantic adapters |
| AI access | CLI JSON envelope | MCP wrapper over same service |
| App knowledge | local app/macro/asset index | cross-recording summaries and reusable skill draft prompts |

The extension point is provider/service boundary, not SwiftUI view logic.

## 9. Recommended Next Sequence

1. Submit the current Owner2 workflow checkpoint as a first-pass UI/evidence slice, with the live gaps clearly named.
2. Record product evidence for live visual diagnostics Open/Reveal using the installed App and real App Support artifacts.
3. Record product evidence for branch evidence real-run consistency across FlowGraph, selected run and Run Detail.
4. Define the minimal template/baseline preview artifact contract. Prefer recorded-frame and runtime-sample refs before designing a global asset library.
5. Add semantic recording Phase 0 schema: `SemanticRecordingBundle`, frame refs, visual observations, safe/AI-safe event streams, suppression policy.
6. Implement recording bundle v0 with `SCRecordingOutput` video plus event-aligned keyframes. Prove event-frame/video alignment with tests.
7. Build one Review flow: select recorded frame region -> create visual asset -> add OCR/visual condition draft -> validate/simulate/import.
8. Add recording CLI query commands only after bundle fixtures exist.
9. Add AI suggestions after local deterministic queries and UI review are stable.
10. Defer MCP, app knowledge graph, high-frame-rate video analytics, daemon polish and model-backed detectors until the thin vertical slice works.

## 10. Acceptance Rule

This direction is accepted only if the first vertical slice helps a user answer:

- What did I record?
- What was I waiting for?
- What should become a condition or visual asset?
- Why did the workflow choose this branch?
- What evidence should I inspect after failure?
- Can I reuse this recording in a new workflow without trusting AI blindly?

If a proposed feature cannot answer one of those questions, it is probably infrastructure polish or overdesign for this phase.

## 11. Maintenance Task List

当前维护顺序按“先证明现有 Workflow 可信，再扩展语义录制”推进：

详细执行账本维护在 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)。本节只保留路线级摘要；当任务状态、Owner 边界、验收证据或 overdesign 判断变化时，以 06 文件和 [acceptance-checklist.md](acceptance-checklist.md) 为准并同步回链。

1. Workflow evidence closure:
   - live visual diagnostics Open/Reveal recording
   - macro evidence Reveal Report / Open Screenshot recording
   - branch evidence real-run consistency recording
   - real drag/reorder or drag-link WYSIWYG recording
   - template/baseline preview refs design note
2. Semantic recording contract:
   - minimal `SemanticRecordingBundle` schema
   - video-plus-keyframe first slice
   - AI-safe event stream and suppression records
   - retention/deletion policy
   - frame-derived asset mapping into existing `AutomationWorkflowDraftVisualAssets`
3. Frame-to-condition vertical slice:
   - recorded frame review surface
   - OCR region from frame
   - image template from frame
   - baseline from frame
   - pixel sample from frame
   - evidence-backed suggestion review
4. CLI query slice:
   - `recording list/show`
   - `recording frames`
   - `recording events-near`
   - `recording ocr search`
   - `recording asset extract`
   - `recording suggest waits`

Checkpoint rule：如果一项工作不能改善“录完能看懂、失败能解释、修正有证据、组合前可审阅”，就不是下一阶段优先级。

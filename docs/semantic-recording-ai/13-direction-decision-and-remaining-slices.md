# Direction Decision And Remaining Slices

更新时间：2026-07-07
状态：方向纠偏记录与剩余任务切片
Owner：Semantic Recording program coordination

本文记录本轮对 `docs/semantic-recording-ai/` 的审阅结论。它不替代 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md) 或 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)，而是把“方向是否正确、还差什么、哪些是过度设计、下一步怎么切”固定成一份可继续维护的决策记录。

## 1. Verdict

当前方向总体正确，但必须继续收束。

SparkleRecorder 应该做的是：

```text
Record
  -> Review
  -> Teach waits / locators / visual state
  -> Draft
  -> Run
  -> Diagnose
  -> Reuse
```

不是：

```text
Record video
  -> send everything to AI
  -> AI guesses an automation
  -> AI runs it
```

真正有价值的路线是“证据驱动的自动化生产力工具”：`RecordedEvent` 继续是执行真相，semantic recording 负责把一次录制补上视频、关键帧、OCR、窗口/AX、suppression、source/runtime comparison 和 AI 可查询 evidence。AI 只能提出 suggestion 或 `sparkle.workflow.draft.v1`，用户必须能看到证据、验证、模拟、导入和拒绝。

## 2. User Logic That Should Drive The Design

用户不会先搭复杂状态机。用户通常先录制，然后才知道哪里需要教系统：

1. 先把真实操作录下来。
2. 停止后回看，解释哪里是等待、哪里是点击、哪里是误触。
3. 把 fragile coordinate 转成文本、图标、区域变化或像素状态。
4. 把可复用步骤组成 workflow。
5. 运行失败后查看系统当时看到了什么。
6. 同一应用积累几次后，再让 AI 复用已有证据。

典型场景：

```text
战斗完成
  -> 等待动画或结算稳定
  -> 点击任意位置唤出“离开”
  -> 等待“离开”文字出现
  -> 点击“离开”
  -> 等待主界面或再次战斗入口出现
```

这个场景暴露的产品要求：

- “等待文本”和“点击文本”不能被合并成普通连续点击。
- 点击后出现 UI 是一个独立意图，不能折叠成多点点击。
- 等待/验证类动作应该显示观察区域，不应该显示点击圆点或点击光圈。
- 用户需要“等待图标出现/消失”“等待画面变化”“等待颜色/像素状态”，而不是只能等待固定时间或固定文字。
- 失败时必须能对照 recorded baseline、runtime sample、score/diff、OCR 结果和 timeout/fallback 原因。

## 3. Current State Summary

当前 worktree 已经有足够底座，下一阶段不是推倒重来。

| Area | Current State | What It Means |
| --- | --- | --- |
| Recording boundary | `RawInputEvent`、`RecordingEventPipeline`、`RecordingSessionProcessor` 已把 CGEvent 边界和纯 pipeline 分开 | 录制底层可继续增量拆，不需要整体重写 |
| Workflow runtime | reducer、resource queue、retry、timeout、join、branch evidence、run history first pass 已有 | 可以承接复杂状态，不应该在 SwiftUI 里重写调度语义 |
| Product evidence gate | `workflow product-evidence audit` 严格校验 live artifacts；当前 strict audit 已达 13/13 | 证据门禁是正确约束，不能用 fixture 伪装完成；后续 UI 改动仍需重新跑 strict audit |
| Visual conditions | OCR/image/baseline/pixel/regionChanged first pass 已有 | 录制帧可以映射到现有 visual asset/condition 模型 |
| Semantic bundle | S1 bundle/schema/fixture first pass 已有 | S2/S3/S4 可以基于同一事实层并行 |
| S2 capture | fake capture session、preflight、suppression、Recorder bridge、redaction plan、redacted frame PNG writing hook、redacted `.mov` renderer/store hook、live finish redaction application 和 Review/CLI redacted-frame preference first pass 已有 | 下一步是 live `.mov`/keyframe product evidence 和 redacted frame/video product evidence，不是继续扩 schema |
| S3 Review | Review projection、Run Detail entry、frame region selection、Draft Preview handoff、package-local materialization、Run Target provenance、pixel picking first pass 已有 | S3 first pass 暂停；下一步等待 S2 live bundle + saved macro metadata 后再做 installed-app linked Review、frame-to-condition live evidence 和 Review -> Draft Preview live evidence |
| S4 CLI | fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording`、explicit stored-bundle/default-root read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search`、explicit-source frame-region asset extraction、low-token CLI transcript 和 suggestion-without-evidence low-confidence guard 已有 | Product-ready live catalog/search/suggestions、stored suggestion synthesis、image-byte visual similarity、product-ready stored/live draft-from-recording 暂停到 S2 live evidence 和 S3 Review boundary 稳定后；MCP 仍后置 |

## 4. Remaining Slices

### Slice A: Trust The Existing Workflow

目标：先让用户相信当前 Workflow 和 evidence UI。

必须完成：

- live visual diagnostics Open/Reveal：done for strict gate via `live-visual-diagnostics-open-reveal.mov` / `.md`。
- live macro evidence Open/Reveal：done for strict gate via `live-macro-evidence-open-reveal.mov` / `.md`。
- OCR/visual region picker：fixture evidence 已证明等待/验证显示 region box 和 label、点击/text-click 显示 circle/pulse；installed-app editor evidence 和完整 grouping proof 仍 open。
- action preview stability：新动作启用预览后立即有可见轨迹；拖动点位或路径控制点后轨迹不消失，箭头方向实时更新。
- action grouping rules：点击文字、普通点击、双击、多点点击必须按用户意图拆分，不能把有等待/画面变化的点击误合并。
- saved macro/library preview：重新打开软件后 library 中的 timeline/total duration/preview 必须能从持久化数据重建。

建议的点击合并规则先写成产品约束，后续再实现：

- 双击只用于同一目标附近的快速连续点击，默认间隔上限建议 `350 ms`。
- 多点点击只用于不同点位的快速 burst，单次间隔上限建议 `500 ms`，且整个 burst 不应跨越有意义等待、键盘输入、滚动稳定、视觉检测或窗口变化。
- 如果两个点击之间存在显式 wait、用户停顿、视觉状态变化、文本/图标检测、或目标语义不同，必须保留独立步骤。
- “点击后等待”应作为两个步骤显示：click action + wait/verify condition。

### Slice B: Make Review And Teach Real

目标：让用户录完后能把脆弱宏教成可靠宏。

必须完成：

- Run Detail 自动找到关联 live semantic bundle，不依赖 open panel；当前 macro-level `SavedMacro.semanticRecording` opener first pass 已有，installed-app live evidence 等 S2 ordinary Recorder bridge。
- event row 能跳到 before/after frame。
- frame region selection 能生成 OCR wait、image appeared/disappeared、region changed、pixel matched 的 draft patch。
- frame crop/package materialization：从录制帧裁出来的图片/baseline 必须复制成 workflow draft 可用的 safe refs；fixture/stored first pass 已有，live installed-app evidence 等 S2 live bundle。
- source/runtime comparison 在真实 Review 或 Run Detail 中同屏显示，而不只存在 fixture。
- suggestion review 必须可接受/拒绝，不能静默修改原宏。

### Slice C: Make Live Capture Safe

目标：证明 semantic recording 能在真实 macOS 环境里产出可靠证据。

必须完成：

- 通过 `SCRecordingOutput` 记录 target-window `.mov`。
- 同一录制生成 event-aligned keyframes。
- live bundle 持久化 video segment、frames、timeline/events/suppressed、OCR/window/AX observations。
- `semantic-recording debug-smoke --evidence-sidecar <path>` 随 live/preflight smoke 保留 command、preflight、bundle counts、redaction indexes、synthetic redaction rehearsal fields 和 review notes；`--synthetic-redaction` 只用于安全内容上的 renderer/sidecar 演练，不替代真实敏感场景证据。
- recording-start preflight 有产品证据：blocked/degraded 状态、Open Settings 行为、用户可理解提示。
- redacted frame/video ref consumption：frame PNG renderer/store hook 和 redacted `.mov` renderer/store hook 已能消费 `SemanticRecordingRedactionPlan` 写出遮罩后的图像/视频片段，`LiveSemanticRecordingSession.finish` 已在 bundle write 后应用 non-empty redaction plan，Review projection 和 S4 frame payload 已优先消费 redacted refs；下一步要补 live product evidence。
- playable macro text sanitization：纯 planner first pass 已有，且 playback-preserving readable metadata 已接入保存、当前 buffer 同步和导出路径；需要修改 `textAnchor.text` 的情况仍必须进 S3 Review 确认。
- retention confirmation UI：retention settings、manual cleanup confirmation 和 scheduled cleanup first pass 已有；仍需 live cleanup product evidence，普通 macro playback 不依赖视频存在。

### Slice D: Make CLI Useful To AI Without Overreach

目标：让 AI 能逐步查询证据、提出可审阅建议，而不是直接操作内部格式。

下一批命令：

- `recording ocr search --json`
- `recording visual search --json` metadata-only first pass 已有；image-byte similarity 后置
- `recording asset extract/baseline --json` explicit-source first pass 已有；product workflow integration 后置
- `recording suggest waits --json`
- `recording suggest locators --json`
- `recording suggest conditions --json`
- `workflow draft from-recording --json` fixture/review-only first pass 已有；product-ready stored/live synthesis 后置

CLI 必须保持：

- 输出 `sparkle.cli.result.v1`。
- 默认只返回 summary、ids、safe artifact refs 和 top candidates。
- 不默认导出图片 bytes 或完整视频。
- suggestion 必须带 evidence refs、confidence、risk、fallback。
- 缺少 evidence refs 的 suggestion 必须保持低置信度并显示 missing-evidence risk。
- draft 仍然走 validate/simulate/dry-run/import。

MCP 仍然不做第一优先级。未来 MCP 只能包装这些 CLI/shared service 语义，不能另起一套逻辑。

### Slice E: Keep Workflow Packaging As A Boundary

目标：AI 生成的东西能进入系统，但不能绕开用户验收。

当前应该做：

- 继续使用 `sparkle.workflow.draft.v1` 作为 AI/draft 入口。
- frame-derived visual assets 必须进入 `AutomationWorkflowDraftVisualAssets` 或 workflow package-local refs。
- import/export/package 设计要明确哪些 artifact 被复制、哪些保留为外部 package root、哪些缺失时显示 degraded。
- 对 AI 来说，可写目标是 draft/patch，不是 app 内部 repository JSON。
- workflow loop semantics now have a narrow explicit draft contract for fixed-count loops: draft v1 can expand a loop body into acyclic tasks/dependencies before validate/simulate/import. Product loop work remains open for authoring UI, runtime/run-evidence presentation, repeat-until/foreach policy and live proof; current dependency graphs intentionally reject cycles, so loops cannot be smuggled in as back-edges.

当前不应该做：

- 不让 AI 直接写 `automations.json`。
- 不让 AI 直接运行刚生成的 workflow。
- 不把 semantic bundle 的内部文件结构暴露成长期外部 API。

## 5. Overdesign Lines

以下设计现在应该被压住：

| Design | Why Not Now | Safer Path |
| --- | --- | --- |
| MCP first | 会复制 CLI/service 逻辑，权限、测试和错误模型都更复杂 | CLI/shared service 稳定后再包装 |
| every-frame OCR | CPU、存储、隐私和噪音成本高 | event-aligned keyframes + selected-frame OCR |
| global visual asset library | 文件迁移、删除、缺失引用复杂度过早爆炸 | recording/package-local assets first |
| AI direct-run workflow | 用户不可审阅，失败难解释 | AI 只写 suggestion/draft |
| full App Knowledge graph | 还没有足够 live semantic bundles | 先 app/surface/macro/anchor 轻量分组 |
| Player full rewrite as prerequisite | 会把用户价值拖成长期重构 | 增量抽 pure state/evidence helpers |
| dependency-cycle loops | 会绕过 DAG validation、run history 和 failure evidence 语义 | 固定次数 draft loop authoring/expansion 已有 editor/CLI/Draft Preview first pass；product authoring UI、repeat-until / foreach、runtime evidence 和 live proof 后置，仍不允许 graph back-edge |
| SwiftUI Vision/file IO | 卡顿、权限边界混乱、不可测 | app-edge presenter/adapters + core value data |
| video replaces playback truth | 会破坏 deterministic playback | `RecordedEvent` stays execution truth |

## 6. Maintenance Rules

后续每个相关 PR 必须更新至少一个 workstream，并在必要时同步本文件或 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)。

必须保持：

- Core: value types、safe refs、reducers、pure helpers、fake-client tests。
- App target: ScreenCaptureKit、Vision、AX、Open/Reveal、file IO、bundle store、live adapters。
- SwiftUI: projection/presenter result、selection、accepted user intent。
- CLI: stable envelope、safe refs、deterministic query/suggestion services。
- Docs: first pass、fixture proof、live product evidence 必须分开写。

## 7. Current Work Status For This Folder

本轮维护后的状态：

- `semantic-recording-ai/` 被确认为下一阶段方向纠偏工作台。
- 当前方向判断：正确，但必须围绕证据链、Review 教学和 CLI 可审阅协作收束。
- 当前 S0 strict live evidence 已关闭，S1 contract first pass 已关闭，S3 first pass 暂停等待 S2 live bundle，S4 fixture OCR/metadata visual/explain/suggestion CLI 已收束到 pure bundle/query boundaries，explicit stored-bundle read-only CLI、explicit-source asset extraction、fixture/review-only draft-from-recording、low-token transcript 和 no-evidence suggestion low-confidence guard 已完成，S2 debug-smoke 已有 sidecar 和 synthetic redaction rehearsal；最高优先级转为 S2 live capture smoke / ordinary Recorder bridge product evidence，再恢复 S3/S4 live product work。
- S0-S4 最终差距和验收姿态维护在 [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)：S0 closed、S1 first pass closed、S2 active blocker、S3 paused、S4 product-ready live work paused。
- 下一条用户价值主线是 Review and Teach，而不是 MCP 或 App Knowledge。
- 过度设计边界已在本文固定：MCP deferred、App Knowledge later、AI 不直接运行、every-frame OCR 不做默认路径。
- 剩余任务已按 Slice A-E 补充，供 S0/S2/S3/S4 workstream 继续拆实现。

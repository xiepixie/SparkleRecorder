# User Logic Roadmap And Scope Audit

更新时间：2026-07-06
状态：方向校准与剩余任务补充
Owner：Semantic Recording program coordination

本文是对 `semantic-recording-ai/` 当前方向的一次现实审阅。它补充两个问题：

- 从用户行为逻辑看，下一阶段到底应该先做什么。
- 从工程维护角度看，哪些设计是正确扩展，哪些已经接近过度设计。

结论先写清楚：当前方向是正确的，但只能在“语义证据层 + Review 教学层 + CLI 可审阅协作”这个边界内正确。它不应该演变成“录视频后让 AI 猜完整工作流并直接运行”的黑盒系统。

## 1. Direction Verdict

正确的产品路径是：

```text
用户录制一次真实操作
  -> App 保存可回放的 RecordedEvent
  -> 同时保存视频、关键帧、OCR、AX/window、suppression 和 visual evidence
  -> 用户在 Review 中解释等待、修正定位、提取视觉锚点
  -> AI/CLI 基于本地证据提出 suggestion 或 workflow draft
  -> 用户 validate / simulate / import
  -> 运行失败后回到 recorded baseline、runtime sample 和 branch evidence
```

不应该走的路径是：

```text
用户录一段视频
  -> App 把完整视频丢给 AI
  -> AI 猜测用户意图
  -> AI 直接写最终 workflow 并运行
```

SparkleRecorder 的优势不是“更会猜”，而是“能证明”。每一步自动化都应该能追到事件、帧、区域、OCR/视觉观察、运行样本、分支原因和用户确认。

## 2. Product Shape From User Behavior

用户的直觉不是先搭状态机。用户通常会这样使用：

1. 先快速录制，不希望在录制前配置复杂条件。
2. 录完后回看，才愿意告诉系统“这里是在等页面变化”、“这里要先点一下唤出按钮”、“这个等待应该绑定文字/图标/区域”。
3. 失败后，用户要看到系统当时看见了什么，而不是内部 JSON。
4. 同一个应用重复做几次后，用户才会希望 AI 复用已有宏、视觉锚点和等待条件。

所以下一阶段的第一用户路径应该是：

```text
Record
  -> Review
  -> Teach waits / locators / visual assets
  -> Compose or draft workflow
  -> Run
  -> Diagnose with source/runtime evidence
```

这条路径比“先做 App Knowledge 或 MCP”更重要。没有 Review 和证据链，AI 只会把脆弱坐标脚本包装得更像成品。

## 3. Current Architecture Reality

现在已有的框架已经够支撑下一阶段，不需要推倒重来：

| Layer | Current Truth | Next Role |
| --- | --- | --- |
| Playback truth | `RecordedEvent`、Playback engine、Player lifecycle shell | 继续负责真正执行；semantic evidence 不替代它 |
| Workflow truth | `AutomationWorkflow`、reducer、resource queue、retry、timeout、branch evidence | 继续负责状态机和可测试转移 |
| Visual condition truth | OCR/image/baseline/pixel/regionChanged condition first pass | 接收从 recorded frame 提取出的 assets |
| Evidence truth | Run evidence presenter、condition artifact presenter、branch evidence | 承接 source/runtime comparison 和 Open/Reveal |
| Semantic truth | `SemanticRecordingBundle` v0、frame/event/video refs、suppression records | 作为录制证据和 AI 查询的共享事实层 |
| AI interface truth | CLI-first `sparkle.cli.result.v1` envelope and workflow draft commands | 先做可测试 CLI；MCP 以后包装同一服务 |
| UI truth | SwiftUI projection + presenter result | 只渲染和发 intent，不运行 Vision/ScreenCaptureKit/file IO |

这说明下一阶段不是大型重构，而是沿这些边界补真实竖切。

## 4. Remaining Work By User Value

### P0: Make Current Workflow Evidence Trustworthy

这批任务必须先关，因为它们决定用户是否相信系统：

| Task | User Need | Acceptance |
| --- | --- | --- |
| Live visual diagnostics Open/Reveal | 用户能确认系统真的观察了指定区域 | Done for strict gate: `live-visual-diagnostics-open-reveal.mov` proves App-host OCR condition run payload, App Support sample artifacts and Open/Reveal file actions |
| Branch evidence consistency | 用户能相信为什么走绿色/红色分支 | Strict gate closed by `live-branch-evidence-consistency.mov`: App-host handoff run payload proves source run、target run、dependency trigger 和 live App window capture 一致；更完整的手动 Run Detail drill-in 可后续补充 |
| Macro failure evidence Open/Reveal | 失败后用户能立即打开报告和截图 | Done for strict gate: `live-macro-evidence-open-reveal.mov` proves App-host failed macro run payload and per-run evidence file actions |
| Authoring WYSIWYG | 拖拽、排序、连线的 preview 不能骗用户 | indicator 与 reducer mutation 一致，有 live clip |
| OCR/visual region picker | 用户能明确“只看这个区域” | 等待/验证类动作只显示区域框和编号；点击类动作才显示圆点/光圈 |

S0 严格 product evidence gate 现在是正确方向：它拒绝 fixture、placeholder、zero-byte clip、错误 sidecar 和非视频文件改名。这会让状态暂时更红，但这是可信产品化所需的红。

### P1: Build Review And Teach

这是 semantic recording 的第一条核心用户竖切：

| Task | User Need | Acceptance |
| --- | --- | --- |
| Macro Review frame strip | 用户能从事件跳回录制画面 | 事件行能显示 before/after frame |
| Frame region selection | 用户能框选文字、图标、区域、像素 | bounds、surface、source frame、artifact ref 都落到 bundle/draft |
| Frame-to-condition | 用户能把脆弱等待变成可靠条件 | OCR wait、image appeared/disappeared、region changed、pixel matched 能生成 draft patch |
| Source/runtime comparison | 失败时能对照录制基准和运行样本 | 同屏显示 source frame、runtime sample、score/diff/fallback |
| Suggestion review | AI/系统建议不能静默修改宏 | 每条建议带 evidence refs、confidence、risk、fallback，可接受/拒绝 |

P1 的目标不是让 AI 自动理解所有意图，而是让用户更容易教系统。

### P2: Make Live Capture Real

S2 first pass 已经有 core session、app-edge skeleton、preflight、suppression producer、普通录制 suppression context ingestion、pure frame/video redaction planning 和 app-edge redacted frame PNG writing hook。剩下的是产品证据和安全行为接线：

| Task | User Need | Acceptance |
| --- | --- | --- |
| Ordinary recording lifecycle wiring | 用户正常点 Record 就能产生 semantic bundle | `Recorder`/recording lifecycle 后台接入 `LiveSemanticRecordingSession`，可 feature flag |
| `.mov` through `SCRecordingOutput` | 用户有完整视频母带可回看 | macOS 15+ 真实 capture 写 video segment 和文件 |
| Event-aligned keyframes | Review/CLI 不必读整段视频 | start/click/text/wait/stop 附近有 frame refs |
| Live OCR/window/AX observations | 录制后能生成可检索 evidence | app-edge Vision/AX 产出 value observations |
| Preflight UX | 用户知道为什么不能录或只能 degraded | App shell 展示 blocking/degraded issue 和 action intent |
| Retention/deletion | 用户敢保存敏感视频 | 用户能删除 bundle artifacts；普通宏 playback 不依赖视频存在 |
| Suppression diagnostics/redaction | 敏感内容可解释地缺失 | Secure Input diagnostics first pass；password/excluded target suppression records；capture-level semantic suppression first pass；AI-safe semantic/OCR text redaction first pass；playback-preserving playable macro save/export/status sanitization first pass；pure frame/video redaction planning first pass；app-edge redacted frame PNG writing hook first pass；app-edge redacted `.mov` renderer/store hook first pass；live finish redaction application first pass；Review/CLI redacted-frame preference first pass；live product evidence and reviewed text-anchor mutation still open |

P2 不能把 ScreenCaptureKit、Vision、AX 或 file IO 放进 SwiftUI。

### P3: CLI For AI Collaboration

CLI 的目标是让 AI 逐步查询证据、提出可审阅草稿，而不是直接操纵每个内部字段。

| Command Slice | First Value |
| --- | --- |
| `recording show` | 让 AI 先知道这次录制是什么、有哪些证据 |
| `recording frames` / `events-near` | 让 AI 找到相关时刻和帧 |
| `recording ocr search` | 让 AI 找文字和候选区域 |
| `recording visual search` | 让 AI 找 persisted visual observation 候选；image-byte similarity 后置 |
| `recording asset extract` | 把用户/AI 选中的帧区域变成 draft visual asset；explicit-source first pass 已有 |
| `recording suggest waits/locators/conditions` | 提供带证据的非破坏建议 |
| `workflow draft from-recording` | Fixture/review-only first pass 生成 `sparkle.workflow.draft.v1` 并通过 validate/simulate；stored/live product-ready 仍走 Review/Draft Preview/import |

MCP 继续暂缓。未来 MCP 只能包装这些 CLI/shared service 语义，不能另开一套产品逻辑。

### P4: App Knowledge Later

App Knowledge 有价值，但现在不该成为主线。第一版最多保留轻量索引：

- app bundle id
- surface family
- macro group
- visual anchor group
- known waits / known failures

大型知识图谱、自然语言全自动规划、跨应用 skill memory，都应该等 Review、CLI query、draft-from-recording 和用户验收稳定后再做。

## 5. Action Vocabulary For Users

UI 不应该把所有视觉能力暴露成工程术语。用户应该看到的是动作意图：

| User-facing Action | Meaning | Visual Hint |
| --- | --- | --- |
| 点击位置 | fixed coordinate click | click circle / pulse |
| 点击文字 | find text then click | text box plus click target, not merged into generic multi-click |
| 等待文本 | wait until text appears in region | region box only |
| 验证文本 | assert text exists in region | region box plus check state |
| 等待图标出现 | image/template appears | crop thumbnail + search region |
| 等待图标消失 | image/template disappears | crop thumbnail + disappearance state |
| 等待画面变化 | watched region changed from baseline | baseline region + diff threshold |
| 等待颜色/像素 | pixel or color state appears | point sample only, no click affordance |
| 点击后等待 | click to reveal UI, then wait for target | two visible steps, not collapsed into multi-click |

多点点击应该表示“多个点需要快速连续点击”。如果两个点击之间存在有意义等待、画面变化或用户停顿，就应保留为独立步骤。否则用户很难表达“先点一下唤出 UI，再等待离开按钮出现，再点击离开”这类真实流程。

2026-07-07 OCR/visual scope maintenance note: OCR remains a text detector, not an icon detector. Workflow OCR conditions now crop the resolved `searchRegion` before running Vision text recognition; only no-region conditions scan the full captured display. The condition editor surfaces this as `Detector: OCR text` plus `Scope: selected region/full display`. Icon/button/pattern waits are represented as visual conditions (`imageAppeared`, `imageDisappeared`, `regionChanged`, `pixelMatched`) using local template similarity, baseline diff or pixel color checks, and the visual condition editor now shows the detector and scope separately. Ordinary Macro Editor still has product-ready text locator actions only; macro-level icon/template locator UX remains future work behind Review/Draft Preview and Workflow visual conditions.

2026-07-07 maintenance note: recorded coordinate clicks can now enter the text-target binding path, so selecting a Wait Text row plus its following recorded Click row can bind the same picked text to both rows and turn the click into a locator-backed "Click text" action. Selecting a Wait Text row also exposes a direct Add Click Text action that inserts the follow-up locator-backed click after the wait, reuses the wait anchor/timeout/fallback, and selects both text-target rows so one pick/type operation can keep them aligned. A separate Convert to Click Text path now replaces the Wait Text event itself with locator-backed mouse down/up events using the same anchor/timeout/surface, preserving script timing unless the new click would overlap the next event; incomplete red waits can become editable `Click text (needs text)` rows instead of disappearing, and sidebar conversion merges the current inspector/reviewed target text plus timeout into the conversion plan so freshly taught Wait Text targets do not fall back to stale event text. `TextTargetAnchorFactory` now preserves a recorded click's fallback point/content-normalized fallback when it is rebound as text, and derives missing inserted or converted text-click fallback from the OCR text box center instead of treating wait event origins as click points. `TextTargetReadiness` distinguishes empty inserted or missing-anchor visual-text actions from ready targets, so the editor no longer shows a blank Anchor card as if playback can succeed; the action list target column now distinguishes `No text target` for missing searchable anchors from `No target text` for empty target text, with matching English and Simplified Chinese entries in `Localizable.xcstrings`. `ActionPreviewAffordance` now separates wait/verify condition regions from click pulses at projection level, incomplete text clicks are not mergeable into ordinary coordinate multi-clicks, and Multi Click no longer exposes the single-point Action Type converter because a point sequence is edited through its point list rather than by changing Click/Double/Long Press count metadata. `editor-preview-affordances.png` / `.md` captures fixture overlay evidence for this mapping; the acceptance checklist still keeps the full preview/grouping product gate open until installed-app/full grouping evidence is captured.

Behavior binding maintenance note: users experience a bound behavior as one reusable recorded action, so copy/rename/edit semantics now follow that model. Copying a bound behavior creates a fresh `BehaviorGroupID` and `Copy of ...` label, preventing the copied block from merging back into the original; behavior list count chips use `ActionGroup.containedActionCount` through `actionRowCountLabel`, so a click+type behavior presents as two user actions rather than four raw down/up events. The Macro Editor sidebar has a dedicated Behavior area that now switches between `New Behavior` for naming/creating a whole-event block from selected actions and `Selected Behavior` for renaming, splitting or reusing an existing block through `Duplicate Behavior`. Duplicate Behavior is also the Selection/context-menu label when a behavior is selected, and copied rows are reselected by copied behavior id rather than raw copied event rows, so reuse keeps the copied block feeling like one whole event. Rename uses `BehaviorRenameReadiness`, so empty names, unchanged names and non-behavior selections explain themselves instead of making submit/button clicks look inert. The action-list context menu keeps the same editing context after structure changes: Create reselects the newly merged behavior row, Duplicate Behavior reselects the copied behavior row, and Unbind reselects the exposed action rows. Create requires at least two event-backed recorded action rows, no existing behavior in the selection and one continuous block of recorded actions; wait gaps may remain between selected actions, but an unselected real click/key/scroll action breaks the block. Disabled states explain whether the user needs more recorded actions, a continuous recorded block, a real behavior row, a changed behavior name or must rename/unbind an existing behavior first. This keeps users from accidentally wrapping a single click, crossing unrelated recorded work, nesting behavior blocks, seeing misleading raw-event counts, losing selection after grouping/splitting, overwriting behavior groups or trying an unchanged rename while cleaning up a recording. This is code/test proof for the editor model, not installed-app product evidence.

Macro editing timing maintenance note: users read insertion position, selected row and trailing wait as part of the macro's rhythm, not as disposable editor rows. The Macro Editor now uses shared live-duration helpers so inserted coordinate actions, Click Text, Add Click Text after Wait, Reveal and Click Text flows and appended multi-point click points preserve existing tail wait; inserting a Wait in the middle shifts later events and keeps the same tail wait, while inserting a Wait at the end extends `liveDuration`. Beginning or negative-index insertions now start at time 0 and move existing events later, so adding a missing first action does not sort that action behind the original macro. Inserted-action selection now follows matched inserted events after sorting/re-timing, so the Inspector and Preview stay on the action the user just added instead of a neighboring row. This keeps post-recording cleanup from changing playback cadence or editing the wrong action just because the user added a missing step. This is code/test proof for timing semantics, not installed-app editor evidence.

Action Type maintenance note: users expect Click / Double / Triple / Long Press to change the selected action's playback shape, including its duration. `convertClickType(at:from:to:)` now owns the event mutation, so converting Click to Long Press extends the mouse-up time to the long-press duration and the sidebar updates `liveDuration` with the same trailing-wait preservation rule used by insertions; converting Long Press back to Click / Double / Triple shortens the action to the normal click cadence, applies the selected click count, and preserves any wait that originally followed it. This prevents a macro from ending before the converted long press can finish, and prevents long-press cleanup from leaving stale action duration. Multi Click remains separate from this converter because it is a point sequence, not a single click-count variant. This is code/test proof for action type timing, not installed-app editor evidence.

Multi Click maintenance note: users edit Multi Click as a sequence of points, not as a click-count variant. The sidebar now drives Remove Last through `MultiPointClickPointRemovalReadiness`, shows localized help when a sequence is already at the minimum two points, and `removeLastMultiPointClick(at:)` only removes a complete down/up pair when more than two complete click points remain. This prevents a recorded multi-point action from being reduced into a single click, half-click, or misleading Action Type conversion while still letting users trim accidental extra points. This is code/test proof for point-sequence editing, not installed-app editor evidence.

Trim maintenance note: Trim Before and Trim After are destructive cleanup actions, so they now follow the same visible-readiness rule as batch edits. `ActionTrimReadiness` disables Trim Before when the selection is not exactly one action or the selected action is already at the beginning, and disables Trim After when the selection is not exactly one action or the selected action is already at the end. The valid cleanup paths remain enabled: removing leading delay before the first useful action, trimming trailing wait after the final action, and trimming at a passive-wait boundary. This avoids no-op trim clicks while preserving the user's expected macro rhythm. This is code/test proof for editor affordances, not installed-app editor evidence.

Shift Selected maintenance note: moving recorded actions should never feel like an inert edit. `ActionShiftReadiness` now disables Shift Selected for no selection, wait-gap-only selection and already-at-start backward shifts, and explains that derived wait gaps should be edited through Wait Duration instead of event shifting. The click path and Inspector `Time (s)` edits now share `RecordedEventTimeShiftPlan` / `timeShiftPlan`: `liveDurationAfterShifting` extends `liveDuration` when a selected event is shifted past the previous macro tail while preserving trailing wait on earlier shifts, and `shiftDeltaClampedToTimelineStart` clamps oversized backward shifts as one selected block at timeline start so internal spacing is not compressed by per-event clamping. This keeps timeline edits aligned with the user's mental model that real recorded actions move, derived waits represent duration, direct time edits preserve the action's internal rhythm, and playback length must still cover the last shifted action. This is code/test proof for editor affordances, not installed-app editor evidence.

Time Stretch maintenance note: users read Time Stretch as a whole-macro timing command, so disabled or no-op states now explain themselves. `ActionTimeStretchReadiness` disables Apply when there are no macro rows, the factor is non-positive/non-finite, or the factor is unchanged, shows localized guidance for those states, and `EditorSidebar.applyStretch` uses the same guard as the button. Real stretch operations still preserve trailing wait through `liveDurationAfterStretching`. This prevents empty macro stretches, destructive zero/negative factor writes and accidental 1.00x apply attempts from looking like meaningful edits. This is code/test proof for editor affordances, not installed-app editor evidence.

Selection Delete/Duplicate maintenance note: users expect the sidebar buttons and action-list context menu to agree on whether a selected row can be edited. `ActionSelectionDeletionReadiness` and `ActionSelectionDuplicationReadiness` now drive the sidebar Delete/Duplicate buttons and the button execution guards, while the underlying mutation still comes from `ActionGroupDeletionPlanner` and `ActionGroupPassiveWaitDuplicationPlanner`. Empty selection and zero-duration/empty derived rows no longer present as clickable sidebar actions, but recorded actions and real wait gaps still delete or duplicate through the same timing plans as the context menu. `duplicateEvents(at:)` also filters stale, out-of-range and repeated event indices before copying, so an outdated selection or future caller cannot crash the editor or duplicate the same raw event twice. This is code/test proof for editor affordances, not installed-app editor evidence.

Inspector input maintenance note: users read the Inspector fields as direct edits to the selected action, so bad typed input should not silently vanish. `ActionInspectorInputWarning` now reports invalid time/duration, timeout, start coordinate, end coordinate and key-code text with localized inline guidance. `EditorSidebar.applyInspector` uses the same finite/non-negative parsing helpers, so negative or non-finite time values do not move actions, invalid timeout values do not overwrite existing text waits/clicks, invalid coordinates do not retarget actions, and key-code edits accept harmless whitespace while still requiring a valid `UInt16`. This is code/test proof for editor affordances, not installed-app editor evidence.

Action List reorder maintenance note: users also interpret the up/down action-list arrows as script-order edits, so disabled arrows need to explain whether the selection is a derived wait gap, already at the top/bottom, or unable to move farther. `ActionRowReorderReadiness` now drives the toolbar help, and `actionRowReorderDisabledSummary` gives the both-disabled state a single explanation without pretending wait gaps are movable actions. This keeps action order editing aligned with the same rule as Shift Selected: real recorded actions move; wait gaps represent duration and are edited with Wait Duration. This is code/test proof for editor affordances, not installed-app editor evidence.

Undo maintenance note: users treat Undo as proof that an edit actually changed the macro. `MacroEditMutationSnapshot` now gates the Macro Editor, sidebar and action-list undo wrappers on actual `RecordedEvent` or `liveDuration` changes. Invalid/no-op Inspector submissions, unchanged timing edits and other no-change paths no longer create empty undo entries, while real event or duration edits still register undo/redo and refresh stats. This keeps the edit history aligned with user-visible script changes. This is code/test proof for editor affordances, not installed-app editor evidence.

Batch edit maintenance note: users expect a visible batch button either to work or to explain why it cannot. The Macro Editor sidebar now computes `batchTextTargetReadiness` for Shared Text Target, disabling Apply until selected text-capable rows also have a non-empty target text so a blank batch operation cannot turn multiple rows into `No target text`. It computes `batchCoordinateAlignmentReadiness` for Align X/Y to First, disables axes that cannot make a change, and explains single-selection, first-row-without-coordinate, no-other-coordinate-action and already-aligned states with localized copy. It also computes `batchTimeoutReadiness` for Standardize Timeout, enabling Apply only for Wait Text, Verify Text or already-targeted Click Text rows with a finite non-negative timeout, and explaining when the selection has no timeout-capable actions or the timeout value is invalid. This avoids silent no-ops, empty undo entries, destructive blank-target writes and invalid timeout writes when batch selection includes waits, keys, text conditions, ordinary clicks, already aligned points, negative timeout values or actions without timeout semantics. This is code/test proof for batch edit affordances, not installed-app editor evidence.

Workflow orchestration now has a narrow draft-level loop first pass: `sparkle.workflow.draft.v1` can express a fixed-count loop body through `AutomationWorkflowDraftLoop` and expand it into an acyclic workflow through `AutomationWorkflowDraftLoopExpander` before simulation/import. The expansion maps condition/manual-approval body steps to `conditionMatched`, so wait-text loop bodies can advance to the next body step or next iteration. `AutomationWorkflowDraftTests` covers fixed loop expansion plus invalid/nested loop rejection, and `AutomationWorkflowDraftPreviewProjectionTests` covers the Draft Preview/import projection path. This does not close product loop acceptance. Repeating schedules and macro playback loops are still different concepts, dependency cycles are still rejected by validation, and future loop work still needs user-facing authoring, run evidence, repeat-until/foreach policy and live product proof instead of graph back-edges.

2026-07-07 visual Repeat-Until design note: Repeat-Until should be a Workflow structured loop node with `Do` / `Until` / max attempts / timeout / polling / failure policy, not an arbitrary dependency back-edge and not a Macro Editor-only nested block. OCR remains text-only; icon/button/pattern waits use visual detectors. Runtime visual observation should be built on ScreenCaptureKit `SCStreamOutput` / `CMSampleBuffer`, with selected-region-first matching and explicit full-window/full-display scope when the user chooses it. Vision feature prints can provide tolerant image similarity, Accelerate can provide region-diff scoring, and Metal remains a later backend for large/high-frequency regions. Full details: [16-visual-repeat-until-design.md](16-visual-repeat-until-design.md).

## 6. Overdesign Audit

| Tempting Move | Risk | Decision For Now |
| --- | --- | --- |
| MCP first | 重复 CLI/service 逻辑，测试和权限边界更复杂 | 暂缓；先做 CLI/shared service |
| Every-frame OCR | CPU、存储、隐私和噪音过高 | event-aligned keyframes + selected-frame OCR |
| Global visual asset library first | 迁移/删除/缺失资产会拖垮第一版 | recording/package-local assets first |
| AI directly writes runnable workflow | 用户无法审阅风险，debug 困难 | AI 只写 suggestion/draft |
| Semantic evidence replaces playback | 会破坏确定性回放和测试 | `RecordedEvent` stays execution truth |
| SwiftUI performs Vision/file IO | 卡顿、不可测、权限混乱 | app-edge presenter/adapters + core value models |
| Player full rewrite as blocker | 会把 semantic recording 拖成重构项目 | 只抽可测 state machine/evidence helper，保持 lifecycle shell |
| App Knowledge graph now | 没有足够数据，图谱会空转 | 先按 app/surface/macro/anchor 轻量组织 |

## 7. Maintainability Rules

每个后续 PR 都应该能回答：

- 是否保持 `RecordedEvent` 为执行真相？
- 是否把 ScreenCaptureKit、Vision、AX、Open/Reveal、file IO 留在 app target？
- 是否让 SwiftUI 只渲染 projection/presenter result 并发送 accepted intent？
- 是否有 fake-client Swift Testing 覆盖核心行为？
- 是否所有 artifact ref 都是安全相对路径？
- 是否让用户可以删除或抑制敏感 evidence？
- 是否让 AI 输出引用 frame/event/evidence IDs，并保持可拒绝？
- 是否复用现有 `AutomationWorkflowDraftVisualAssets`、artifact presenter 和 CLI envelope？

如果答案是否定的，这个功能应该降级为设计文档、app-edge spike，或推迟到后续阶段。

## 8. Updated Work Status

本次维护把剩余任务补进 `semantic-recording-ai/` 的方式如下：

- 本文件补充用户路径、优先级、过度设计审计和维护规则。
- [workstreams/s4-cli-ai-app-knowledge.md](workstreams/s4-cli-ai-app-knowledge.md) 建立 S4 CLI/AI 工作台，明确 CLI-first、MCP deferred、App Knowledge later。
- [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md) 继续作为执行账本；本文件不替代它。
- [10-next-stage-reality-check.md](10-next-stage-reality-check.md) 继续作为现实校准；本文件把校准落到更明确的动作词汇和 Owner 任务边界。
- [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md) 继续作为当前方向控制台；下一阶段开工前用它核对剩余任务、过度设计裁剪和 P0-P4 顺序。

当前最重要的未完成项仍然是：

1. S0 live Workflow evidence strict gate 已关闭：visual diagnostics、macro evidence、authoring reorder 和 branch consistency live gates 均已补齐。
2. OCR/visual region picker 和动作预览语义修正。
3. S3 real Macro Review 自动绑定、frame crop package materialization 和 live 产品证据。
4. S2 ordinary recording lifecycle + live `.mov` / keyframes bundle。
5. S4 在 fixture-backed `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions` 后已补 explicit stored-bundle/default-root read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search`、metadata-only stored-bundle `recording suggest waits/locators/conditions`、suggestion artifact-file/deleted status、explicit-source frame-region asset extraction 和 fixture/review-only `workflow draft from-recording`；后续继续补 product-ready live catalog/search/suggestions、cleanup suggestions、image-byte visual similarity 和 product-ready stored/live draft-from-recording。
6. workflow-level loop semantics: fixed-count draft loop authoring/expansion has a first pass through the draft editor / CLI and Draft Preview; product authoring UI, repeat-until / foreach, runtime evidence and product proof remain open, and loops still cannot be represented by dependency cycles.
7. frame crop -> `AutomationWorkflowDraftVisualAssets` copy semantics。

只有这些闭环以后，才应该进入 MCP、App Knowledge graph 或模型辅助检测器。

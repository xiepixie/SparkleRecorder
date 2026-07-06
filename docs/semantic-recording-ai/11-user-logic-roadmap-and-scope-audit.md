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

2026-07-07 maintenance note: recorded coordinate clicks can now enter the text-target binding path, so selecting a Wait Text row plus its following recorded Click row can bind the same picked text to both rows and turn the click into a locator-backed "Click text" action. `TextTargetReadiness` also distinguishes empty inserted or missing-anchor visual-text actions from ready targets, so the editor no longer shows a blank Anchor card as if playback can succeed; the action list summary/target column now says `needs text` / `No target text` for incomplete text-target actions, with matching English and Simplified Chinese entries in `Localizable.xcstrings`. This is code-level evidence only; the acceptance checklist still keeps the full preview/grouping product gate open until region/click affordance evidence is captured.

Workflow orchestration still lacks a first-class loop action. Repeating schedules and macro playback loops are not workflow loop semantics, and dependency cycles are rejected by validation, so future loop work needs an explicit contract for loop body, termination/limit and evidence instead of a graph back-edge.

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
5. S4 在 fixture-backed `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions` 后已补 explicit stored-bundle read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search`、explicit-source frame-region asset extraction 和 fixture/review-only `workflow draft from-recording`；后续继续补 product-ready default/live catalog/search/suggestions、stored suggestion synthesis、image-byte visual similarity 和 product-ready stored/live draft-from-recording。
6. workflow-level loop semantics: loop body / repeat-until / foreach must be explicit and cannot be represented by dependency cycles.
7. frame crop -> `AutomationWorkflowDraftVisualAssets` copy semantics。

只有这些闭环以后，才应该进入 MCP、App Knowledge graph 或模型辅助检测器。

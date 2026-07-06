# Next Stage Reality Check

更新时间：2026-07-06
状态：方向校准与剩余任务分流
Owner：Semantic Recording program coordination

本文用于把当前已经完成的大量框架拉回到用户问题上：用户为什么要录制、录完之后如何修正、运行失败后如何理解，以及 AI/CLI 应该帮到哪里。它不是新的总路线，也不替代 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)。它的作用是给下一阶段开工前做一次现实校准。

## 1. Verdict

当前方向总体正确，但下一阶段必须收窄成一条可上线的用户路径：

```text
用户录制一次
  -> 停止后 Review
  -> 用户把等待、点击、视觉锚点教给系统
  -> 系统生成可验证的 macro / workflow draft
  -> 运行失败时回到录制基准和运行样本
  -> AI 只基于本地证据提出可审阅建议
```

正确的核心不是“做一个看视频的 AI agent”，而是把录制从坐标脚本升级成有证据、有来源、能被修正、能被组合的自动化资产。

如果下一阶段直接去做 MCP、全局 App Knowledge、每帧 OCR 或自然语言生成完整 workflow，就会过度设计。那些能力未来有价值，但现在缺少用户可见的证据链和 Review UX，会把不稳定性藏得更深。

## 2. User Logic

用户真实的直觉通常是这样：

1. 先录下来，不想在录制前设计状态机。
2. 录完后才想解释：“这里我是在等页面变化”，“这里要点离开”，“这里文字出现后再点”。
3. 失败时不想看内部 JSON，只想知道系统当时看到了什么，为什么没继续。
4. 同一应用重复做几次后，才希望 AI 帮自己复用已有宏、视觉锚点和等待条件。

一个典型场景：

```text
战斗完成
  -> 等一段时间
  -> 点击屏幕任意位置，让“离开”按钮显示
  -> 等待“离开”文字出现
  -> 点击“离开”
  -> 等待主界面或重新战斗入口出现
```

这个场景说明当前产品不应该只提供“等待文本”和“点击文本”。用户还需要更贴近画面状态的动作：

- 等待区域变化：从某一帧开始观察一块区域，变化达到阈值后继续。
- 等待图标出现或消失：例如 loading 消失、奖励图标出现。
- 等待像素或颜色状态：例如按钮亮起、状态条变色。
- 点击后等待：把“点击唤出 UI”与“等待目标出现”表达成连续意图，而不是误合并成多点点击。
- 失败诊断：如果“离开”没出现，能看到 recorded baseline、runtime sample、OCR 结果和 timeout 原因。

用户不需要在第一版看到复杂术语。UI 应把这些表达成“等待画面变化”、“等待图标出现”、“等待图标消失”、“等待文字出现”、“点击文字”、“点击位置”等直接动作。

## 3. What Is Already Strong Enough

这些底座已经可以支撑下一阶段，不需要推倒重来：

| Area | Current Strength |
| --- | --- |
| Recording boundary | `RawInputEvent`、`RecordingEventPipeline`、`RecordingSessionProcessor` 已经让底层 CGEvent 边界可测试 |
| Workflow core | reducer、resource queue、timeout、retry、join、branch evidence、run history 已经是比较完整的状态机底座 |
| Visual conditions | OCR/image/baseline/pixel/regionChanged 的 draft/runtime first pass 已有 |
| Evidence presenters | condition artifact、macro run evidence、Open/Reveal 边界已有 first pass |
| AI workflow draft | validate/simulate/dry-run/import/edit/patch 已有 CLI-first 基础 |
| Semantic contract | `SemanticRecordingBundle` v0、safe artifact refs、frame/event/preview comparison fixture 已有 |
| Semantic capture spine | `SemanticRecordingCaptureSession` / `SemanticRecordingCaptureClient` pure actor/client first pass 已有，fake tests 可生成 validating bundle |
| Product evidence gate | `workflow product-evidence audit` 和 sidecar template 已经能防止把 fixture 当 live 完成 |

所以下一阶段不是“重构一遍架构”，而是沿现有边界补真实产品路径。

## 4. Remaining Work By User Value

### P0: Make Current Workflow Evidence Trustworthy

先补这些，是因为它们直接决定用户是否相信系统。

| Task | User Value | Acceptance |
| --- | --- | --- |
| live visual diagnostics Open/Reveal | 用户能看到系统真实观察了哪块画面 | 真实 App run 中 Run Detail 显示 watched region、last sample/crop、score/threshold，Open/Reveal 打开真实 artifact |
| branch evidence consistency | 用户能相信绿色/红色分支为什么走 | 同一次 run 中 FlowGraph edge、selected run、Run Detail branch evidence 三者一致 |
| macro evidence file actions | 失败后用户能一键打开报告/截图 | Reveal Report / Open Screenshot 有真实录屏和 inline feedback |
| authoring WYSIWYG | 拖拽、排序、连线不能骗用户 | indicator 位置和 reducer mutation 一致，有 drag/reorder 或 drag-link 录屏 |
| OCR region bounds picker | 用户能清楚选择“只看这个区域” | 等待文本/验证文本只显示区域框和编号，不显示暗示点击的圆点；坐标、bounds 和 preview 一致 |

P0 完成前，不应宣称 semantic recording 已经能解决用户体验。否则视频和 AI 只会放大已有 evidence UI 的不可信。

### P1: Build Review And Teach

这是真正把录制变成语义资产的第一条竖切。

| Task | User Value | Acceptance |
| --- | --- | --- |
| Macro Review frame strip | 用户能从事件跳回录制时画面 | 点击事件行能看到 before/after frame |
| frame region selection | 用户能从录制帧框选文本、图标、区域、像素 | region bounds、source frame、surface id、artifact ref 都落到 bundle |
| frame-to-condition | 用户能把等待变成可靠条件 | OCR wait、image appeared/disappeared、region changed、pixel matched 能生成 workflow draft visual assets |
| source/runtime comparison | 失败时能对照录制基准和运行样本 | Run Detail 或 Review 同屏显示 source frame、runtime sample、decision、score/diff/fallback |
| suggestion review | AI/系统建议不自动改宏 | 建议带 evidence refs、confidence、risk、fallback，用户可接受/拒绝 |

P1 的重点是“教系统”，不是“AI 自动理解一切”。

### P2: Make Capture Real

S1 core contract 已有，S2 要把 live evidence 生产出来。

| Task | User Value | Acceptance |
| --- | --- | --- |
| `.mov` capture through `SCRecordingOutput` | 用户有完整视频母带可回看 | macOS 15+ 录制生成 video segment metadata 和文件 |
| event-aligned keyframes | 编辑和 AI 查询不需要读整段视频 | start/click/text/wait/stop 周围有 frame refs，和 event time 可对齐 |
| bundle storage | 录制证据能稳定保存、打开和删除 | app-edge store 写 video/frames/index/timeline/events/suppressed，core 只接收 safe refs |
| Vision OCR observations | 文本等待可从录制帧产生 | app-edge Vision 产出 `RecordingVisualObservation`，core 只存值 |
| suppression records | 敏感内容可解释地被隐藏 | secure input、排除窗口/应用、密码区域产生 `suppressed.jsonl` |
| retention/deletion policy | 用户敢保存视频证据 | 可以删除 bundle artifacts，普通 macro playback 不依赖视频存在 |

P2 不应该把 Vision、AX、ScreenCaptureKit 或文件 IO 放进 SwiftUI。

### P3: Expose CLI For AI Collaboration

CLI 的目标是让 AI 逐步查询证据、提出草稿，而不是一口气操纵所有内部细节。

| Command Slice | User/AI Value | Acceptance |
| --- | --- | --- |
| `recording show` | 先理解录制是什么 | JSON 返回 app/surface/key steps/evidence summary |
| `recording frames` / `events-near` | AI 定位相关时刻 | 返回 frame/event IDs、time、surface、safe refs |
| `recording ocr search` | AI 找文字证据 | 返回 bounding boxes、confidence、source frame |
| `recording asset extract` | AI/用户生成可复用视觉资产 | 输出 `AutomationWorkflowDraftVisualAssets` 可用 refs |
| `recording suggest waits/locators/conditions` | AI 提出可审阅优化 | 每条建议带 evidence refs、risk、fallback |
| `workflow draft from-recording` | 从录制生成 workflow 雏形 | 输出 `sparkle.workflow.draft.v1`，仍走 validate/simulate/dry-run/import |

MCP 继续暂缓。未来 MCP 只能包装这些 CLI/shared service 语义，不能另开一套产品逻辑。

### P4: App Knowledge Later

同应用知识库有价值，但必须等多个 semantic bundles 和 CLI 查询稳定后再做。

第一版只需要轻量组织：

- app bundle id
- surface family
- macro group
- visual anchor group
- known waits / known failures

不要现在做大型知识图谱、复杂自然语言规划器或跨应用 agent。

## 5. Overdesign Audit

| Tempting Move | Why It Is Too Much Now | Safer Move |
| --- | --- | --- |
| MCP first | 会复制 CLI/service 逻辑，测试更难 | 先稳定 CLI JSON envelope |
| every-frame OCR | CPU、噪音和隐私成本高 | event-triggered keyframes + selected-frame analysis |
| global visual asset library first | 迁移、丢文件、归属规则会先爆炸 | recording/package-local assets first |
| AI directly writes runnable workflow | 用户无法判断风险，debug 很痛苦 | AI writes draft/suggestion only |
| semantic recording replaces playback truth | 会破坏现有可测试回放底座 | `RecordedEvent` stays execution truth |
| SwiftUI performs Vision/file IO/path logic | 卡顿、不可测、权限边界混乱 | app-edge presenter/adapters + core value data |
| Player full rewrite as prerequisite | 容易把播放线拖住 | 先抽可测 state machine/evidence helper，保持 lifecycle shell |
| App Knowledge graph before Review | 没有足够证据，图谱会空转 | 先做 Review and Teach |

## 6. Feasibility And Maintainability

这个方向可实现，前提是继续遵守现有分层：

- Core: schema、ids、safe refs、pure helpers、reducers、test fixtures。
- App: ScreenCaptureKit、Vision、AX、file IO、Open/Reveal、storage。
- SwiftUI: projection、review surfaces、selection、accepted user intents。
- CLI: 复用同一 service/result envelope，不自己推导内部状态。

每个 slice 都必须满足：

- 可以用 fake clients 和 Swift Testing 覆盖核心行为。
- 不需要真实鼠标、键盘、Vision 或 ScreenCaptureKit 才能跑 unit tests。
- 所有 artifact ref 都是安全相对路径。
- 用户能删除或隐藏敏感 evidence。
- AI 输出必须引用 frame/event/evidence IDs。
- UI 文案和图形暗示必须符合动作含义：等待/验证显示区域，点击才显示点击圆点。

## 7. Current Maintenance Status

本次维护后，`docs/semantic-recording-ai/` 的责任更明确：

- [05-workflow-continuation-and-direction-review.md](05-workflow-continuation-and-direction-review.md) 负责路线判断。
- [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md) 负责执行账本。
- [08-parallel-workstreams.md](08-parallel-workstreams.md) 负责 S0-S4 owner 边界。
- [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md) 负责 S0 -> S1 preview-ref 合同。
- 本文件负责下一阶段现实校准：用户路径、剩余任务优先级、过度设计审计和可维护性规则。

当前仍未完成的最高优先级不是 MCP 或 App Knowledge，而是：

1. S0 live-product evidence 4 个严格门禁。
2. OCR/visual region picker 的真实用户体验。
3. Review UI 中 source frame / runtime sample / decision 的真实接线。
4. S2 live `.mov` + event-aligned keyframe + bundle storage API spike。
5. S3 frame-to-condition 竖切。
6. S4 fixture-backed `recording show` / `recording frames` CLI。

只有这些闭环能证明“录完能看懂、失败能解释、修正有证据、组合前可审阅”时，才进入更大的 AI/App Knowledge 阶段。

# Remaining Work And Direction Control

更新时间：2026-07-07
状态：当前方向控制台
Owner：Semantic Recording program coordination

本文把 `semantic-recording-ai/` 作为下一阶段纠偏工作台来使用：不是再扩一层宏大愿景，而是把已经完成的大框架收束成用户能理解、工程能维护、AI 能安全协作的几条竖切。

结论先写清楚：当前方向是对的，但只在一个前提下成立：SparkleRecorder 要做的是“证据驱动的自动化生产力工具”，不是“把视频丢给 AI 让它猜并直接运行”。我们要继续强化的是录制证据、Review 教学、可验证 draft、运行诊断和 CLI 查询；要推迟的是 MCP、全局 App Knowledge、大型知识图谱、every-frame OCR、自然语言直接运行 workflow。

## 1. Product Direction Verdict

正确路径：

```text
用户快速录制一次
  -> App 保存可回放 RecordedEvent
  -> 同时保存视频/关键帧/OCR/视觉/窗口/AX/suppression 证据
  -> 用户在 Review 里解释等待、修正定位、提取视觉锚点
  -> CLI/AI 基于本地证据提出 suggestion 或 workflow draft
  -> 用户 validate / simulate / import
  -> 运行失败后回到 recorded baseline、runtime sample、branch decision 和 failure evidence
```

错误路径：

```text
用户录一段视频
  -> AI 猜测完整意图
  -> AI 直接写内部 workflow
  -> AI 直接运行
```

SparkleRecorder 的差异化不是“猜得更多”，而是“能证明”：每个等待、点击、分支、失败、视觉判断都能追到事件、帧、区域、样本、分数、fallback 和用户确认。

## 2. User Behavior Logic

用户真实的使用顺序通常不是先搭复杂状态机，而是：

1. 先录下来，不希望录制前被迫配置条件。
2. 录完后回看，才愿意告诉系统“这里是在等页面变化”“这里先点一下唤出按钮”“这里应该等文字出现再点”。
3. 失败后想知道系统当时看到了什么，而不是看 reducer JSON。
4. 同一个应用重复自动化几次以后，才希望 AI 复用已有宏、视觉锚点和等待条件。

因此下一阶段 UI/UX 的核心不是更多工程按钮，而是让用户能自然表达这些动作：

| 用户动作 | 产品语义 | UI 暗示 |
| --- | --- | --- |
| 点击位置 | 在固定坐标点击 | 圆点、光圈、点击编号 |
| 点击文字 | 找到文字后点击 | 文字框 + 点击目标，不能和普通点击误合并 |
| 等待文本 | 等文字在区域内出现 | 只显示区域框和标签，不显示点击圆点 |
| 验证文本 | 断言文字在区域内存在 | 区域框 + 验证状态 |
| 等待图标出现 | 模板/图标出现后继续 | crop 缩略图 + 搜索区域 |
| 等待图标消失 | loading/状态图标消失后继续 | 消失状态 + 搜索区域 |
| 等待画面变化 | 某块区域相对 baseline 变化 | baseline 区域 + diff/threshold |
| 等待颜色/像素 | 按钮亮起、状态条变色 | 像素/颜色采样点，不暗示点击 |
| 点击后等待 | 点击唤出 UI，再等待目标出现 | 两个独立步骤，不合并成多点点击 |

多点点击只应该表达“多个点需要快速连续点击”。如果两个点击之间存在有意义的停顿、画面变化、等待或用户意图变化，就应该保留成独立动作。否则用户无法表达“战斗完成 -> 点一下屏幕唤出离开 -> 等待离开文字 -> 点击离开”这类真实流程。

## 3. Current Reality

目前框架已经足够，不需要整体推倒：

| Layer | Current State | Direction |
| --- | --- | --- |
| Recording | `RawInputEvent`、`RecordingEventPipeline`、`RecordingSessionProcessor` 已拆边界 | 保持 playable macro 快、稳、可测 |
| Playback | engine/state/evidence first pass 已有，`Player.swift` 仍是 lifecycle shell | 继续抽可测状态机，不把 semantic recording 卡在 Player 全重写上 |
| Workflow | reducer、resource、retry、timeout、branch evidence、run history 已较完整 | 先补 live product evidence，证明用户能信 |
| Visual condition | OCR/image/baseline/pixel/regionChanged first pass 已有 | 接收录制帧提取出的视觉资产 |
| Evidence UI | condition artifact、macro evidence、branch evidence first pass 已有；branch、visual diagnostics、macro evidence strict gates 均已由 live App-host payload / App Support artifact / live window capture 关闭 | S0 strict gate closed; next evidence pressure moves to S3 real Review/source-runtime drill-in |
| Semantic bundle | core schema、fixture、preview refs first pass 已有 | 作为 Review/CLI/AI 的共享事实层 |
| S2 capture | fake session、preflight、retention、suppression、redaction planning、redacted frame PNG writing hook、Review/CLI redacted-frame preference、Recorder bridge first pass 已有 | 补真实 `.mov`、keyframe、bundle 产品证据 |
| S3 Review | fixture/stored Review、Run Detail entry、frame region、Draft Preview handoff、package-local materialization、Run Target provenance 和 pixel picking first pass 已有 | 暂停主动扩 UI；等待 S2 live bundle + `SavedMacro.semanticRecording` 证据后再补 installed-app linked Review、frame-to-condition live clip 和 Review -> Draft Preview live evidence |
| S4 CLI | fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording`、explicit stored-bundle read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search`、explicit-source frame-region asset extraction、low-token transcript 和 no-evidence suggestion low-confidence guard 已有；S2 sidecar-aware loader/catalog entry point 和 UUID directory -> manifest id consistency rule 已接入 S4 read-only CLI | 暂停 product-ready live work；default/live catalog/search/suggestions、stored suggestion synthesis、image-byte visual similarity、product-ready stored/live draft-from-recording 等授权 live bundle evidence、default root selection、suggestion synthesis 和 Review/Draft Preview alignment |

这说明下一步不是“再设计一个大系统”，而是把现有边界串成可上线竖切。

## 4. Remaining Work Register

### P0: Close Workflow Evidence Trust

| Task | Status | Acceptance |
| --- | --- | --- |
| live visual diagnostics Open/Reveal | Done for strict gate | `live-visual-diagnostics-open-reveal.mov` / `.md` proves App-host OCR condition run payload, persisted App Support artifacts and Open/Reveal file actions |
| live macro evidence Open/Reveal | Done for strict gate | `live-macro-evidence-open-reveal.mov` / `.md` proves App-host failed macro run payload, per-run report/manifest/screenshot and Open/Reveal file actions |
| live branch evidence consistency | Strict gate done; richer manual UI clip optional | `live-branch-evidence-consistency.mov` / `.md` 由 App-host handoff run payload 与 live App window capture 关闭严格门禁；更完整的手动 Run Detail drill-in 可后续补充 |
| authoring WYSIWYG reorder | Done for S0 authoring OR gate | `live-task-reorder-wysiwyg.mov` + sidecar 已满足 authoring live gate；drag-link 可作为未来补充 |
| OCR/visual region picker | Open | 等待/验证类动作只显示区域框；点击类动作才显示圆点/光圈 |
| real Review preview refs | Open | source frame、runtime sample、decision/score/diff 在真实 Review 或 Run Detail 中渲染 |

P0 完成前，不要宣称 semantic recording 已经解决用户体验。视频和 AI 会放大证据 UI 的问题，而不是掩盖它。

### P1: Review And Teach

| Task | Status | Acceptance |
| --- | --- | --- |
| Macro Review frame strip | First pass | 用户能从事件跳到 before/after frame |
| frame region selection | First pass | bounds、surface、source frame、artifact ref 能落到 bundle/draft |
| frame-to-condition | First pass patch builder | OCR wait、image appeared/disappeared、region changed、pixel matched 能生成 review-only draft patch |
| source/runtime comparison | Fixture/stored Review proof | live installed-app UI 同屏显示 recorded source、runtime sample、score/diff/fallback |
| suggestion review | First pass fixture/stored proof | 每条建议带 evidence refs、confidence、risk、fallback，可接受/拒绝；live installed-app evidence waits on S2 bundle |

P1 的目标是“用户教系统”，不是“AI 自动理解所有东西”。

### P2: Live Capture

| Task | Status | Acceptance |
| --- | --- | --- |
| ordinary recording lifecycle rollout | Experimental bridge first pass | feature flag 下普通录制能稳定产出 semantic bundle，并有失败清理 |
| `.mov` capture through `SCRecordingOutput` | App-edge skeleton + pure bundle readiness audit | 授权 macOS 15+ 环境产出真实 video segment，并通过 readiness 摘要确认 video/keyframe/timeline/redaction sidecar 完整性 |
| event-aligned keyframes | Fake/session first pass | start/click/text/wait/stop 附近生成 frame refs 和 PNG artifact |
| OCR/window/AX observations | App-edge skeleton | live bundle 中有可查询 observations |
| suppression diagnostics/redaction | Producer + ordinary recording context ingestion + Secure Input diagnostics + capture-level semantic suppression + AI-safe semantic/OCR text redaction + playback-preserving playable macro save/export/status summary + pure frame/video redaction planning + app-edge redacted frame PNG writing hook + app-edge redacted `.mov` renderer/store hook + live finish redaction application + Review/CLI redacted-frame preference + debug-smoke synthetic redaction rehearsal + bundle readiness audit first pass | live product evidence and reviewed text-anchor mutation still open |
| retention/deletion UI | Settings policy + manual confirmation + scheduled cleanup first pass done | 用户可配置 visual evidence retention policy 并手动确认 cleanup；启动时定时 cleanup 已有 first pass；仍需 live cleanup product evidence，普通 macro playback 不依赖视频存在 |

P2 必须保持 ScreenCaptureKit、Vision、AX、file IO 在 app-edge；SwiftUI 只消费 presenter/projection。

### P3: CLI For AI Collaboration

| Task | Status | Acceptance |
| --- | --- | --- |
| `recording show` | Fixture first slice done; live/stored bundle open | fixture command 返回 summary、evidence availability、warnings、next actions；S2 loader/catalog first pass 已有，live CLI 等授权 bundle evidence 和 wiring |
| `recording frames` / `frame show` / `events-near` | Fixture first slice done; live/stored bundle open | fixture commands 返回 frame/event IDs、time、surface、safe refs，不默认返回图片 bytes；S2 loader/catalog first pass 已有，live CLI 等授权 bundle evidence 和 wiring |
| `recording ocr search` | Fixture and explicit stored-bundle read-only slice done; product-ready default/live open | 返回文字、bounds、confidence、query result ids、frame/source refs；S2 loader/catalog/root-id first pass 已接入，default/live CLI 等授权 bundle evidence、default root selection 和 wiring |
| `recording visual search` | Fixture and explicit stored-bundle metadata-only slice done; image-byte similarity open | 过滤 persisted visual observation kind/label/text，返回 observation ids、bounds、confidence/score、labels、safe refs；不读 image bytes，不跑 Vision/template matching |
| `recording asset extract` | Explicit-source first pass done; product integration open | stored bundle 或 fixture `--source-root` 读取 frame artifact，`--output-root` 下写 package-local image/baseline PNG，返回 compatible visual asset refs；未自动导入 workflow |
| `recording suggest ...` | Fixture waits/conditions slice done; stored/live synthesis open; no-evidence summaries stay low confidence | fixture 建议不突变宏，引用 evidence refs、confidence、risk、fallback、mutation policy；stored/live locators/cleanup 等 S2/S3 对齐后再接；缺少 evidence refs 的 suggestion summary 会被压到低置信度并追加 missing-evidence risk |
| `workflow draft from-recording` | Fixture/review-only first pass done; product-ready stored/live open | 产出 `sparkle.workflow.draft.v1`，仍走 validate/simulate/dry-run/import；stored/live synthesis 等 S2 live evidence、stored suggestion synthesis 和 Review/Draft Preview alignment |

MCP 继续暂缓。未来 MCP 只能包装这套 CLI/shared service 语义，不能另起一套系统。

### P4: App Knowledge Later

| Task | Status | Start Only When |
| --- | --- | --- |
| app/surface/macro grouping | Future | live semantic bundles 和 CLI show/frames 稳定 |
| app-level anchor library | Future | frame-derived visual assets 稳定 |
| natural-language composition | Future | suggestion/draft-from-recording 可审阅且可拒绝 |
| cross-recording skill memory | Future | 用户接受/拒绝记录和失败修正有稳定证据 |

现在做大型 App Knowledge 图谱是过度设计。第一版只保留轻量 app bundle id、surface family、macro group、visual anchor group、known waits/failures。

## 5. Overdesign Decisions

| Temptation | Risk | Decision |
| --- | --- | --- |
| MCP first | 会复制 CLI/service 逻辑，权限和测试更复杂 | Deferred |
| every-frame OCR | CPU、存储、隐私和噪音成本过高 | Event-aligned keyframes + selected-frame OCR |
| global visual asset library first | 文件归属、迁移、删除、缺失引用复杂度过早爆炸 | Recording/package-local assets first |
| AI directly writes runnable workflow | 用户无法审阅风险，debug 困难 | AI writes suggestion/draft only |
| video replaces playback truth | 破坏 deterministic playback 和测试 | `RecordedEvent` stays execution truth |
| SwiftUI runs Vision/file IO | 卡顿、权限混乱、不可测 | App-edge presenters/adapters only |
| Player full rewrite as blocker | 会把语义录制拖成重构项目 | Incrementally extract state machine/evidence helpers |
| App Knowledge graph now | 没有足够录制资产，图谱会空转 | App Knowledge later |

## 6. Maintainability Rules

每个后续实现都要过这几条：

- Core 只放 value model、safe refs、reducers、pure helpers、fake-client tests。
- App target 负责 ScreenCaptureKit、Vision、AX、Open/Reveal、file IO、bundle store。
- SwiftUI 只渲染 projection/presenter result，并发出用户确认过的 intent。
- CLI 复用同一 service/result envelope，不自己解析内部存储细节。
- AI 输出必须引用 frame/event/evidence IDs，且默认不可直接运行。
- 所有 artifact refs 必须是安全相对路径。
- 用户必须能删除或抑制敏感 evidence。
- 文档不能把 fixture proof、first pass、live product evidence 混成同一种完成。

## 7. Immediate Recommended Sequence

1. 修 OCR/visual region picker 的动作语义：等待/验证区域框，点击才有圆点；点击文本不和普通点击误合并。
2. S2 在授权 macOS 15+ 环境跑 `semantic-recording debug-smoke --json --evidence-sidecar <sidecar.md>`，保留真实 `.mov` + keyframe bundle 和 sidecar，并检查 payload/sidecar 的 bundle readiness status；需要安全演练 redaction renderer 时可加 `--synthetic-redaction`，但真实 password/Secure Input/excluded-context product evidence 仍需单独补。
3. S3 完成自动 run/macro -> semantic bundle 绑定，让 Run Detail 不再靠 open panel。
4. S3 完成 frame crop/package materialization，再把 frame-to-condition 推成真实产品流。
5. S3 first pass 暂停：只维护 fixture snapshots/action semantics；等 S2 ordinary Recorder bridge 产出 live bundle + `SavedMacro.semanticRecording` 后，再补 installed-app linked Review、frame-to-condition live clip 和 Review -> Draft Preview product evidence。
6. S4 fixture OCR/metadata visual query、pure `SemanticRecordingQueryEngine` deterministic suggestion query、no-evidence suggestion low-confidence guard 和 explicit stored-bundle read-only catalog/query 已完成，保持 `sparkle.cli.result.v1`、evidence refs、fallback/source 状态和 review-only mutation policy；`product-evidence/semantic-recording-cli-low-token-transcript.md` 记录了 explain/OCR/visual/suggest/draft/validate/simulate/import dry-run 的低 token fixture CLI 链路。
7. S2 sidecar-aware bundle loading/catalog/root-id entry point 已完成 first pass 并已接入 S4 explicit stored-bundle CLI；S4 explicit-source asset extraction 已能写 package-local image/baseline refs，fixture/review-only `workflow draft from-recording` 已能生成并验证/模拟 draft。下一步接 product-ready default/live catalog/search/suggestions 前仍需授权 live bundle evidence、default root selection 和 suggestion synthesis；image-byte visual similarity 仍 open，product-ready stored/live `workflow draft from-recording` 需在 stored suggestion synthesis、artifact status 和 Review/Draft Preview 边界稳定后再接。
8. App Knowledge 和 MCP 继续等待 CLI/shared service 稳定。

## 8. Current Work Status

本次维护状态：

- 已确认 `semantic-recording-ai/` 是下一阶段方向纠偏源，而不是替代 `automation-engine/` 或 `workflow-page-productization/`。
- 已把剩余任务按 P0-P4 补成明确执行队列，并标注 first pass、fixture first slice、open、future。
- 已把用户行为逻辑明确为 `Record -> Review -> Teach -> Draft -> Run -> Diagnose`。
- 已把过度设计裁剪规则写成可执行判断，尤其是 MCP deferred、App Knowledge later、AI 不直接运行。
- 已新增 [13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md)，把本轮方向判断和剩余任务收束为 Slice A-E：Workflow trust、Review and Teach、live capture、CLI/AI collaboration、workflow packaging/import boundaries。
- 已新增 [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)，把 S0-S4 最终差距和验收姿态固定为：S0 closed、S1 first pass closed、S2 active blocker、S3 paused、S4 product-ready live work paused。
- S0 strict live evidence audit 已完成：visual diagnostics、macro evidence、authoring reorder 和 branch consistency live gates 均已补齐，严格审计为 13/13。
- 2026-07-07 维护补齐 S4 low-token CLI transcript 和 suggestion-without-evidence safety gate：fixture CLI 能生成并验证/模拟/dry-run import 一个 review-only draft，但 product-ready default/live catalog/search/suggestion synthesis、image-byte similarity 和 stored/live draft synthesis 继续保持 open。
- 后续任何推进都应同步更新本文件、[06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)、[13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md)、[14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)、[acceptance-checklist.md](acceptance-checklist.md) 和对应 workstream。

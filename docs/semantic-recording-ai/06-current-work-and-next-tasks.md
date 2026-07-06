# Current Work And Next Tasks

更新时间：2026-07-07
状态：下一阶段执行账本
Owner：Recording / Workflow Evidence / AI CLI shared planning

本文把 `semantic-recording-ai/` 的愿景转成当前可执行任务。它的作用不是扩大范围，而是防止方向跑偏：先让现有 Workflow 证据可信，再做最小 semantic recording 竖切，最后再谈 AI 组合和 App Knowledge。

## 1. Current Work Status

当前项目已经有三块底座，可以支撑 semantic recording，但还不能直接宣称“AI 录制理解”完成。

| Area | Current State | Evidence | Gap |
| --- | --- | --- | --- |
| Low-level recording | `RawInputEvent`、`RecordingEventPipeline`、`RecordingSessionProcessor` 已把 CGEvent 边界和纯 pipeline 分开 | Swift Testing 覆盖 pipeline/buffer/sampler/session processor | 还没有 event-aligned keyframe/video bundle |
| Workflow runtime | reducer/effect/runtime/resource/player/condition/run history 已有 first pass | `AutomationReducerTests`、`AutomationOwnerBClientTests`、runtime/session tests；`live-task-reorder-wysiwyg.mov` proves one real authoring mutation；`live-branch-evidence-consistency.mov` proves App-host branch payload consistency；`live-visual-diagnostics-open-reveal.mov` and `live-macro-evidence-open-reveal.mov` close the remaining S0 live Open/Reveal gates | S0 strict gate is closed; remaining Workflow-adjacent product gaps are OCR/visual region picker polish and S3 real Review/source-runtime drill-in |
| Workflow AI draft | `sparkle.workflow.draft.v1` validate/simulate/dry-run/import/edit/patch 已有 first pass | Draft/import/runtime CLI tests | 还不能从 recording evidence 自动生成 draft |
| Visual conditions | OCR/visual condition、visual assets、package-root retention、condition diagnostics payload 已有 first pass | Contract/reducer/view projection/OwnerB tests; `template-baseline-preview-refs.png` fixture renders source/runtime/decision from `SemanticRecordingBundle` | 最终 Review UI 仍需把录制帧、运行样本、score/diff 接进真实用户流程 |
| Run evidence | Macro evidence presenter、condition artifact presenter、branch evidence first pass 已有 | Product fixture PNG + tests；authoring WYSIWYG live reorder evidence captured；branch strict gate captured from App-host run payload/window capture；visual diagnostics and macro evidence live Open/Reveal gates captured | S0 strict evidence gate is closed; S3 still owns real Macro Review / source-runtime evidence product clips |
| Semantic capture session | pure `SemanticRecordingCaptureSession` / `SemanticRecordingCaptureClient` 已能用 fake movie/frame/index clients 生成 bundle、video segment、event-aligned keyframes 和 observations；`SemanticRecordingCaptureTargetMapper` 已能把普通录制的 `PlaybackSurface` 映射成 target-window `RecordingCaptureTarget` 或 display fallback；`SemanticRecordingSuppressionProducer` 已能为 Secure Input、password field、excluded app/window/domain、private region、oversized artifact 生成 suppression records；`SemanticRecordingSuppressionProducer.captureSuppressionDecision(for:)` 已能判断 Secure Input、password field、excluded app/window/domain 和 private region 是否必须停止语义视觉采集；`SemanticRecordingCaptureSession` 已能根据 suppression 的 event/frame/exact time/timeRange 匹配 redacts AI-safe semantic event title/summary/evidence refs 和 OCR/AX/window observation text/confidence/artifact refs；`SemanticRecordingPlayableSanitizationPlanner` 已能根据 suppression 的 timeline event/frame/exact time/timeRange 匹配 explain 并生成普通可回放宏的 readable text fields sanitization plan，覆盖 `unicodeString`、`textAnchor.text` 和 `behaviorGroupName`，且标记 keyCode-based playback-preserving 与需要 reviewed mutation 的情况；`MacroPlayableSanitizationSummary` / `MacroLibrary.applyPlayableSanitization` / `MenuBarController` 已把 playback-preserving readable metadata withholding 接到保存、当前 buffer 同步和导出路径；`SemanticRecordingRedactionPlanner` 已能把 suppression records 转成 deterministic frame masks、stable redacted frame refs 和 video time-range redaction plans，优先用 observation bounds，必要时退回 full-frame masks；`SemanticRecordingFrameRedactionRenderer` / `RecordingBundleStore.applyRedactionPlan` 已能在 app-edge dry-run 或 confirmed-render redacted frame PNG，并写出 `redacted/frames/index.json`；`SemanticRecordingVideoRedactionRenderer` / `RecordingBundleStore.applyRedactionPlan` 已能用 macOS 15 AVFoundation async API confirmed-render full-frame redacted `.mov` ranges，并写出 `redacted/video/index.json`；`LiveSemanticRecordingSession.finish` 已能在 bundle write 后对 non-empty redaction plan 执行 frame/video redaction，并把 redacted frame/video count / pending video range count 暴露给 debug-smoke；`SemanticRecordingDebugSmokeEvidenceSidecar` / `semantic-recording debug-smoke --evidence-sidecar` 已能把 blocked/preflight/finished smoke 的 command、permission snapshot、capture target、bundle counts 和 redaction indexes 写成 sidecar 草稿；`SemanticRecordingBundleSidecars` / strict `RecordingBundleStore.loadBundle` 已能把 manifest + video/frame/timeline/event/OCR/suppression/redacted-frame/redacted-video sidecars 重组为完整 bundle，`SemanticRecordingBundleLoadResult` / `loadBundleTolerant` 已能为 corrupt optional sidecar 提供 manifest fallback 和 loaded/missing/failed diagnostics，`SemanticRecordingBundleDirectoryIdentity` 已定义 UUID directory -> manifest id consistency rule，`listBundleCatalog` 已被 S4 explicit stored-bundle read-only CLI 消费，product-ready default/live catalog 仍需 live evidence、default root selection 和 suggestion synthesis；`SemanticRecordingReviewProjection` 和 S4 frame payload 已优先消费 redacted frame refs，同时保留 source image refs；`LiveSemanticRecordingSuppressionContext` 已能从当前 capture target、AX focused secure/password field hints、window-title domain candidate 和 UserDefaults exclusion rules 生成 app-edge suppression context；`RecordingEngineDiagnostic.eventTapDisabledByUserInput` 已能把 event tap disabled-by-user-input 转成 Secure Input suppression signal；`Recorder` 已在 semantic start / event flush / Secure Input diagnostic 时检查 suppression decision：安全 context 送进 `SemanticRecorderBridge` / `LiveSemanticRecordingSession.addSuppressions(for:)`，敏感或排除 context 会 suppress experimental semantic bridge、取消/移除语义 bundle 并继续普通宏录制；`SemanticRecordingPreflightPresentation` 已能把 ready/blocked/degraded preflight result 转成 app-shell guidance；app shell 已在 `semanticRecordingEnabled` 开启时于 countdown/start 前执行 live preflight，blocking 不启动，degraded 以状态提示继续；recording-start preflight 会先于 popover close/countdown 执行，blocked 会打开 Settings guidance；`SettingsPanel` 已在实验开关下显示 SwiftUI preflight issue rows、re-check、permission-specific Open Settings actions、visual evidence retention controls 和 Privacy exclusions；`SemanticRecordingRetentionPlanner` 已能为 fresh/protected/expired/user-delete recording 生成保留、artifact prune 或 bundle delete 计划；`SemanticRecordingRetentionSettings` 已能把 retention days / expired disposition 转成 policy；`SemanticRecordingRetentionPresenter` 已能把 retain/prune/delete 计划转成纯 confirmation projection；app-edge `RecordingBundleStore.applyRetentionPlan` 已能 dry-run/执行 artifact prune 或 bundle delete；`SemanticRecordingScheduledRetentionCleanupPlanner` / `AppState` / `MenuBarController` 已能在启动时按 last-run interval 复用现有 preview/apply cleanup；`SemanticRecorderBridge` 已把普通 `Recorder` 以 `semanticRecordingEnabled` 实验开关接到 `LiveSemanticRecordingSession` 的 start/record/finish/cancel/suppress，cancel/failure/suppress cleanup 会停止 movie capture 并移除临时 bundle；`SavedMacro.semanticRecording` 已能把保存后的 macro metadata 链到 semantic bundle manifest；app-edge `LiveSemanticCaptureClient`、ScreenCaptureKit movie/frame、Vision OCR indexer、window/AX metadata indexer、bundle store、permission preflight evaluator 和 live PermissionCenter bridge 已编译通过 | `SemanticRecordingCaptureTests`、`SemanticRecordingPreflightTests`、`SemanticRecordingPreflightPresentationTests`、`SemanticRecordingRetentionTests`、`SemanticRecordingRedactionTests`、`SemanticRecordingPlayableSanitizationTests`、`SemanticRecordingDebugSmokeEvidenceTests`、`SemanticRecordingSuppressionTests`、`SemanticRecordingBundleTests`、`SemanticRecordingReviewProjectionTests`、`SemanticRecordingCLITests`、`SavedMacroPreviewCacheTests`、Swift 6 build | 普通录制 lifecycle 的 live 产品证据和默认 rollout、recording-start guidance 产品证据、redacted frame/video 产品证据、reviewed text-anchor mutation、live cleanup product evidence 仍缺 |
| Semantic Review UX | S3 Macro Review first integration 已有且 first pass 暂告一段落：core projection、interactive SwiftUI review view、Run Detail open-panel entry、live bundle presenter、artifact Open/Reveal、frame region selection、frame-to-condition draft patch builder、package-local Review asset materialization、Draft Preview handoff、Run Target provenance 和 pixel color picking UI | `SemanticRecordingReviewProjectionTests`; `workflow product-evidence snapshot semantic-review-timeline`; `semantic-review-draft-preview`; `semantic-review-materialized-actions`; `SemanticRecordingReviewPresenter`; `SemanticRecordingReviewDraftPatchBuilder`; `AutomationWorkflowDraftPreviewSheet` handoff; pixel color test | 每次 workflow run/session -> semantic bundle id 绑定、live installed-app linked Review、live frame-to-condition 产品录屏仍缺；这些下一步等待 S2 live bundle / ordinary Recorder bridge evidence |
| Context-only condition evidence | `previousOutcome`、external signal、manual approval 已通过 `AutomationConditionEvaluationEvidence.contextual` 生成 durable diagnostics | `AutomationOwnerBClientTests.contextualConditionEvaluatorUsesContextAndProviders` | UI 可展示，但还没有产品证据截图/录屏专门覆盖 |

本轮维护状态：

- 已确认 `semantic-recording-ai/` 应作为 Workflow 证据缺口之后的路线校准源，而不是替代 `automation-engine/` 或 `workflow-page-productization/`。
- 已把当前剩余任务整理为本文件的执行账本。
- 已把 `AutomationConditionEvaluationEvidence` 的 context-only diagnostics 纳入 current status，避免未来只把 diagnostics 理解成 OCR/visual 截图。
- 已完成 2026 Apple API 可行性核对并接受 macOS 15+ 产品基线：`SCRecordingOutput` 是默认完整 `.mov` 路径；同一录制生成 event-aligned keyframes 作为视觉索引；不规划 macOS 14 `AVAssetWriter` fallback；Vision 可提供 OCR/feature print/tracking primitives，但 pattern search 需要自有评分和 deterministic matcher。
- 已新增 [08-parallel-workstreams.md](08-parallel-workstreams.md)，把下一阶段拆成 S0 Workflow Evidence、S1 Contract/Core、S2 App Capture/Visual Index、S3 Review UX、S4 CLI/AI/App Knowledge。
- 已新增 [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md) 作为 S0 工作台，并确认 S1 已接受 [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md) 的 first-pass core contract；source/runtime/decision fixture 渲染证据已补，真实 Review UI 接线仍待补。
- 已新增 `workflow product-evidence audit` 作为 S0 证据门禁；当前 smoke 为 13/13 required present。`live-task-reorder-wysiwyg.mov` 和同名 sidecar 已关闭 authoring WYSIWYG gate，`live-branch-evidence-consistency.mov` 和同名 sidecar 已关闭 branch consistency gate，`live-visual-diagnostics-open-reveal.mov` / `.md` 已关闭 visual diagnostics Open/Reveal gate，`live-macro-evidence-open-reveal.mov` / `.md` 已关闭 macro evidence Open/Reveal gate。live artifact 可用 `.mov` 或 `.mp4`，但严格门禁会校验同名 sidecar 的必填 capture labels、拒绝未填写的占位符、拒绝 fixture/mock/synthetic evidence source、要求 `Checklist item:` 匹配 live gate title/id、要求 `Clip file:` 精确指向一个匹配候选，拒绝 zero-byte / size-unknown 的空 clip，并拒绝非视频文件改名成 `.mov` / `.mp4`。`workflow product-evidence capture-plan` 会列出每个缺失 live gate 的文件名候选、sidecar 模板命令、录屏后可复制的 `complete-sidecar` 命令模板、缺失/无效标签、undersized clip 和 invalid clip container；`workflow product-evidence prepare-live-capture` 可把缺失 live sidecar 草稿写入 product-evidence 目录且默认不覆盖已有记录；`workflow product-evidence complete-sidecar` 可在录屏后用 typed CLI 字段补全单个 sidecar 并校验 clip 文件名；`workflow product-evidence sidecar-template` 可生成单个 live gate 的标准 sidecar 草稿。`.build/debug/SparkleRecorder workflow product-evidence audit --require-live --json` 已验证 `allRequiredPresent: true`。
- 已新增 S1 core schema v0 first pass：`SemanticRecordingBundle`、video/keyframe/timeline/AI-safe event/visual observation/suppression/source preview/runtime sample/comparison/query/suggestion value types，以及 `SemanticRecordingFixture.checkoutBundle()` / query result / suggestion fixtures；测试覆盖 path safety、schema validation、fixture validation 和 preview comparison round trip。
- 已新增 [10-next-stage-reality-check.md](10-next-stage-reality-check.md)，把剩余工作按用户价值重新分成 P0 Workflow evidence trust、P1 Review and Teach、P2 live capture、P3 CLI for AI collaboration、P4 App Knowledge later，并明确 OCR/visual region picker、source/runtime comparison、frame-to-condition 和 Player state machine extraction 的边界。
- 已新增 [workstreams/s2-app-capture-visual-index.md](workstreams/s2-app-capture-visual-index.md)，记录 S2 capture session first pass、targeted tests、app-edge ScreenCaptureKit/Vision/store 骨架和生命周期接线/产品证据剩余任务。
- 已启动 S2 app capture first pass：`SemanticRecordingCaptureSession` 和 `SemanticRecordingCaptureTests` 用 fake clients 证明 `.mov` segment、event-aligned keyframes、AI-safe semantic events、OCR/window/AX observation 回填和 keyframe-only 模式；`SemanticRecordingCaptureTargetMapper` 已覆盖 `PlaybackSurface` -> target-window capture target 和 display fallback；`SemanticRecordingSuppressionProducer` / `SemanticRecordingSuppressionTests` 覆盖 Secure Input、password field、excluded app/window/domain、private region、oversized artifact 的 suppression record 生成，并新增 capture suppression decision 覆盖：敏感/排除 context 停止语义视觉采集，retention-only oversized artifact 不停止整段采集；`SemanticRecordingCaptureSession` 已新增 AI-safe 文本净化：suppression 匹配 event/frame/time/timeRange 时会 redacts semantic event title/summary/evidence refs 和 OCR/AX/window observation text/confidence/artifact refs；`SemanticRecordingRedactionPlanner` / `SemanticRecordingRedactionTests` 已新增纯 redaction planning：suppression 可转成 observation-bound frame masks、full-frame fallback masks、video time ranges 和 stable redacted frame refs；`SemanticRecordingFrameRedactionRenderer` / `RecordingBundleStore.applyRedactionPlan` 已新增 app-edge frame PNG writing hook，可 dry-run 或 confirmed-render redacted frame PNG，并写 `redacted/frames/index.json`；`LiveSemanticRecordingSession.finish` 现会在 bundle write 后执行 non-empty redaction plan，并把 redacted frame count / pending video range count 写进 debug-smoke；`SemanticRecordingBundle.redactedFrames` / `RecordingBundleStore.loadBundle` / `SemanticRecordingReviewProjection` / S4 frame payload 已提供 Review/CLI redacted-frame preference first pass，仍需 live 产品证据和 `.mov` range redaction；`SemanticRecordingDebugSmokeEvidenceSidecar` 已接到 `semantic-recording debug-smoke --evidence-sidecar <path>`，可为 blocked/preflight/finished smoke 写出 command、permission snapshot、target、bundle counts、redaction indexes 和 review notes；`LiveSemanticRecordingSuppressionContext` 已把普通录制的 app-edge suppression context 接到当前 capture target、AX focused secure/password field hints、window-title domain candidate 和 UserDefaults exclusion rules，`RecordingEngineDiagnostic.eventTapDisabledByUserInput` 已接入 Secure Input suppression signal，`Recorder` 会在 semantic start / event flush / Secure Input diagnostic 时检查 context，安全 context 送进 `SemanticRecorderBridge` / `LiveSemanticRecordingSession.addSuppressions(for:)`，敏感 context suppress experimental semantic bridge、取消/移除 bundle 并继续普通宏录制；`SemanticRecordingPreflightPresentation` / `SemanticRecordingPreflightPresentationTests` 覆盖 ready/blocked/degraded app-shell guidance；`MenuBarController` 已在实验开关开启时把 live preflight 接到普通录制 countdown/start 前，且会在 semantic preflight ready/degraded 后才关闭 popover 并进入 countdown，blocked 会打开 Settings guidance；`AppState` 保存 latest preflight presentation，`SettingsPanel` 暴露非默认 `Record visual evidence` 开关并显示 preflight issue rows、re-check 和 Open Settings actions；`SemanticRecordingRetentionPlanner` / `SemanticRecordingRetentionTests` 覆盖 fresh/protected retention、expired artifact prune 和 explicit bundle deletion planning；`RecordingBundleStore.applyRetentionPlan` 已提供 app-edge dry-run/confirmed artifact prune 和 bundle delete hook；`SemanticRecorderBridge` 已用 `semanticRecordingEnabled` 实验开关把普通 `Recorder` 的 flushed events、normal stop、discard/cancel 和 suppress 接入 `LiveSemanticRecordingSession`，并在 start/record/finish failure 或 suppression 前取消 active session 以清理临时 bundle；`SavedMacro.semanticRecording` 已能把保存后的 macro metadata 链到 semantic bundle manifest；app target 已有 `LiveSemanticCaptureClient`、`ScreenCaptureKitMovieRecorder`、`ScreenCaptureKitFrameSource`、`VisionRecordingIndexer`、`SemanticRecordingFrameObservationIndexer`、`SemanticRecordingFrameRedactionRenderer`、`RecordingBundleStore`；`SemanticRecordingPreflight` / `LiveSemanticRecordingPreflight` 已覆盖 permission snapshot、blocking/degraded capability 判断并通过 Swift Testing。当前 S2 targeted tests 已覆盖 capture/lifecycle cancel 不写 stop keyframe、AI-safe text redaction、suppression decisions、redaction planning、bundle sidecar loading、redacted frame consumption、debug-smoke evidence sidecar 和 CLI effective image refs；whole-worktree Swift 6 build 已通过。
- S2 debug-smoke 已补 `--synthetic-redaction` / `--synthetic-redaction-reason` 安全演练入口：授权机器可在非敏感窗口注入一条明确标记为 synthetic 的 suppression，验证 redacted frame/video sidecar 管线、JSON/plain summary 和 evidence sidecar 字段；真实 password/Secure Input/excluded-context product evidence 仍独立未完成。
- S2 已补 pure `SemanticRecordingBundleReadiness`：在 schema validation 之外检查 live bundle 是否具备 video/keyframe/timeline/AI-safe event、可选 OCR/window/AX observation、frame-to-video alignment 和 sensitive suppression 对应 redaction sidecar；debug-smoke finished JSON/plain/sidecar 会先通过 tolerant loader 重新读取刚写入磁盘的 bundle，再输出 `commandPlan`、app-facing `preflightPresentation`、persisted reload counts、结构化 `persistedBundleCountCheck` / memory-vs-persisted count match/mismatch、loaded/missing/failed sidecar diagnostics、readiness policy、status、issue counts、issue details 和 issue-specific follow-up actions，`--require-ocr` / `--require-window-or-ax` 可用于授权 live evidence review 的严格检查。
- 已新增 [workstreams/s3-review-ux-evidence-editing.md](workstreams/s3-review-ux-evidence-editing.md)，并完成 S3 Review UX first integration 且暂告一段落：`SemanticRecordingReviewProjection` 把 S1 fixture bundle 转成 frame strip、event before/after navigation、selected-frame overlays、source/runtime comparison、frame-to-condition candidates 和 review-only suggestion rows；`SemanticRecordingReviewPresenter` 可从真实 bundle directory / `manifest.json` 打开 Review，并集中解析 safe artifact refs；`SemanticRecordingReviewFixtureView` 现在支持 event/frame 选择、Before/After frame chips、真实 keyframe image display、frame drag region selection、artifact Open/Reveal、patch 保存、Review patch -> Draft Preview -> confirm import handoff、package-local Review asset materialization、materialized action evidence，以及 pixel 候选的 target color picker；`SemanticRecordingReviewDraftPatchBuilder` 把 OCR/image/baseline/pixel 候选转成 review-only `AutomationWorkflowDraftPatchDocument`，并通过 visual asset upsert ops 登记 region/image/baseline refs。S3 接下来只做维护；installed-app linked Review、per-run/session bundle drill-in 和 live frame-to-condition 证据等待 S2 live bundle / ordinary Recorder bridge evidence 后再继续。
- 已新增 [11-user-logic-roadmap-and-scope-audit.md](11-user-logic-roadmap-and-scope-audit.md)，把下一阶段从用户路径重新收敛为 P0 Workflow evidence trust、P1 Review and Teach、P2 live capture、P3 CLI for AI collaboration、P4 App Knowledge later；并明确等待/验证只显示区域框，点击才显示圆点，点击后等待不应被误合并为多点点击。
- 已新增 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)，作为当前方向控制台：把剩余任务、用户路径、过度设计裁剪、P0-P4 队列、S0 当前 live evidence 状态和“做/不做”决策收敛到一页，供下一阶段开工前复核。
- 已新增 [13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md)，记录本轮方向纠偏结论：当前路线正确但必须围绕证据链、Review 教学和 CLI 可审阅协作收束；剩余任务按 Slice A-E 组织为 Workflow trust、Review and Teach、live capture、CLI/AI collaboration 和 workflow packaging/import boundaries。
- 已新增 [workstreams/s4-cli-ai-app-knowledge.md](workstreams/s4-cli-ai-app-knowledge.md)，冻结 S4 CLI-first / MCP-deferred 边界和 fixture-first MVP。S4 已实现 fixture-backed `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording`，也已实现 explicit stored-bundle read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search` 和 explicit-source frame-region asset extraction，均返回 `sparkle.cli.result.v1`、fixture/source 状态、S1 evidence ids 和 safe artifact refs；OCR payload 现在显式区分 `deterministicFixture` 与 `persistedBundle`，suggestion payload 显式暴露 `query.allowedKinds`、availability 和 unavailable reason，stored/live suggestion synthesis 仍返回 unavailable；product-ready default/live catalog、stored suggestion synthesis、image-byte visual similarity、product-ready stored/live `workflow draft from-recording` 和 App Knowledge 仍未实现。
- 2026-07-07 S4 维护补齐低 token CLI 证据和安全门：`semantic-recording-cli-low-token-transcript.md` 记录 fixture `recording explain`、OCR/visual query、suggestion、`workflow draft from-recording`、validate、simulate 和 import dry-run 全链路均只返回 compact ids / safe refs，不输出图片或完整视频 bytes；`SemanticRecordingCLISuggestionSummary` 现在把缺少 evidence refs 的 suggestion summary 压到低置信度并追加 missing-evidence risk。Product-ready default/live catalog/search/suggestion synthesis、image-byte similarity 和 stored/live draft synthesis 仍保持 open。
- 已新增 [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)，把 S3 暂停后的 S0-S4 最终差距收敛为 live evidence、live producer completeness、ordinary Recorder bridge、bundle identity/default root、privacy safety、S4 product-ready live AI collaboration 六组，并明确 S0 closed、S1 first pass closed、S2 active blocker、S3/S4 paused。已新增 [15-s2-live-evidence-playbook.md](15-s2-live-evidence-playbook.md)，把 S2 授权 live capture、ordinary Recorder bridge、安全/cleanup 和 S3/S4 handoff 证据路径写成可执行 checklist，但不关闭任何 live gate。尚未把 S2 的普通宏录制 lifecycle 做成用户可见默认路径；尚未产出 live `.mov` 产品证据、AX/window observation live evidence、installed-app linked Macro Review evidence、product-ready default/live Recording CLI、redacted frame/video consumption 产品证据、reviewed text-anchor mutation 或 live cleanup product evidence。
- 2026-07-07 UI owner checkpoint：Macro Editor action list 开始消费 text-target readiness。locator-only click / wait text / wait text gone / verify text 在缺 anchor 或缺 non-empty target text 时优先显示 `No target text`，并由 tests 覆盖 `.missingAnchor`、`.missingText` 和 `.ready`。后续同轮 code polish 新增 `TextClickEventFactory` 和 Wait Text 行内 `Add Click Text`：用户可以复用等待目标的 anchor/timeout/fallback，在等待之后插入 locator-backed text click，并同时选中等待和新点击行继续共享 Teach/Pick target。`MacroEditorLocalizationTests` 现在守护 Macro Editor 所有 `NSLocalizedString` key 都具备 `en` 和 `zh-Hans` 条目，并拦截新增的硬编码静态可见 `Text` / `Button` / `Label` / `TextField` 文案。`ActionPreviewAffordance` 把 wait/verify condition region、text click target、ordinary input point、multipoint 和 drag path 的预览语义放到 projection 层；incomplete text click 也不再合并进 ordinary coordinate multi-click。`editor-preview-affordances.png` fixture screenshot 已证明 `TargetCrosshairView` 渲染这些 affordance；installed-app/editor 录屏验收仍 open。这是 S3 暂停后的 UI 打磨方向样例：把已有后端/projection 状态变成用户可理解的修正入口，不把缺失 live evidence 的能力伪装成完成。

## 2. Direction Decision

方向正确，但正确点不在“让 AI 看视频自动操作电脑”，而在“让一次录制变成可解释、可修正、可组合的自动化资产”。

正确路线：

```text
record playable macro
  -> align events with keyframes and visual observations
  -> user reviews intent and fragile waits
  -> extract visual assets / conditions from frames
  -> AI proposes draft with evidence refs
  -> user validates, simulates, imports
  -> runtime evidence feeds diagnosis and future cleanup
```

需要避免的路线：

```text
record video
  -> send whole video to AI
  -> AI guesses workflow
  -> write runnable automation directly
```

SparkleRecorder 的优势是本地确定性：录制事件、窗口/视觉证据、Workflow reducer、condition evaluator、CLI draft 和 run evidence 都能被测试和审阅。Semantic recording 应该增强这些边界，而不是绕过它们。

## 3. User Behavior Logic

用户不是一开始就想配置复杂状态机。用户的直觉路径是：

1. 快速演示一次，不想打断录制。
2. 停止后回看，才愿意解释“这里在等什么”、“这个输入是否是变量”、“这个点击是否应该绑定文字或图标”。
3. 让 AI 帮忙提出修正，但用户要看到证据。
4. 把多个已知宏拼成 workflow。
5. 运行失败后回到证据：录制时基准、运行时样本、分支原因、失败截图。
6. 对同一应用重复积累，下一次少录一点。

所以第一版产品不应该要求用户在录制前设计 workflow，也不应该要求用户相信 AI 的黑盒结论。第一版应该让用户录完之后更容易“教系统”。

## 4. Remaining Task Register

### Bridge A: Close Current Workflow Evidence

这些任务优先级最高，因为它们验证现有 Workflow 是否可信。

| Task | Owner | Why It Matters | Acceptance |
| --- | --- | --- | --- |
| Live visual diagnostics recording | App + UI | 用户需要看到系统真实看了哪里，不只是 fixture | 真实 App 运行 OCR/visual condition，Run Detail 显示 sample/crop/score/threshold，Open/Reveal 打开真实 artifact |
| Branch evidence real-run recording | Core + UI | 用户需要相信 FlowGraph 走线和 Run Detail 原因一致 | Done for strict gate: `live-branch-evidence-consistency.mov` proves App-host handoff run payload consistency across source run, target run, dependency trigger and live App window capture; richer manual Run Detail drill-in can still be recaptured later |
| Macro evidence file-action recording | App + UI | 失败后用户第一件事是打开报告或截图 | Reveal Report / Open Screenshot 真实交互有 inline feedback |
| Drag/reorder WYSIWYG recording | UI | 编排页面必须可用，preview 不能骗用户 | Done for task reorder: `live-task-reorder-wysiwyg.mov` shows the right-inspector Down/Up controls moving `大贸易` below `生产管理`, graph/list staying aligned, then restoring order |
| Template/baseline preview contract | S0 + S1 + App + UI | 字符串 refs 不够，用户要知道 ref 指向什么 | S1 已接受 first-pass core contract；S0 fixture artifact 已展示 source/runtime/decision；下一步需要真实 Run Detail/Review UI artifact 展示 recorded template/baseline、runtime sample、score/diff/fallback |
| Resource/runtime product evidence | Core + UI | 等待资源、重试、超时要能被用户解释 | 多 workflow resource queue、max wait、handoff status readback 有产品证据 |

Bridge A strict S0 live gates are now closed. Do not use that to claim semantic recording, Review UI, frame-to-condition, or App Knowledge completion; those remain S2/S3/S4 work.

### Phase 0: Freeze Minimal Semantic Contract

| Task | Owner | Deliverable | Notes |
| --- | --- | --- | --- |
| Bundle schema v0 | Core | `SemanticRecordingBundle`, version, ids, paths | Keyframe-only compatible; full video optional |
| Timeline/event split | Core | private `timeline.jsonl`, AI-safe `events.jsonl`, `suppressed.jsonl` | Suppression is a first-class artifact, not a log afterthought |
| Frame refs | Core | `RecordingFrameReference`, event/frame/surface alignment | Must support click before/after frame |
| Visual observations | Core | OCR/AX/window/pixel/template observation value types | App produces, core stores values |
| Asset mapping | Core + App | frame crop -> `AutomationWorkflowDraftVisualAssets` | Reuse existing visual asset refs and safe path rules |
| Retention/deletion policy | App | user-facing local storage and delete semantics | Video/keyframes are sensitive |
| Apple availability policy | App + Core | macOS 15+ baseline, default `SCRecordingOutput` video, event-aligned keyframes, no macOS 14 fallback | Must be written before live video code |

### Phase 1: Video Plus Keyframe Recording Slice

First implementation should prove full video and keyframes together, while still allowing a future light keyframe-only mode for privacy/storage.

| Task | Owner | Acceptance |
| --- | --- | --- |
| Pure capture session | Core | first pass done: fake clients build a validating `SemanticRecordingBundle` with video segment, keyframes, semantic events and observations |
| Capture `.mov` recording | App | first pass adapter compiles; accepted only when ordinary recording lifecycle writes a real `SCRecordingOutput` video segment with start/end metadata and preserved live evidence |
| Capture event-aligned keyframes | App | first pass adapter compiles; accepted only when ordinary recording lifecycle writes frame refs and PNG artifacts around start/click/text/wait/stop in the persisted live bundle |
| Persist frame index | App + Core | first pass done in pure capture/bundle contract: frame IDs, event IDs, video segment IDs, time, surface ID and related-event lookup round-trip. Live bundle evidence remains open |
| Macro Review frame strip | UI | fixture/stored projection first pass done; installed-app Macro Review from `SavedMacro.semanticRecording` remains blocked on S2 ordinary Recorder bridge evidence |
| OCR on selected frames | App | first pass bundle values and Vision adapter compile exist; accepted only when live Vision OCR observations persist and reload from an authorized bundle |
| Tests | Core/App | fake clock/frame fixtures prove alignment; no real ScreenCapture in unit tests |

Full `.mov` capture is part of semantic recording on macOS 15+. Keyframe-only can remain a user-facing light mode, but no macOS 14 fallback is planned.

### Phase 2: Frame-To-Condition

This is the product vertical slice that makes semantic recording valuable.

| User Action | System Output | Acceptance |
| --- | --- | --- |
| Select text area on recorded frame | OCR wait condition draft | fixture Review first pass done: draft patch validates against existing OCR condition model. Live installed-app evidence remains open |
| Select icon/button crop | `imageRef` template asset | fixture/manual frame crop materialization first pass done. Live package-local asset materialization from a saved-macro-linked bundle remains open |
| Select result panel | `baselineRef` region-changed asset | fixture/CLI baseline extraction first pass done. Live region-changed condition creation and runtime comparison evidence remain open |
| Pick a status pixel | `pixelMatched` condition | Review color picker first pass done. Live pixel sampling from recorded frames and product evidence remain open |
| Accept suggestion | Draft patch or workflow draft | fixture/review-only suggestions include evidence refs, confidence, risk and fallback. Stored/live suggestion synthesis remains open |
| Reject suggestion | No mutation | first pass done: Review/S4 action semantics keep rejection local and preserve playable macro/workflow storage |

### Phase 3: Recording CLI

CLI comes after bundle fixtures exist.

| Command Group | First Commands | Current Acceptance / Blocker |
| --- | --- | --- |
| Catalog | `recording list/show/explain --json` | fixture and explicit stored-bundle reads are done; product-ready default/live catalog is blocked by S2 root/id policy and accepted live bundles |
| Frame query | `recording frames/frame show/events-near --json` | fixture and explicit stored-bundle reads are done; product-ready default/live reads are blocked by S2 live bundle/root policy |
| OCR/search | `recording ocr search --json` | fixture and explicit persisted-bundle OCR filtering are done; product-ready live OCR search is blocked by live Vision observations in accepted S2 bundles |
| Asset extraction | `recording asset extract/baseline --json` | explicit-source extraction is done; product flow is blocked by Review/Draft Preview alignment over saved-macro-linked live bundles |
| Suggestions | `recording suggest waits/locators/conditions/cleanup --json` | deterministic fixture suggestions are done; stored/live synthesis is intentionally unavailable until S2 live evidence and Review mutation boundaries are accepted |
| Draft | `workflow draft from-recording --json` | Fixture/review-only first pass done; product-ready stored/live suggestion synthesis + draft compiler open |

MCP remains deferred. When needed, MCP should wrap this service/CLI semantic contract, not create a separate product logic path.

### Phase 4: App Knowledge

This is future work, not next sprint.

| Task | When To Start |
| --- | --- |
| Group macros/recordings by app bundle ID and surface family | After several recordings have semantic bundles |
| Build app-level anchor/condition library | After frame-derived assets are stable |
| Natural-language goal composition | After CLI can explain, search, and generate draft from evidence |
| Cross-recording reusable skill summaries | After users can reject/accept AI suggestions reliably |

## 5. Overdesign Audit

| Tempting Design | Risk | Safer Version |
| --- | --- | --- |
| Full video without controls | storage and privacy risk | video default for semantic recording, plus explicit retention, deletion, exclusions and optional light mode |
| OCR/AX on every frame | CPU and noisy evidence | event-triggered keyframes and selected-frame analysis |
| Global visual asset library first | hard migration and missing-file complexity | recording/package-local assets first, then managed storage |
| AI writes runnable workflow | unsafe and hard to debug | AI writes draft/suggestion with evidence refs |
| MCP now | duplicated logic and harder tests | CLI/shared service first; MCP wrapper later |
| App knowledge graph now | too abstract without data | app/macro/surface grouping first |
| SwiftUI visual processing | hangs and untestable code | app-edge presenters/adapters and core value models |

## 6. Maintainability Checks

Every semantic recording PR should answer:

- Does this keep `RecordedEvent` as execution truth?
- Does this store evidence as versioned value data with safe relative refs?
- Can the feature be tested without real mouse, keyboard, ScreenCaptureKit, Vision or AX in unit tests?
- Does SwiftUI only render projections/presenter results?
- Does AI output cite frame/event/evidence IDs and stay reviewable?
- Does this reuse `AutomationWorkflowDraftVisualAssets`, artifact presenters and CLI envelope patterns?
- Can users delete or suppress sensitive recording evidence?

If the answer is no, the implementation probably belongs in a later phase or behind an app-edge adapter first.

## 7. Immediate Next Slice

Recommended order from here:

1. Product UX closure: text-target readiness and preview-affordance code polish are in place, with fixture `editor-preview-affordances.png`; next evidence step is installed-app editor recording showing wait/verify region labels and click-only pulse affordances in the real overlay.
2. API spike: target-window/display `.mov` capture through `SCRecordingOutput` plus event-aligned keyframes, with fake capture clients for tests. First pass now has fake-client session tests, app-edge ScreenCaptureKit/Vision/store skeletons, strict sidecar-aware bundle loading and explicit tolerant load diagnostics; next step is following `15-s2-live-evidence-playbook.md` on an authorized macOS 15+ machine to capture the real smoke path and ordinary Recorder bridge evidence.
3. S3 is paused except for fixture/action-semantics maintenance. Resume S3 only after S2 produces an accepted live bundle through the ordinary Recorder bridge and `SavedMacro.semanticRecording`; then capture installed-app linked Review -> Draft Preview -> confirm import.
4. CLI follow-up: S4 fixture OCR/visual query, deterministic suggestion query/result availability contract, fixture/review-only draft-from-recording and explicit stored-bundle read-only catalog/query are done; S2 stored bundle root/id policy now has a first pass, and product-ready default/live catalog/search/suggestions plus stored/live draft synthesis are next blocked by authorized live bundle evidence, default root selection, stored suggestion synthesis and Review/Draft Preview alignment rather than by manifest-only loading.
5. Asset materialization: define and implement frame crop file copy/package-local refs for generated image/baseline assets before shipping frame-to-condition broadly.
6. UI polish: add clearer accept/reject affordances for frame-to-condition suggestions, and capture product evidence for pixel color picking.
7. Frame-to-condition live validation: record OCR wait, image appeared/disappeared and region changed creation from a real bundle.
8. Playback architecture follow-up: continue extracting `Player.swift` lifecycle state into pure testable state machine/evidence helpers, but do not block semantic recording planning on a full Player rewrite.

This sequence keeps the project grounded: every new AI-facing capability starts from evidence a user can see.

并行执行边界见 [08-parallel-workstreams.md](08-parallel-workstreams.md)。下一阶段现实校准见 [10-next-stage-reality-check.md](10-next-stage-reality-check.md)，当前方向控制台见 [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md)，本轮方向纠偏和剩余切片见 [13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md)，S3/S4 暂停后的 S0-S4 总差距见 [14-s0-s4-final-gap-alignment.md](14-s0-s4-final-gap-alignment.md)。S0 进展维护在 [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md)。下一轮实现时不要把 S1/S2/S3/S4 的职责混到一个 PR 里；当前最重要的是让 S2 产出可审阅的 live bundle/product evidence。

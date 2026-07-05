# Automation Engine Current Status

本文记录截至当前工作树的迁移状态。状态以代码事实为准，不把规划当完成。全局文档角色和完成标记见 [../DOCUMENTATION_STATUS.md](../DOCUMENTATION_STATUS.md)。

## 已完成或基本完成

| Area | Status | Evidence |
| --- | --- | --- |
| Swift 6 baseline | Done | `Package.swift` target 和 package language modes 已对齐 `.v6` |
| Swift Testing baseline | Done | `Tests/SparkleRecorderTests` 主要使用 `import Testing`, `@Test`, `#expect` |
| 录制边界拆分 | Mostly done | `RecordingEngineClient`, `LiveRecordingEngineClient`, `RawInputEvent`, `RecordingEventPipeline`, `RecordingSessionProcessor` |
| Event tap 启动反馈 | Done | `EventTapThread.startAndWait`, `RecordingEngineClient.start() -> Bool`, `Recorder.startRecording() -> Bool` |
| 高频录制缓冲 | Done | `RecordingEventBuffer`, `RecordingSessionProcessor`, `AsyncStream(bufferingNewest:)` |
| 播放普通 step 执行器 | Mostly done | `PlaybackStepExecutor` 和对应 Swift Testing |
| 播放失败证据纯值化 | Mostly done | `PlaybackFailureEvidence`, `PlaybackFailureEvidenceBuilder`, `PlaybackEvidenceClient`, `EvidenceClient.recordFailure` |
| 播放 run 状态机纯值化 | First pass done | `PlaybackRunStateMachine` owns generation, loop/progress snapshots, stale update rejection, and terminal `AutomationPlayerCompletion` mapping |
| 播放 live 执行 loop 边界 | First pass done | `PlaybackRunEngine` owns plan looping, window activation/refresh, conflict abort, progress throttling, failure evidence construction, and the async step-runner boundary used by `Player.play` |
| 播放 live locator/OCR step client | First pass done | `LivePlaybackRunStepClient` owns live wait/verify text, locator fallback, OCR-backed point resolution, event posting handoff, and uses `PlaybackLocatorCache` / `PlaybackLocatorCacheTests` for locator reuse semantics |
| 播放同步 CLI loop/step 边界 | First pass done | `PlaybackSynchronousRunEngine` owns blocking CLI plan looping, window activation/refresh, conflict abort, progress handoff, and failure evidence construction; `LivePlaybackSynchronousRunStepClient` owns blocking locator/OCR step execution |
| 播放期防锁屏/睡眠守卫 | Done | `PlaybackPowerAssertion` holds app-layer ProcessInfo + IOKit display/system idle assertions and refreshes local user activity during live and CLI playback |
| SwiftUI selection 重算收敛 | Done | `ActionGroupSelectionSnapshot` 和 `ActionGroupProjectionTests` |
| Automation Core contract | Done | `AutomationWorkflow`, `AutomationTask`, `AutomationTaskRun`, `AutomationDependency`, `AutomationOutcome`, `AutomationAction`, `AutomationRunState` and `AutomationContractTests` |
| Automation reducer/effects | Done | `AutomationReducer`, `AutomationReducerResult`, `AutomationEffect`, `AutomationReducerTests` |
| Automation projection/UI bridge | Done | `AutomationViewProjection`, workflow/task node/dependency edge/timeline projection types, `AutomationOverviewModel`, `AutomationMainView(runtimeHost:)` |
| Owner B adapter/persistence clients | Done | `AutomationEngineRuntime`, `AutomationRuntimeSession`, `AutomationEffectRunner`, `AutomationResourceArbiter`, `AutomationPlayerClient`, `LiveAutomationPlayerClient`, `LiveAutomationConditionEvaluatorClient`, `LiveAutomationRuntimeHost`, `AutomationSchedulerClient`, `AutomationRepositoryClient`, `AutomationRepositorySnapshotClient`, `.sparkrec_workflow` package codec, `AutomationOwnerBClientTests`, `AutomationEngineRuntimeTests`, `AutomationRuntimeSessionTests` |
| Multi-resource lease handoff | Done | `AutomationAction.resourceLeasesAcquired`, reducer batch lease handling, `AutomationEffectRunner` partial-acquire cleanup, reducer/Owner B tests |
| Runtime graceful shutdown | Done | `AutomationRuntimeSession.stop(at:)` cancels active runs through reducer/effects, `AutomationEffect.cancelPlayer`, lease release, cancelled run persistence tests |
| Condition evaluation context | Done | `AutomationEffect.evaluateCondition` carries upstream `previousOutcomes`; `AutomationConditionEvaluatorClient.contextual` handles previous outcome, injected external signal/manual approval providers, OCR test closures, OCR region coordinate spaces, `LiveAutomationRuntimeHost` provider injection, and app-layer frontmost window/content OCR context |
| Repository refresh state | Done | `AutomationRepositoryRefreshClient` and `AutomationRepositoryRefreshState` expose idle/loading/loaded/failed values with previous snapshot retention for Owner C |
| FlowGraph node actions | First pass done | `AutomationViewIntent.startTask` maps to `.manualStart`; active-run cancel emits `AutomationAction.cancelRun`; `AutomationViewIntent.moveTask` maps to `AutomationAction.moveTask`; reducer persists `AutomationTask.graphPosition` |
| Automation runtime app lifecycle | First pass done | `LiveAutomationRuntimeHost` is started by `MenuBarController`, restores `automations.json` workflows/run history through `AutomationRuntimeSession`, starts scheduler ticks, and consumes Player completion events |
| Automation authoring UI | First pass done | Main window Library/Automation workspace reads live runtime projection; Automation can create workflows, add `SavedMacro` tasks, add condition tasks, connect/delete dependencies, edit workflow/task/dependency fields, edit task schedule/condition parameters, dispatch manual starts/cancels, and expose external signal/manual approval sources through provider boundaries |
| Task run detail UI | Second pass done | `AutomationTaskInspectorView` now shows per-task run history through `AutomationTaskRunHistoryView`, including outcome reason, lifecycle timing, attempt number, execution chain ID, upstream count, evidence availability, and duration metadata without opening Player internals or evidence payloads |
| OCR region picker product UI | Second pass done | `AutomationTaskInspectorView` exposes Pick Text Region and Draw Region for OCR conditions; `AutomationOCRRegionEditorView` shows coordinate-space status, preview, numeric bounds micro-editing, clear action, multi-display hints, and window/content availability feedback; saves still go through reducer `upsertTask` |
| Workflow package UI | Second pass done | `AutomationWorkflowPackagePresenter` exposes `.sparkrec_workflow` save/open/share flows for selected-workflow and all-workflow packages, uses Owner B `AutomationWorkflowPackage` codec, prompts for duplicate workflow conflicts and missing local macro references, and imports through reducer `upsertWorkflow` actions |

## 后续增强

| Area | Status | Why It Matters |
| --- | --- | --- |
| Scheduler launch integration | Product hardening | workflow 级 scheduler 第一版已经通过 timer-driven `clockTick` 走 reducer；后续可评估 `NSBackgroundActivityScheduler` 或 login item，而不是当前 Owner B 阻塞项 |

## 当前可进入下一阶段的依据

当前底座已经足够开始 Automation Core 设计，因为：

- 宏模板已有 `SavedMacro`。
- 播放结果已有 `RunReport` / `PlaybackFailureEvidence` 基础。
- 播放和录制核心行为已有若干 pure clients，可继续向 reducer 注入。
- Swift Testing 已能快速覆盖 pure value 和 fake client。

现在可以继续推进真实产品化接线：live projection、manual task start/cancel、node move、workflow/task/dependency 第一版 authoring、schedule/condition 参数表单、task run history/evidence 解释层、OCR region picker 二版 polish、manual approval、external signal 来源、workflow package codec、workflow 导入/导出/分享 UI 和缺失宏提醒已经走 reducer/provider/repository 边界；Owner B 当前规划内的 player/resource/scheduler/condition/repository/runtime 边界已经有代码和测试落点，后续主要是产品硬化和发布级调度集成。

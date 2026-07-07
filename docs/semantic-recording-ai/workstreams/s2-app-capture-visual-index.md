# S2 App Capture And Visual Index

状态：active first pass; next unblocker is authorized live bundle evidence for S3/S4
Owner：App-edge capture / Vision index / recording bundle storage
并行对象：S0 Workflow Evidence Closure, S1 Contract/Core, S3 Review UX

S2 的任务是把一次用户录制生产成 `SemanticRecordingBundle` 可消费的真实证据：`.mov` 视频、event-aligned keyframes、OCR/视觉/AX observations、suppression 和本地 bundle storage。S2 不负责 Review UI，也不负责 CLI/AI 命令命名；这些分别属于 S3/S4。授权机器上的 live evidence capture 顺序维护在 [../15-s2-live-evidence-playbook.md](../15-s2-live-evidence-playbook.md)。

## Current First Pass

已完成：

- Core capture session contract: `SemanticRecordingCaptureSession`
- Fake-client tests: `SemanticRecordingCaptureTests`
- Core lifecycle/preflight gate: `SemanticRecordingLifecycle`
- Core capture target mapper: `SemanticRecordingCaptureTargetMapper`
- App-edge live session runner: `LiveSemanticRecordingSession`
- App-edge ordinary Recorder bridge: `SemanticRecorderBridge`
- Macro manifest semantic bundle link: `SavedMacro.semanticRecording`
- Settings SwiftUI preflight guidance panel: `SettingsPanel`
- Live suppression context provider: `LiveSemanticRecordingSuppressionContext`
- Debug-only live smoke command: `semantic-recording debug-smoke`
- Debug smoke evidence sidecar writer: `semantic-recording debug-smoke --evidence-sidecar`
- App-edge live client boundary: `LiveSemanticCaptureClient.live(bundleDirectory:)`
- Semantic recording permission preflight contract: `SemanticRecordingPreflight*`
- Semantic recording preflight app-shell projection: `SemanticRecordingPreflightPresentation`
- Semantic recording retention/deletion planner: `SemanticRecordingRetentionPlanner`
- Semantic recording retention settings policy mapper: `SemanticRecordingRetentionSettings`
- Semantic recording retention/deletion confirmation projection: `SemanticRecordingRetentionPresenter`
- Semantic recording retention cleanup preview projection: `SemanticRecordingRetentionCleanupPresenter`
- Semantic recording scheduled retention cleanup decision: `SemanticRecordingScheduledRetentionCleanupPlanner`
- Semantic recording suppression settings mapper: `SemanticRecordingSuppressionSettings`
- App-edge retention/deletion dry-run and file application: `RecordingBundleStore.applyRetentionPlan`
- App-shell manual retention cleanup review/confirmation: `SettingsPanel` -> `MenuBarController` -> `RecordingBundleStore.retentionCleanupPreview` / `applyRetentionCleanup`
- App-shell scheduled retention cleanup first pass: `AppState.semanticRecordingLastScheduledRetentionCleanupAt` -> `MenuBarController` -> `RecordingBundleStore.retentionCleanupPreview` / `applyRetentionCleanup`
- Capture-level suppression decision: `SemanticRecordingCaptureSuppressionDecision`
- Core frame/video redaction planner: `SemanticRecordingRedactionPlanner`
- Core playable macro text sanitization planner: `SemanticRecordingPlayableSanitizationPlanner`
- Macro playable sanitization summary: `MacroPlayableSanitizationSummary`
- App-edge redacted frame PNG renderer: `SemanticRecordingFrameRedactionRenderer`
- App-edge redacted `.mov` renderer: `SemanticRecordingVideoRedactionRenderer`
- App-edge redaction application hook: `RecordingBundleStore.applyRedactionPlan` / `applyRedactions`
- App-shell playback-preserving playable macro sanitization application: `MacroLibrary.applyPlayableSanitization` / `MenuBarController`
- Live finish redaction application: `LiveSemanticRecordingSession.finish`
- Core bundle sidecar merge semantics: `SemanticRecordingBundleSidecars` / `SemanticRecordingBundle.applyingSidecars`
- Core bundle directory identity policy: `SemanticRecordingBundleDirectoryIdentity`
- Core tolerant bundle load result and sidecar diagnostics: `SemanticRecordingBundleLoadResult` / `SemanticRecordingBundleSidecarLoadDiagnostics`
- Core bundle readiness audit: `SemanticRecordingBundleReadiness`
- App-edge artifact file audit: `SemanticRecordingArtifactFileAuditor`
- Read-only recording readiness CLI over fixture/explicit/default-root bundles: `recording readiness`
- Read-only saved macro semantic recording link audit: `workflow macros` / `recording macro-links`
- App-edge strict/tolerant bundle sidecar loader/catalog: `RecordingBundleStore.loadBundle` / `loadBundleTolerant` / `loadBundle(recordingID:)` / `listBundleCatalog`
- App-edge bundle store scratch-root tests: `RecordingBundleStoreTests`
- App-edge permission snapshot bridge: `SemanticRecordingPreflightClient.live`
- CLI-safe permission snapshot bridge: `SemanticRecordingPreflightClient.liveCommandLine`
- ScreenCaptureKit movie adapter skeleton: `ScreenCaptureKitMovieRecorder`
- ScreenCaptureKit keyframe PNG adapter skeleton: `ScreenCaptureKitFrameSource`
- ScreenCaptureKit live frame metadata/raw-frame stream skeleton: `ScreenCaptureKitLiveFrameSource`
- App-edge latest-frame ROI router/cropper first slice: `AutomationVisualLatestFrameRouter`
- App-edge polling/fake-detector dispatch first slice: `AutomationVisualPollingDispatcher`
- App-edge OCR routed-crop detector first slice: `AutomationVisualFrameDetectorClient.ocrText` / `AutomationVisualTextDetectorClient`
- App-edge feature-print / template-locator routed-crop detector first slices: `AutomationVisualFrameDetectorClient.featurePrintImage` / `AutomationVisualFeaturePrintClient` / `AutomationVisualImageLocatorClient`
- App-edge pixel routed-crop sampler first slice: `AutomationVisualFrameDetectorClient.pixelColor`
- App-edge region-diff routed-crop sampler first slice: `AutomationVisualFrameDetectorClient.regionDiff`
- Vision OCR frame indexer skeleton: `VisionRecordingIndexer`
- Window/AX metadata frame indexer skeleton: `SemanticRecordingFrameObservationIndexer`
- Suppression policy/producer skeleton: `SemanticRecordingSuppressionProducer`
- Bundle storage write/load/catalog first pass: `RecordingBundleStore`

当前 first pass 证明：

- fake movie client 可以生成一个 `RecordingVideoSegment`
- start / event / stop keyframes 可以按 `RecordingFrameReference` 写入 bundle
- `RecordedEvent` 会被映射到 `RecordingTimelineEvent` 和 AI-safe `RecordingSemanticEvent`
- keyframe-only 模式不会启动 movie recorder，也不会给 frame 写 `videoSegmentID`
- frame indexer 可以把 OCR observations 回填到同一个 bundle
- app-edge adapter 已按 macOS 15+ `SCRecordingOutput` / `SCScreenshotManager.captureImage` / `SCStreamOutput(.screen)` 路线编译通过；movie finish 会检查 `SCRecordingOutputDelegate` failure 并拒绝缺失或空 `.mov` 文件，避免把失败录制写成成功 segment；live frame stream skeleton 可产出 sample metadata，也可在 app-edge 提供 raw `CMSampleBuffer` frame wrapper 给后续 detector jobs；latest-frame image router/cropper first slice 可按 core route 裁剪 ROI；polling/fake-detector dispatch first slice 可跳过 stale frame 并等待 fresh frame；OCR routed-crop detector first slice 可用 fake text detector 或 live `VisionDetector` factory 评估 OCR text condition，并把命中文字框投回 watched region；feature-print routed-crop detector first slice 可用 fake distance 或 live `VNGenerateImageFeaturePrintRequest` / `computeDistance` factory 评估 image appeared/disappeared，写出 detector-native distance threshold evidence，并可注入 deterministic verifier 做 pixel/template similarity 复核；template locator first slice 可在 routed ROI 内滑动搜索模板小图，写出 locator similarity/threshold/local bounds，并把命中图案框投回 display region；existing live visual condition evaluator 也会在 image appeared/disappeared condition evidence 中写出 template locator similarity/threshold/local bounds；pixel routed-crop sampler first slice 可采样显式 point 或 selected-region center，默认 3x3 small-radius average，支持 0...8 `pixelSampleRadius`，并写出 sampled/target color、similarity threshold、sample radius/count evidence；region-diff routed-crop sampler first slice 可比较 baseline/current crop，写出 change score threshold evidence，并在 summary 与 `AutomationVisualDetectorResult.fields` 中报告 changed ratio / max delta / sample count；Accelerate/Metal production diff backend、runtime/live persistence 和 live evidence 仍是后续切片
- preflight evaluator 区分 blocking 和 degraded：Input Monitoring / Screen Recording 阻塞 playable events、movie、keyframes、OCR；Accessibility 降级 AX/window metadata
- preflight presentation maps ready / blocked / degraded results into app-shell status, issue rows and safe action intents without SwiftUI or System Settings side effects
- lifecycle gate 会在创建 capture session 前评估 preflight：blocking 不创建 session，degraded 返回给调用方但允许开始；权限补齐后 blocked start 可以重试
- live session runner 已把 PermissionCenter preflight、bundle directory creation、live ScreenCaptureKit/Vision capture client、core lifecycle 和 `RecordingBundleStore.write` 串成一个 app-edge internal entry point；blocking preflight 不创建 bundle directory
- app shell now checks `SemanticRecordingPreflightClient.live` before countdown when `semanticRecordingEnabled` is on; blocking preflight prevents starting, degraded preflight continues with an app status message, and the latest presentation is stored on `AppState`
- recording-start preflight now runs before closing the popover or starting countdown; blocked semantic recording opens the Settings preflight guidance instead of leaving the user with only a transient status message
- ordinary `Recorder` now has an experimental `semanticRecordingEnabled` feature-flag bridge: when enabled, it starts `SemanticRecorderBridge`, forwards flushed `RecordedEvent` batches into `LiveSemanticRecordingSession`, finishes semantic capture on normal stop, and cancels/removes the semantic bundle when the user discards a recording
- ordinary `Recorder` maps the frontmost `PlaybackSurface` into a semantic capture target before starting the experimental bridge, so the live client can prefer target-window capture by window id / app bundle / window title and fall back to display capture when no surface is available
- Settings exposes the non-default `Record visual evidence` switch for the experimental semantic recording path
- Settings now expands that switch into a SwiftUI preflight panel: it shows ready / blocked / degraded state from `SemanticRecordingPreflightPresentation`, renders next-step / evidence-impact / privacy-boundary decision rows, renders issue rows, can re-check permissions, and opens the exact System Settings pane for the affected permission through `MenuBarController`
- saved macro manifests now have an optional `semanticRecording` reference; when the experimental bridge finishes after a normal recording stop, `MenuBarController` attaches the semantic recording id, bundle-relative path, manifest-relative path and event count to the newly saved macro metadata
- `semantic-recording debug-smoke` 是 S2 调试入口：默认捕获显示器、写出 bundle directory 和 manifest path；它只做 live capture smoke，不提供 `recording show/frames/search` 等 S4 用户查询能力
- `semantic-recording debug-smoke --preflight-only` 是授权预检入口：使用 CLI-safe 系统权限快照，不创建 bundle directory，不触碰 ScreenCaptureKit，避免 CLI semaphore 等待 MainActor permission bridge 时卡住
- `semantic-recording debug-smoke --evidence-sidecar <path>` now writes a reviewed-capture sidecar draft for both blocked/preflight-only and finished smoke runs. The sidecar records command plan, capture target, permission snapshot, app-facing preflight guidance projection, bundle paths, in-memory counts, persisted bundle reload status, persisted counts, memory-vs-persisted count match/mismatch details, sidecar diagnostics, redaction indexes and remaining review notes so an authorized live machine can preserve S2 evidence without relying on terminal copy/paste; JSON/plain output also exposes the same preflight presentation plus persisted count check through `commandPlan`, `preflightPresentation`, structured `persistedBundleCountCheck` and a `persisted bundle count match` summary. It is evidence metadata, not product-evidence completion by itself
- live frame indexing now aggregates Vision OCR with window snapshot / focused AX element observations when the capture target resolves to a window and Accessibility is available; fake-client tests prove `.windowSnapshot` and `.axElement` observations validate inside `SemanticRecordingBundle`
- suppression production now has a pure rule layer for Secure Input, focused password fields, excluded apps/windows/domains, private regions and oversized artifacts; `LiveSemanticRecordingSession` can turn a suppression context into bundle records without exposing user-facing semantic recording yet
- capture-level suppression now has a pure decision layer: Secure Input, focused password fields, excluded apps/windows/domains and private regions require semantic visual capture to stop; retention-only oversized artifacts still produce suppression records without stopping the whole capture
- AI-safe text redaction now has a core first pass: suppression records for Secure Input, focused password fields, excluded targets, private regions, user deletion and unknown sensitive contexts redact matching `RecordingSemanticEvent` titles/summaries/evidence refs and matching OCR/AX/window observation text/artifact refs when the suppression points to an event, frame, exact time or time range
- playable macro text sanitization now has a pure planning first pass: `SemanticRecordingPlayableSanitizationPlanner` matches sensitive suppression records back to `RecordedEvent` indices through bundle timeline events and time ranges, identifies readable `unicodeString`, `textAnchor.text` and `behaviorGroupName` fields, produces an explainable plan with suppression ids/reasons/fallbacks, and can create an explicit sanitized event copy; `unicodeString` / behavior-name removal preserves keyCode-based playback, while text-anchor redaction is marked as requiring reviewed mutation before execution
- playback-preserving playable macro sanitization now has a save/export/status first pass: `MacroPlayableSanitizationSummary` records applied vs withheld/review-required readable fields, `MacroLibrary.applyPlayableSanitization` applies only keyCode-preserving `RecordedEvent` metadata removals after semantic bundle attachment, `MenuBarController` syncs the current recording buffer when needed, and text/script/file export paths reload macro events and apply the same playback-preserving subset before writing payloads. Review-required `textAnchor.text` mutation stays out of automatic save/export until S3 provides an explicit user-reviewed edit path
- localized frame/video redaction now has a pure planning layer: `SemanticRecordingRedactionPlanner` maps suppression records to deterministic frame masks and video time ranges; it prefers observation bounds, falls back to full-frame masks when only frame dimensions are available, ignores record-only oversized artifact suppression, and emits stable `redacted/frames/<frame-id>.png` refs for the later app-edge renderer
- app-edge redacted frame/video writing now has a first-pass renderer and live finish hook: `SemanticRecordingFrameRedactionRenderer` decodes source frame PNGs, clips masks to image bounds, fills masked areas and writes the planned `redacted/frames/<frame-id>.png` artifact; `SemanticRecordingVideoRedactionRenderer` uses macOS 15 AVFoundation async loading/export to overlay full-frame black masks over planned sensitive time ranges and write `redacted/video/<segment-id>.mov`; `RecordingBundleStore.applyRedactionPlan` writes `redacted/frames/index.json` and `redacted/video/index.json` sidecars, and `LiveSemanticRecordingSession.finish` applies the plan after bundle write before returning a successful finish result. `RecordingBundleStore.loadBundle` now reads the redacted frame/video indexes, Review projection defaults to redacted frame refs while preserving source refs, S4 frame payloads expose `effectiveImageRef` / `redactedImageRef`, and retention includes redacted frame/video artifacts; live product evidence remains open
- live suppression context ingestion now has a first pass: `Recorder` asks an app-edge context client at semantic start and on event flush, deduplicates repeated context fingerprints, sends safe changed contexts through `SemanticRecorderBridge` into `LiveSemanticRecordingSession.addSuppressions(for:)`, and suppresses the experimental semantic capture bridge before attaching a bundle when sensitive/excluded contexts are detected
- the live context client resolves the current frontmost capture target when possible, detects focused secure/password-like AX elements, derives a domain candidate from window titles, and reads exclusion rules from UserDefaults keys (`semanticRecordingExcludedApplicationBundleIDs`, `semanticRecordingExcludedWindowTitleFragments`, `semanticRecordingExcludedDomains`, `semanticRecordingMaximumArtifactByteCount`)
- Secure Input diagnostics now have a first pass: `EventTapThread` surfaces `tapDisabledByUserInput` through `RecordingEngineDiagnostic.eventTapDisabledByUserInput`, `LiveRecordingEngineClient` exposes it on a diagnostics stream, and `Recorder` turns it into a secure-input context that suppresses semantic visual capture while ordinary macro recording continues
- retention planning now has a pure policy layer that can retain protected/fresh recordings, prune expired artifact refs while preserving metadata files, or plan explicit full bundle deletion without touching the file system
- retention settings now have a first-pass pure policy mapper and Settings UI: `SemanticRecordingRetentionSettings` converts user-selected retention days and expired disposition into `SemanticRecordingRetentionPolicy`, `AppState` persists the settings in UserDefaults, and `SettingsPanel` exposes retention duration plus expired prune/delete behavior under the experimental visual evidence setting
- retention/deletion confirmation now has a pure presentation layer: `SemanticRecordingRetentionPresenter` turns retain/prune/delete plans into deterministic confirmation status, copy, artifact/preserved-metadata counts and destructive/keep actions without SwiftUI or file IO
- `RecordingBundleStore.applyRetentionPlan` can turn a retention plan into a dry-run preview or confirmed app-edge deletion: expired prune deletes only safe artifact files, preserves metadata paths, reports missing artifacts, rejects directory refs, and explicit delete removes the canonical bundle directory
- manual retention cleanup now has a first-pass app-shell flow: `SemanticRecordingRetentionCleanupPresenter` builds a deterministic preview from scanned plans, `RecordingBundleStore.retentionCleanupPreview` loads catalog bundles through the tolerant sidecar loader so one corrupt optional sidecar does not block cleanup scanning, `SettingsPanel` exposes Review cleanup under the experimental visual-evidence setting, and confirmation applies the preview through `RecordingBundleStore.applyRetentionCleanup`
- scheduled retention cleanup now has a first-pass app-shell flow: `SemanticRecordingScheduledRetentionCleanupPlanner` decides skip/run from retention settings, last-run time and a 24-hour default interval; `AppState` persists the last scheduled cleanup time; and `MenuBarController` runs existing preview/apply cleanup on launch when eligible. Live cleanup product evidence remains open
- user-facing suppression exclusions now have a first-pass app-shell settings path: `SemanticRecordingSuppressionSettings` normalizes app bundle IDs, window-title fragments, domains and max artifact bytes; `AppState` persists the fields through the same UserDefaults keys consumed by `LiveSemanticRecordingSuppressionContext`; and `SettingsPanel` exposes privacy exclusions plus a max-artifact selector under the experimental visual-evidence setting. Live product evidence for excluded-app/window/domain capture suppression remains open
- bundle loading now has a first-pass stable sidecar, identity and default-root path: strict `RecordingBundleStore.loadBundle` reads `manifest.json`, overlays `video/segments.json`, `frames/index.jsonl`, `timeline.jsonl`, `events.jsonl`, `ocr/observations.jsonl` and `suppressed.jsonl` when present, falls back to manifest data when a sidecar is missing, and enforces UUID directory name -> manifest id consistency for catalog/default-root paths; `RecordingBundleStore.defaultRootDirectory` exposes the App Support semantic recordings root for read-only CLI discovery; explicit `loadBundleTolerant` returns `SemanticRecordingBundleLoadResult` with loaded/missing/failed sidecar diagnostics and falls back to manifest data when an optional sidecar is corrupt, giving S2 cleanup and later S4 live catalog/search a degraded-but-readable path. `SemanticRecordingBundleTests` cover pure merge, directory identity and tolerant diagnostics semantics, `RecordingBundleStoreTests` cover real scratch-root manifest/sidecar writes, reload, catalog, default root and root confinement, and `SemanticRecordingReviewPresenter` consumes the full strict loader instead of `loadManifest`
- bundle readiness now has a pure audit layer plus app-edge artifact file evidence: `SemanticRecordingBundleReadiness` evaluates schema/reference validity, expected video/keyframe/timeline/AI-safe event presence, optional OCR/window/AX observation presence, frame-to-video alignment and redaction sidecar coverage for sensitive suppressions. `SemanticRecordingArtifactFileAuditor` checks manifest-declared video/frame/redacted/source/runtime/diff refs against the bundle directory and reports present/missing/empty/directory/unsafe status plus byte counts without opening image/video bytes. `semantic-recording debug-smoke` now reloads the just-written bundle from disk through `RecordingBundleStore.loadBundleTolerant(from:)`, reports persisted reload counts plus memory-vs-persisted count match/mismatch details and loaded/missing/failed sidecar diagnostics in sidecar, plain summary and JSON `persistedBundleCountCheck`, and runs readiness against that persisted bundle rather than the in-memory finish value; blocked/preflight-only smoke runs leave reload/readiness unset. `recording readiness <id> --json` exposes the same read-only audit for fixture, explicit-root, explicit bundle-path and default-root bundles, with artifact file evidence and the same `--require-ocr` / `--require-window-or-ax` gates. `workflow macros --json` now exposes `SavedMacro.semanticRecording`, and `recording macro-links --json` audits saved macro references against the selected/default recording root with bundle load diagnostics, readiness status, canonical relative path issues and artifact file evidence. Reviewers can use those flags when a live evidence gate must prove OCR or window/AX observations, rather than accepting a manifest-only video/keyframe smoke.
- semantic capture cancellation now stops the movie recorder without writing a misleading stop keyframe, marks the lifecycle finished, and asks the app-edge store to remove the temporary bundle directory
- `SemanticRecorderBridge` now cleans up the active live session before reporting start/record/finish failures, so partial capture artifacts are not attached to the saved macro after an error

尚未完成：

- 普通宏录制流程的默认 rollout 和 live 产品证据
- 在授权机器上实际运行 `semantic-recording debug-smoke --json` 并保留 live `.mov` / keyframes / bundle sidecar 作为产品证据
- live authorized evidence proving AX/window metadata snapshots on a real target window
- live product evidence for redacted frame/video consumption; first-pass AI-safe semantic/OCR text redaction, playback-preserving playable macro save/export/status sanitization, pure frame/video redaction planning, app-edge redacted frame PNG writing, app-edge redacted `.mov` rendering, live finish redaction application, Review/CLI redacted-frame preference and capture-level semantic suppression now exist, but live proof plus reviewed `textAnchor.text` mutation remain open
- live product evidence for user-facing exclusion rules suppressing semantic capture on real excluded apps/windows/domains
- live cleanup product evidence for manual and scheduled retention cleanup
- live evidence for the recording-start preflight guidance copy and Settings guidance panel
- frame-derived asset copy into `AutomationWorkflowDraftVisualAssets`
- S3 Review UI integration
- live bundle catalog/search/suggestion wiring for S4 after live bundle evidence exists

## Accepted S1 Contract Usage

S2 当前只消费 S1 已接受的 value model，不改变 schema 语义：

| S1 Type | S2 Usage |
| --- | --- |
| `SemanticRecordingBundle` | session finish 时组装 bundle |
| `RecordingVideoSegment` | movie recorder finish 后提供 duration/codec/fileType/frameSize |
| `RecordingFrameReference` | start/event/stop keyframes，携带 safe `imageRef` |
| `RecordingTimelineEvent` | 每个 `RecordedEvent` 一个 timeline entry |
| `RecordingSemanticEvent` | AI-safe click/input/scroll/wait/condition candidate summary |
| `RecordingVisualObservation` | Vision OCR indexer 回填 `ocrText` observations |
| `RecordingCapturePolicy` | 支持 default video+keyframes 与 keyframe-only |
| `RecordingArtifactRef` | movie/keyframe/store 全部使用 safe relative refs |
| `SemanticRecordingPreflightPolicy` | 根据 capture policy 和权限快照评估 blocking/degraded capabilities |

如果 S2 后续需要新的 provider metadata，先写入 `metadata` 或 provider fields；只有当 S1 schema 无法表达时，才向 S1 发起 interface request。

## App-Edge Boundaries

Core target:

- `SemanticRecordingCapture.swift`
- `SemanticRecordingCaptureTargetMapper.swift`
- `SemanticRecordingLifecycle.swift`
- `SemanticRecordingPreflightPresentation.swift`
- `SemanticRecordingRetention.swift`
- `SemanticRecordingRedaction.swift`
- `SemanticRecordingPlayableSanitization.swift`
- `SemanticRecordingSuppression.swift`
- `SavedMacro.swift` optional `MacroSemanticRecordingReference`
- session lifecycle
- pure `PlaybackSurface` -> `RecordingCaptureTarget` mapping for target-window recording
- preflight gating before capture session creation
- pure app-shell projection for ready / blocked / degraded preflight guidance
- pure retention/deletion planning for artifact refs and preserved metadata files
- pure retention settings mapping from user-selected days/disposition to `SemanticRecordingRetentionPolicy`
- pure retention/deletion confirmation presentation for retain/prune/delete plans
- pure retention cleanup preview aggregation for user-confirmed cleanup flows
- pure scheduled retention cleanup run/skip decision from settings, last-run time and minimum interval
- pure bundle directory identity validation for stable catalog/root id policy
- pure tolerant bundle load result and sidecar diagnostics for degraded stored-bundle reads
- pure suppression settings normalization for user-facing app/window/domain/max-artifact exclusion fields
- pure frame/video redaction planning from suppression records to masks and video ranges
- pure playable macro text sanitization planning from suppression records to readable `RecordedEvent` fields
- pure playable macro sanitization summary counts for applied playback-preserving fields and review-required readable anchors
- pure suppression rule evaluation and record construction
- pure capture-level suppression decision for sensitive/excluded contexts
- pure AI-safe semantic event and OCR observation text redaction for suppression-matched evidence
- event/frame/video alignment
- fake-client tests
- no ScreenCaptureKit / Vision / AX / file IO

App target:

- `ScreenCaptureKitSemanticCapture.swift`
- `SemanticRecordingFrameObservationIndexer.swift`
- `SemanticRecordingFrameRedactionRenderer.swift`
- `SemanticRecordingVideoRedactionRenderer.swift`
- `VisionRecordingIndexer.swift`
- `RecordingBundleStore.swift`
- `RecordingArtifactURL.swift`
- `LiveSemanticRecordingPreflight.swift`
- `SemanticRecorderBridge.swift`
- `LiveSemanticRecordingSession.swift`
- `LiveSemanticRecordingSuppressionContext.swift`
- `MenuBarController.swift` macro metadata attachment after semantic bridge finish
- `AppState.swift` semantic recording toggle and latest preflight presentation
- `SettingsPanel.swift` experimental semantic recording switch
- `SettingsPanel.swift` semantic preflight decision rows, issue rows, re-check action and Open Settings buttons
- `SettingsPanel.swift` semantic retention duration and expired disposition settings
- `SettingsPanel.swift` manual retention cleanup preview/confirmation action
- `AppState.swift` scheduled retention cleanup last-run persistence
- `main.swift` debug-only `semantic-recording debug-smoke`
- `main.swift` `semantic-recording debug-smoke --evidence-sidecar <path>` sidecar writing for blocked/preflight/finished smoke runs
- `main.swift` `recording readiness <id> --json` read-only readiness audit for fixture, explicit root/path and default-root bundle sources
- `main.swift` `recording macro-links --json` read-only saved macro -> semantic recording link audit
- `SemanticRecordingArtifactFileAudit.swift` artifact file evidence for manifest-declared refs without reading image/video bytes
- ScreenCaptureKit, Vision image loading, PNG writing, bundle directory writing
- PermissionCenter-based permission snapshot for app-edge preflight
- command-line permission snapshot for debug smoke preflight and live smoke startup
- frame observation aggregation: Vision OCR plus CoreGraphics window snapshot and AX focused-element metadata
- app-edge suppression ingestion through `LiveSemanticRecordingSession.addSuppressions(for:)`
- live suppression context provider for ordinary recording: frontmost capture target refresh, AX focused secure/password-field detection, window-title domain candidates and UserDefaults-backed exclusion rules
- `Recorder` suppression context handoff at semantic start and event flush with duplicate-context suppression before sending contexts to `SemanticRecorderBridge`
- `Recorder` capture-level suppression: sensitive/excluded contexts set `SemanticRecorderBridgeStatus.suppressed`, cancel/remove the active semantic bundle, keep ordinary macro recording running, and prevent stale active/finished bridge statuses from overriding the suppressed state
- `RecordingEngineClient.diagnostics` / `LiveRecordingEngineClient` Secure Input signal handoff from event-tap disabled-by-user-input into semantic suppression context
- app-edge retention application through `RecordingBundleStore.applyRetentionPlan`, defaulting to dry-run and using safe artifact path resolution before any file removal
- app-shell retention settings persistence through `AppState.semanticRecordingRetentionMaximumArtifactAgeDays` / `semanticRecordingExpiredDisposition`, with `semanticRecordingRetentionSettings` producing the core policy mapper for future cleanup flows
- app-shell scheduled retention cleanup through `MenuBarController.scheduleSemanticRecordingRetentionCleanupIfNeeded`, using the pure planner and the same sidecar-aware `RecordingBundleStore.retentionCleanupPreview` / `applyRetentionCleanup` path as manual cleanup
- app-shell suppression settings persistence through `AppState.semanticRecordingExcludedApplicationBundleIDsText` / `semanticRecordingExcludedWindowTitleFragmentsText` / `semanticRecordingExcludedDomainsText` / `semanticRecordingMaximumArtifactMegabytes`, with `semanticRecordingSuppressionSettings` producing the core exclusion mapper used by the live context provider
- app-edge frame/video redaction application through `RecordingBundleStore.applyRedactionPlan` / `applyRedactions`, defaulting to dry-run and writing redacted frame PNGs, full-frame redacted `.mov` range exports, `redacted/frames/index.json` and `redacted/video/index.json` when confirmed
- live finish redaction application through `LiveSemanticRecordingSession.finish`, which writes the bundle, computes the redaction plan, renders redacted frame PNGs and redacted video segments when needed, reports rendered frame/video count and pending video ranges in debug smoke, and treats redaction failure as finish failure with temporary bundle cleanup so an unredacted sensitive bundle is not attached as success
- redacted frame/video consumption through `SemanticRecordingBundle.redactedFrames` / `redactedVideos`, `RecordingBundleStore.loadBundle`, `SemanticRecordingReviewProjection`, Review/S4 artifact refs and retention planning, defaulting Review/CLI frame display to redacted refs while preserving source image refs for traceability
- app-edge full bundle loading through strict `RecordingBundleStore.loadBundle` and explicit `loadBundleTolerant`, merging persisted sidecars into the manifest, enforcing UUID directory id consistency, reporting loaded/missing/failed sidecar diagnostics for degraded reads, exposing `listBundleCatalog` for S4 explicit stored-bundle read-only CLI, exposing `RecordingBundleStore.defaultRootDirectory` for S4 default-root read-only CLI, feeding `recording readiness` so reviewers can audit loaded/default-root bundles without image/video bytes, feeding `recording macro-links` so saved macro references can be checked against the same root, and using `SemanticRecordingArtifactFileAuditor` so manifest refs are distinguished from real present/non-empty artifact files; product-ready live catalog still needs authorized live evidence, installed-app saved macro links and suggestion synthesis
- app-shell manual retention cleanup through `MenuBarController.semanticRecordingRetentionCleanupPreview` / `applySemanticRecordingRetentionCleanup`, using tolerant sidecar-aware bundle loading and a SwiftUI confirmation alert before deletion
- app-shell playback-preserving macro sanitization through `MenuBarController.applyPlayableSanitizationIfNeeded` and `MacroLibrary.applyPlayableSanitization`, using the sidecar-aware bundle loader to build a suppression-matched plan, withholding only playback-preserving readable metadata, updating the current recorder buffer, and preserving reviewed text-anchor mutation for S3 Review
- export-time playback-preserving macro sanitization through `MenuBarController` text/script/file export helpers, which load persisted macro events when manifests are event-light and apply the same sidecar-backed sanitization subset before writing payloads
- experimental ordinary Recorder bridge behind `UserDefaults.semanticRecordingEnabled`, keeping default legacy recording behavior unchanged until live evidence and UI guidance are ready
- macro manifest attachment through `SavedMacro.semanticRecording`, so S3/S4 can discover the bundle from a saved macro without reconstructing raw paths
- app-shell first-pass preflight gating before countdown/start: blocked semantic capture stops with a status message, degraded capture continues with a limited-context status, default legacy recording stays disabled unless the toggle is on
- recording-start guidance: semantic preflight runs before popover dismissal/countdown, and blocked starts open the Settings preflight panel with decision rows, issue rows and Open Settings actions
- frontmost `PlaybackSurface` capture target handoff into `Recorder.startRecording(semanticCaptureTarget:)`, giving ScreenCaptureKit enough identity to resolve a target window in the experimental ordinary recording path
- app-edge session orchestration: preflight -> bundle directory -> live capture client -> lifecycle -> store write
- app-edge cancellation/failure cleanup: cancel stops movie capture without writing a stop keyframe, and failed bridge operations ask the live session to discard the temporary bundle directory before reporting failure

SwiftUI:

- no direct Vision / ScreenCaptureKit / raw path construction in this pass
- S3 should consume bundle/store/presenter results later

## Live API Notes

`SCRecordingOutput` constraints from local SDK and Apple docs:

- macOS 15+ only
- one recording output per `SCStream`
- add recording output before `startCapture` to include first samples
- removing recording output or stopping capture ends the recording
- stream configuration updates while recording should be treated as recording-ending events

Current adapter follows the first-sample rule: `ScreenCaptureKitMovieRecorder.start` creates stream, creates `SCRecordingOutput`, calls `addRecordingOutput`, then starts capture.

`ScreenCaptureKitFrameSource` uses the same target resolver and writes PNG to the safe frame artifact ref requested by core.

`VisionRecordingIndexer` reads the stored frame PNG and emits normalized-frame OCR bounds. `SemanticRecordingFrameObservationIndexer` combines those OCR observations with window/AX metadata observations for window targets. This is enough for OCR query fixtures, target-window explainability and later frame-to-condition UI, but it is not a full pattern search system.

2026-07-07 visual Repeat-Until note: future runtime visual waiting should use ScreenCaptureKit `SCStreamOutput(.screen)` / `CMSampleBuffer` as the live sample source, not repeated `SCScreenshotManager.captureImage` calls, and not legacy `CGWindowListCreateImage` / `AVCaptureScreenInput`. The current `SCRecordingOutput` movie path remains the video evidence path; `ScreenCaptureKitLiveFrameSource` now compiles as a metadata/raw-frame stream skeleton for complete screen sample buffers, `AutomationVisualFrameRoute` resolves selected-region / target-window / full-display processing scope in pure core, `AutomationVisualLatestFrameRouter` can crop resolved ROI from the latest app-edge image frame with fixture tests, `AutomationVisualPollingDispatcher` can dispatch fresh routed crops to a fake/prototype detector while skipping stale frames, `AutomationVisualFrameDetectorClient.ocrText` can evaluate routed OCR crops through an injected fake detector or live `VisionDetector` factory, `AutomationVisualFrameDetectorClient.featurePrintImage` can evaluate routed image appeared/disappeared crops through an injected fake distance or live Vision feature-print factory plus optional deterministic verifier, and the optional `AutomationVisualImageLocatorClient` can run a fixture-safe sliding template search inside the routed ROI and map the local match back to display coordinates. `AutomationVisualFrameDetectorClient.pixelColor` can evaluate routed pixel color crops through fixture-safe configurable 0...8 radius sampling with sample radius/count fields, and `AutomationVisualFrameDetectorClient.regionDiff` can compare routed baseline/current crops with change score threshold evidence plus structured changed ratio / max delta / sample count fields. The remaining S2 slice is production live OCR/feature-print/pixel/region-diff evidence plus recorded crop precompute/cache, production multi-scale/full-window locator search, Accelerate/Metal production region diff, runtime/live persistence of region-diff fields, and Lab/display-profile color matching over this dispatch path. The product and detector split is documented in [../16-visual-repeat-until-design.md](../16-visual-repeat-until-design.md).

## Interface Requests

### To S0

S0 remains responsible for Workflow evidence audit maintenance and its strict live gate is now closed at 13/13. S2 does not need to wait for S0 to keep building fake-client capture boundaries, but S2 still must produce its own live `.mov` / keyframe / bundle product evidence before claiming semantic capture product trust.

Current ask:

- when S0 records live clips, keep sidecars explicit about App build/run source and evidence source so S2 can reuse the capture template for semantic recording product evidence later.

### To S1

No schema change request yet.

Potential future request:

- retention/deletion metadata may need a first-class bundle policy field after storage UX is designed.
- AX/window snapshots may need explicit observation payload fields if `RecordingVisualObservation.metadata` becomes too lossy.

### To S3

S3 first pass is now paused after fixture/stored Review, Run Detail opener, Bundle Health, Run Target provenance, Draft Preview handoff, materialized asset evidence and pixel color first passes. S2 is the next unblocker.

When S2 provides a live bundle directory, S3 should load through presenter/store boundaries rather than raw paths. The next S2 -> S3 handoff must include:

- a live bundle written by the ordinary Recorder bridge, not only a fixture or blocked preflight sidecar
- `SavedMacro.semanticRecording` metadata proving the saved macro can find the bundle
- `.mov`, keyframe PNG, timeline/event, OCR and window/AX sidecars that reload through `RecordingBundleStore.loadBundle`
- readiness diagnostics from the persisted bundle, preferably with `--require-ocr` and `--require-window-or-ax`
- product evidence that the installed app can open linked Macro Review from that saved macro

Until then, S3 should only maintain snapshots/action semantics when S1/S2 fields change. The S0-S4 final gap alignment is tracked in [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md).

### To S4

S4 fixture CLI is no longer blocked on S2, and S4 explicit stored-bundle/default-root read-only CLI now consumes S2 `RecordingBundleStore.loadBundle`, `loadBundleTolerant`, `listBundleCatalog`, `defaultRootDirectory`, `SemanticRecordingBundleReadiness` and `SavedMacro.semanticRecording` link references. S2 now has a first-pass UUID directory name -> manifest id consistency policy plus explicit tolerant load diagnostics/readiness/macro-link audit for catalog/default-root paths. S4 product-ready live catalog/search/suggestions should still wait for authorized live bundle evidence, installed-app saved macro links, artifact status and suggestion synthesis.

## Verification

Current targeted verification:

```bash
swift test --scratch-path .build-test-s2 --enable-swift-testing --disable-xctest --filter 'SemanticRecordingCaptureTests|SemanticRecordingPreflightTests|SemanticRecordingPreflightPresentationTests|SemanticRecordingLifecycleTests|SemanticRecordingSuppressionTests'
swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'SemanticRecordingDebugSmokeEvidenceTests'
swift build -Xswiftc -swift-version -Xswiftc 6
.build/debug/SparkleRecorder semantic-recording debug-smoke --duration 0 --json
.build/debug/SparkleRecorder semantic-recording debug-smoke --preflight-only --json
.build/debug/SparkleRecorder semantic-recording debug-smoke --preflight-only --json --evidence-sidecar /tmp/sparkle-s2-debug-smoke-evidence.md
.build/debug/SparkleRecorder semantic-recording debug-smoke --json --require-ocr --require-window-or-ax --evidence-sidecar /tmp/sparkle-s2-live-smoke.md
.build/debug/SparkleRecorder recording readiness checkout-demo --fixture checkout --require-ocr --require-window-or-ax --json
.build/debug/SparkleRecorder recording macro-links --require-ocr --require-window-or-ax --json
```

Observed status on 2026-07-06:

- `SemanticRecordingCaptureTests|SemanticRecordingPreflightTests|SemanticRecordingLifecycleTests|SemanticRecordingSuppressionTests`: 16 tests passed in an isolated S2 suppression patch tree; includes capture/session, preflight/lifecycle, and suppression producer coverage for Secure Input, password fields, excluded apps/windows/domains, private regions and oversized artifacts
- `SemanticRecordingRetentionTests`: 9 tests passed; covers protected/fresh retention, expired artifact prune planning with preserved metadata files, explicit bundle deletion planning, redacted artifact inclusion, pure retention confirmation presentation for prune/delete/protected states, retention settings -> policy mapping, and cleanup preview aggregation
- Swift 6 build after `RecordingBundleStore.applyRetentionPlan`: passed; app-edge dry-run/file-removal entry compiles with safe artifact path checks and directory-ref rejection
- `SavedMacroPreviewCacheTests`: 4 tests passed; includes semantic recording reference round trip and legacy manifest decode without the new field
- `swift build --target SparkleRecorderTests -Xswiftc -swift-version -Xswiftc 6`: passed after adding `SavedMacro.semanticRecording`
- `swift build --target SparkleRecorderCore -Xswiftc -swift-version -Xswiftc 6`: passed after adding `SemanticRecorderBridge.swift` to the app-edge side of the package
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after feature-flagged Recorder bridge and macro manifest attachment
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after app-shell semantic preflight gating and the non-default settings toggle
- `SemanticRecordingPreflightTests|SemanticRecordingPreflightPresentationTests|SemanticRecordingLifecycleTests`: 12 tests passed in an isolated S2 preflight presentation patch tree; includes ready / blocked / degraded app-shell guidance projection and lifecycle preflight behavior
- `SemanticRecordingCaptureTests|SemanticRecordingPreflightTests|SemanticRecordingLifecycleTests`: 14 tests passed; includes fake window/AX metadata observations attached to an event-aligned frame
- `SemanticRecordingCaptureTests`: 7 tests passed after adding capture target mapper coverage; includes window surface mapping and display fallback mapping
- `SemanticRecordingCaptureTests|SemanticRecordingLifecycleTests`: 13 tests passed after adding cancel cleanup coverage; includes cancel stopping movie capture without writing a stop keyframe and lifecycle rejecting later event writes after cancel
- Swift 6 build: passed
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after recording-start preflight guidance and the shared S4 CLI dispatch landed
- `SemanticRecordingCaptureTests|SemanticRecordingLifecycleTests|SemanticRecordingPreflightTests|SemanticRecordingPreflightPresentationTests|SemanticRecordingRetentionTests|SemanticRecordingSuppressionTests|SavedMacroPreviewCacheTests`: 30 tests passed after recording-start preflight guidance; covers capture/lifecycle/preflight/retention/suppression and saved macro semantic recording metadata
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after live suppression context provider, bridge handoff and Recorder ingestion
- `SemanticRecordingCaptureTests|SemanticRecordingLifecycleTests|SemanticRecordingPreflightTests|SemanticRecordingPreflightPresentationTests|SemanticRecordingRetentionTests|SemanticRecordingSuppressionTests|SavedMacroPreviewCacheTests`: 30 tests passed after live suppression context ingestion; tests cover the pure suppression producer and surrounding S2 contracts, while app-edge AX/UserDefaults detection is compile-verified pending live product evidence
- `RecordingEngineClientTests|DomainSendableTests|SemanticRecordingCaptureTests|SemanticRecordingLifecycleTests|SemanticRecordingPreflightTests|SemanticRecordingPreflightPresentationTests|SemanticRecordingRetentionTests|SemanticRecordingSuppressionTests|SavedMacroPreviewCacheTests`: 35 tests passed after Secure Input diagnostic stream wiring; includes fake diagnostic stream coverage and Sendable coverage for `RecordingEngineDiagnostic`
- `SemanticRecordingSuppressionTests`: 4 tests passed after adding capture-level suppression decisions; proves sensitive/excluded contexts stop semantic capture, while retention-only oversized artifacts do not stop the whole capture
- `SemanticRecordingCaptureTests|SemanticRecordingSuppressionTests`: 13 tests passed after adding AI-safe text redaction; includes a suppression-before-event case proving matched semantic input events and OCR observations are redacted while timeline/event alignment is preserved
- `SemanticRecordingRedactionTests|SemanticRecordingCaptureTests|SemanticRecordingSuppressionTests`: 16 tests passed after adding pure redaction planning; includes observation-bound frame masks, full-frame fallback masks, video time-range planning and record-only oversized artifact suppression being ignored by redaction plans
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after adding `SemanticRecordingFrameRedactionRenderer` and `RecordingBundleStore.applyRedactionPlan`; this compile-verified the app-edge PNG renderer/store hook before the later redacted `.mov` renderer slice landed
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after wiring `LiveSemanticRecordingSession.finish` to apply frame redaction plans after bundle write and extending debug-smoke JSON/plain output with redacted frame counts and pending video redaction counts
- `SemanticRecordingBundleTests`: 7 tests passed after adding `SemanticRecordingBundleSidecars`; the new test proves sidecars override manifest arrays while missing sidecars preserve manifest data
- `SemanticRecordingBundleTests`: 9 tests passed after adding bundle directory identity coverage; tests now prove sidecar override/fallback semantics plus UUID directory name -> manifest id mismatch rejection
- `SemanticRecordingBundleTests`: 11 tests passed after adding tolerant bundle load result/sidecar diagnostics; tests now prove corrupt optional sidecars can fall back to manifest data with stable diagnostics and Codable round trip
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after adding `RecordingBundleStore.loadBundle`, `loadBundle(recordingID:)`, `listBundleCatalog`, and switching `SemanticRecordingReviewPresenter` to the full sidecar-aware loader
- `RecordingBundleStoreTests`: 2 tests passed after adding scratch-root app-edge store coverage; tests prove `RecordingBundleStore.write` materializes manifest/sidecar files, `loadBundle` / `loadBundleTolerant` reload them, `listBundleCatalog` discovers the canonical UUID directory, and explicit bundle loads outside the configured root are rejected
- `semantic-recording debug-smoke --duration 0 --json`: route/error-envelope smoke passed without touching ScreenCaptureKit; live capture smoke still needs an authorized macOS 15+ machine
- `semantic-recording debug-smoke --preflight-only --json`: verified in an isolated S2 patch tree; it returned quickly without creating a bundle or touching ScreenCaptureKit. On this machine it exited 2 with Input Monitoring blocked, Screen Recording authorized and Accessibility degraded.
- `SemanticRecordingDebugSmokeEvidenceTests`: 3 tests passed after adding the pure debug-smoke evidence sidecar renderer and synthetic redaction rehearsal helper; covers finished bundle/redaction counts, blocked preflight issue capture, sidecar synthetic fields and deterministic synthetic suppression construction.
- `SemanticRecordingBundleReadinessTests|SemanticRecordingDebugSmokeEvidenceTests`: 8 tests passed after adding the pure bundle readiness audit and debug-smoke readiness summary/details/follow-ups; covers complete redacted fixture readiness, missing redaction sidecars, Codable issue round trip, keyframes-only policy, frame-to-video alignment, sidecar readiness policy/copy and issue detail/follow-up rendering.
- `SemanticRecordingCLITests|RecordingBundleStoreTests`: 23 tests passed after adding the S4 read-only `recording readiness` envelope and default-root source policy coverage; readiness payloads expose tolerant sidecar diagnostics, readiness status/issues/follow-ups and artifact availability without image/video bytes.
- `SemanticRecordingCLITests|AutomationWorkflowDraftTests`: 59 tests passed after adding saved-macro semantic recording link audit coverage; `workflow macros --json` preserves `SavedMacro.semanticRecording`, and `recording macro-links` payloads expose linked/unlinked counts, bundle load evidence, readiness status and next actions without image/video bytes.
- `SemanticRecordingArtifactFileAuditTests|SemanticRecordingCLITests|SavedMacroPreviewCacheTests|AutomationWorkflowDraftTests`: 67 tests passed after adding app-edge artifact file evidence and canonical macro semantic recording relative-path helpers; coverage proves present/empty/missing artifact file status, readiness artifact warnings, macro-link artifact warnings and `workflow macros --json` semantic reference projection.
- `SemanticRecordingDebugSmokeEvidenceTests`: 6 tests passed after adding persisted bundle reload evidence coverage; covers finished reload counts/sidecar diagnostics, structured memory-vs-persisted count check status/mismatches/Codable round trip, count match/mismatch rendering, blocked/preflight reload absence, Codable reload evidence round trip, readiness issue detail rendering and deterministic synthetic suppression construction.
- `.build/debug/SparkleRecorder semantic-recording debug-smoke --preflight-only --json --evidence-sidecar /tmp/sparkle-s2-debug-smoke-evidence.md`: verified on this machine after Swift 6 build. It exited 2 because Input Monitoring is denied, returned `evidenceSidecarPath` in the JSON payload, and wrote a 2206-byte blocked-preflight sidecar with command, permission snapshot, target, bundle count placeholders and review notes. The temporary sidecar was removed after verification.
- `SemanticRecordingBundleTests|SemanticRecordingRetentionTests|SemanticRecordingCLITests|SemanticRecordingRedactionTests`: 24 tests passed after adding `SemanticRecordingRenderedVideoRedaction`, redacted video sidecar merge/loading semantics, retention artifact refs and S4 artifact availability.
- targeted Swift test build compile-verified `SemanticRecordingVideoRedactionRenderer` with macOS 15 AVFoundation async `load(...)` and `export(to:as:)`; live redacted `.mov` artifact proof still requires an authorized recording bundle with a real segment.
- `SemanticRecordingPlayableSanitizationTests`: 3 tests passed after adding the pure playable macro sanitization planner; covers suppression time-range matching for keyboard readable text metadata, timeline event/frame matching for text anchors, playback-preserving vs reviewed-mutation fallback, and retention-only/unmatched suppressions not modifying playable text.
- `SemanticRecordingPlayableSanitizationTests|SavedMacroPreviewCacheTests`: 10 tests passed after wiring playback-preserving playable macro sanitization summaries and saved/exported macro application; covers playback-preserving sanitized event subsets, review-required text anchors, summary counts and manifest round-trip compatibility.
- `SemanticRecordingSuppressionTests`: 5 tests passed after adding first-pass user-facing suppression settings normalization; covers app/window/domain list parsing, de-duplication, max-artifact nil mapping and rule handoff to excluded-context suppression.
- `SemanticRecordingRetentionTests`: 11 tests passed after adding scheduled cleanup decisions; covers disabled retention skip, recent-run interval skip, eligible run decisions and Codable round trip for the scheduled decision.
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after wiring scheduled cleanup through `AppState` and `MenuBarController`.
- whole-worktree `swift build -Xswiftc -swift-version -Xswiftc 6`: passed after wiring playback-preserving playable macro sanitization through save/export/status paths.

## Next Tasks

Follow [../15-s2-live-evidence-playbook.md](../15-s2-live-evidence-playbook.md) for accepted filenames, sidecar content, non-accepted substitutes and S3/S4 handoff fields. Short form:

1. Run `semantic-recording debug-smoke --preflight-only --json --evidence-sidecar <sidecar.md>` locally before live capture to verify permissions and preserve blocked/degraded preflight evidence. Add `--synthetic-redaction` when you need the sidecar to record the requested safe redaction rehearsal reason.
2. Run `semantic-recording debug-smoke --json --require-ocr --require-window-or-ax --evidence-sidecar <sidecar.md>` on an authorized macOS 15+ machine and capture the resulting bundle directory plus sidecar as S2 live evidence. Then run `recording readiness <recording-id> --bundle-path <bundle-dir> --require-ocr --require-window-or-ax --json` against the preserved bundle to prove the S4/S2 handoff can audit the same artifacts. For safe-window redaction-pipeline rehearsal, add `--synthetic-redaction` or `--synthetic-redaction-reason <reason>`; this can prove the renderer path on non-sensitive content but does not replace password/Secure Input/excluded-context product evidence.
3. Capture product evidence for the Settings preflight panel and recording-start blocked/degraded guidance.
4. Run the `semanticRecordingEnabled` ordinary Recorder bridge on an authorized macOS 15+ machine and capture live bundle evidence, including `SavedMacro.semanticRecording` metadata, before making the feature user-visible. This is the main prerequisite for resuming S3 installed-app Review evidence.
5. Prove AX/window metadata observations in a live authorized `.mov` bundle before claiming product evidence.
6. Collect live product evidence for redacted frame/video consumption from password/Secure Input/excluded-context scenarios. AI-safe semantic/OCR text redaction, playback-preserving playable macro save/export/status sanitization, pure frame/video redaction planning, app-edge frame PNG writing, app-edge redacted `.mov` rendering, live finish redaction application and Review/CLI redacted-frame preference have first passes; reviewed `textAnchor.text` mutation remains a separate S3 Review product/security decision.
7. Capture live cleanup product evidence before broad rollout; manual Settings cleanup review/confirmation and scheduled launch-time cleanup wiring now have first passes.
8. After steps 2-5, hand the accepted live bundle path and macro metadata to S3 for installed-app linked Review -> Draft Preview product evidence. Do not ask S3/S4 to claim product readiness from fixture or explicit-path smoke evidence.

## Implementation Log

- 2026-07-06: Added `SemanticRecordingCaptureSession`, fake capture clients and `SemanticRecordingCaptureTests` to prove movie/keyframe/event alignment without real ScreenCaptureKit or Vision in unit tests.
- 2026-07-06: Added app-edge `LiveSemanticCaptureClient`, `ScreenCaptureKitMovieRecorder`, `ScreenCaptureKitFrameSource`, `VisionRecordingIndexer` and `RecordingBundleStore` skeletons. Build compiles against macOS 15+ ScreenCaptureKit APIs, but no live product evidence is claimed.
- 2026-07-06: Added `SemanticRecordingPreflight` value model/evaluator, live `PermissionCenter` bridge and `SemanticRecordingPreflightTests`; UI surfacing and ordinary `Recorder.swift` lifecycle wiring remain open.
- 2026-07-06: Added `SemanticRecordingLifecycle` and `SemanticRecordingLifecycleTests`; core now has an internal entry point that evaluates preflight before constructing the capture session, blocks Screen Recording/Input Monitoring failures without side effects, allows Accessibility-degraded capture, records/finishes through the wrapped session and supports retry after permissions change. Later S2 slices wired this through the ordinary Recorder bridge and Settings preflight panel.
- 2026-07-06: Added app-edge `LiveSemanticRecordingSession`; it evaluates live preflight before creating a bundle directory, constructs the live ScreenCaptureKit/Vision capture client only after preflight passes, delegates record/finish to `SemanticRecordingLifecycle`, and writes the finished bundle through `RecordingBundleStore`. This is an internal entry point for the next smoke/Recorder wiring slice, not live product evidence.
- 2026-07-06: Added `semantic-recording debug-smoke`; it starts `LiveSemanticRecordingSession`, records one synthetic event, finishes the bundle and prints JSON/plain output with bundle and manifest paths. Parser/error-envelope smoke is verified; real ScreenCaptureKit run is intentionally left as the next authorized-machine evidence step.
- 2026-07-06: Added CLI-safe preflight for `semantic-recording debug-smoke --preflight-only` and switched the debug smoke startup to `SemanticRecordingPreflightClient.liveCommandLine`, keeping App/UI `PermissionCenter` preflight on MainActor while avoiding CLI deadlock before live capture evidence is attempted.
- 2026-07-06: Added debug-smoke evidence sidecar output. `SemanticRecordingDebugSmokeEvidenceSidecar` renders pure markdown evidence metadata from the smoke payload, and `semantic-recording debug-smoke --evidence-sidecar <path>` writes command, preflight, capture target, bundle counts, redaction indexes and review notes for blocked, preflight-ready or finished runs. The sidecar is a capture helper, not automatic product-evidence completion.
- 2026-07-06: Added debug-smoke synthetic redaction rehearsal. `semantic-recording debug-smoke --synthetic-redaction` / `--synthetic-redaction-reason <redacting-reason>` can insert one explicitly synthetic suppression near the smoke event so authorized safe-window runs exercise the redacted frame/video sidecar pipeline without using real private content. The JSON/plain output and evidence sidecar report synthetic suppression count and reason; this remains a debug rehearsal helper, not live product evidence.
- 2026-07-06: Added `SemanticRecordingFrameObservationIndexer`, which aggregates Vision OCR with CoreGraphics window snapshots and focused AX element metadata for window targets. `LiveSemanticCaptureClient` now uses the aggregate indexer, and `SemanticRecordingCaptureTests` covers `.windowSnapshot` / `.axElement` observations in a validating bundle.
- 2026-07-06: Added `SemanticRecordingSuppressionProducer` and `SemanticRecordingSuppressionTests` for Secure Input, password fields, excluded apps/windows/domains, private regions and oversized artifacts. `LiveSemanticRecordingSession.addSuppressions(for:)` is the app-edge hook; live detection and user-facing rollout remain future S2 work.
- 2026-07-06: Added `SemanticRecordingPreflightPresentation` and tests so app-shell UI can render ready / blocked / degraded semantic recording guidance from the pure preflight result without duplicating permission semantics in SwiftUI. Actual app-shell wiring and System Settings opening remain the next S2 UI slice.
- 2026-07-06: Added `SemanticRecordingRetentionPlanner` and tests so S2 can produce deterministic retention/deletion plans from a bundle: retain protected/fresh recordings, prune expired artifact refs while preserving manifest/timeline/events/suppression index files, or plan explicit full bundle deletion. Confirmation UI and scheduled cleanup remain future S2 work.
- 2026-07-06: Added `RecordingBundleStore.applyRetentionPlan` as the app-edge retention application hook. It defaults to dry-run, reports planned/candidate/deleted/missing/preserved relative paths, deletes only safe non-directory artifact paths for prune plans, writes `.userDeleted` suppression sidecars for refs removed by confirmed prune cleanup so S4 can distinguish `deleted` from ordinary missing files, and can remove the canonical bundle directory for explicit deletion after confirmation. User-visible confirmation UI and storage-policy scheduling remain future S2 work.
- 2026-07-06: Added `SemanticRecordingRetentionPresenter` as the pure confirmation projection for retention/deletion plans. It distinguishes retained/protected recordings, expired artifact pruning and full bundle deletion, carries artifact and preserved-metadata counts, and marks prune/delete actions destructive while preserving a keep-recording fallback.
- 2026-07-06: Added first-pass retention settings. `SemanticRecordingRetentionSettings` maps selected artifact age days plus expired disposition into `SemanticRecordingRetentionPolicy`; `AppState` persists the setting; `SettingsPanel` exposes visual-evidence retention duration and expired prune/delete behavior.
- 2026-07-06: Added manual cleanup preview and confirmation first pass. `SemanticRecordingRetentionCleanupPresenter` filters and summarizes destructive plans, `RecordingBundleStore.retentionCleanupPreview` scans sidecar-aware stored bundles, and `SettingsPanel` asks before applying the cleanup through `RecordingBundleStore.applyRetentionCleanup`. Scheduled cleanup and live product evidence remain future S2 work.
- 2026-07-06: Added `SemanticRecorderBridge` and feature-flagged ordinary `Recorder` wiring. With `semanticRecordingEnabled` set, normal stop now finishes the semantic bundle through `LiveSemanticRecordingSession`, while discard/cancel asks the session to stop capture and remove the temporary semantic bundle directory. Default recording remains unchanged until S2 has live authorized evidence and preflight UI.
- 2026-07-06: Added `MacroSemanticRecordingReference` / `SavedMacro.semanticRecording` and `MenuBarController` attachment logic so a saved macro can point at its semantic bundle manifest after the experimental bridge finishes. `SavedMacroPreviewCacheTests` covers round-trip persistence and legacy manifest compatibility.
- 2026-07-06: Added app-shell preflight first pass for the experimental semantic recording toggle. `MenuBarController` now evaluates live semantic preflight before countdown, stores the pure presentation on `AppState`, blocks semantic recording before start when required permissions are missing, and allows degraded capture with a status message. `SettingsPanel` exposes the non-default `Record visual evidence` switch.
- 2026-07-06: Added `SemanticRecordingCaptureTargetMapper` and ordinary Recorder handoff so the experimental semantic recording bridge receives a target-window `RecordingCaptureTarget` derived from the frontmost `PlaybackSurface`, falling back to display capture when no surface is available. `SemanticRecordingCaptureTests` covers both mappings.
- 2026-07-06: Added first-pass Settings preflight guidance for the experimental semantic recording toggle. When enabled, `SettingsPanel` renders the pure preflight presentation, issue rows, a re-check action and permission-specific Open Settings buttons through `MenuBarController`.
- 2026-07-07: Added preflight decision rows to the same pure presentation and Settings panel. Ready, blocked and degraded states now render next-step, evidence-impact and privacy-boundary rows, and debug-smoke sidecars write the same decision rows so S2 live evidence review can see what the app told the user. This is S2 preflight UX evidence only; recording-start product clips remain open.
- 2026-07-06: Tightened semantic capture cancel/failure cleanup. `SemanticRecordingCaptureSession.cancel` and `SemanticRecordingLifecycle.cancel` stop movie capture without writing a stop keyframe, `LiveSemanticRecordingSession` removes temporary bundle directories on cancel/start failure, and `SemanticRecorderBridge` cancels the active session before reporting start/record/finish failure.
- 2026-07-06: Improved recording-start preflight UX. Semantic recording now checks permissions before closing the popover or starting countdown; blocked starts open the Settings preflight panel, while ready/degraded starts close the popover and continue into the existing countdown/recording path.
- 2026-07-06: Added first-pass live suppression context ingestion. `LiveSemanticRecordingSuppressionContext` builds app-edge contexts from the current capture target, AX focused password/secure-field hints, window-title domain candidates and UserDefaults exclusion rules; `Recorder` sends changed contexts through `SemanticRecorderBridge` into `LiveSemanticRecordingSession.addSuppressions(for:)`.
- 2026-07-06: Added first-pass Secure Input diagnostics. `EventTapThread` now reports disabled-by-user-input, `LiveRecordingEngineClient` publishes `RecordingEngineDiagnostic.eventTapDisabledByUserInput`, and `Recorder` converts the diagnostic into a secure-input suppression context for semantic recording.
- 2026-07-06: Added first-pass capture-level suppression. `SemanticRecordingSuppressionProducer.captureSuppressionDecision(for:)` identifies sensitive/excluded contexts that must stop semantic visual capture; `Recorder` checks this before bridge start and during event/diagnostic flush, cancels/removes the semantic bundle through `SemanticRecorderBridge.suppress`, keeps ordinary macro recording alive, and reports `SemanticRecorderBridgeStatus.suppressed` to the app shell.
- 2026-07-06: Added first-pass AI-safe text redaction inside `SemanticRecordingCaptureSession`. Suppression records now redact matched `RecordingSemanticEvent` titles/summaries/evidence refs and matched `RecordingVisualObservation` text/confidence/artifact refs for event, frame, exact-time and time-range matches; `SemanticRecordingCaptureTests` covers a future suppression window redacting a later text-input event and OCR observation.
- 2026-07-06: Added `SemanticRecordingRedactionPlanner` and `SemanticRecordingRedactionTests`. Core can now plan localized frame masks from observation bounds, fall back to full-frame masks when needed, plan video time ranges from suppression records, generate stable redacted frame refs, and leave file rendering to the app-edge layer.
- 2026-07-06: Added `SemanticRecordingFrameRedactionRenderer` and `RecordingBundleStore.applyRedactionPlan` / `applyRedactions`. App-edge code can now dry-run or confirmed-render planned redacted frame PNGs inside the bundle and write `redacted/frames/index.json`; redacted `.mov` range rendering landed in a later S2 slice.
- 2026-07-06: Added sidecar-aware bundle loading. Core `SemanticRecordingBundleSidecars` / `applyingSidecars` define the merge rule, `RecordingBundleStore.loadBundle` overlays persisted sidecars onto `manifest.json`, `listBundleCatalog` exposes catalog inputs, and `SemanticRecordingReviewPresenter` now opens full persisted bundles instead of manifest-only snapshots. S4 now uses these APIs for explicit stored-bundle read-only CLI; live product evidence remains future work.
- 2026-07-07: Added direct app-edge `RecordingBundleStoreTests` using a scratch root. The tests write the checkout bundle manifest/sidecars to disk, reload via strict/tolerant APIs, verify catalog discovery and verify explicit loads cannot escape the configured root. This closes the first-pass bundle-store checklist item without claiming live `.mov` or keyframe artifact production.
- 2026-07-06: Added tolerant bundle load diagnostics. Core `SemanticRecordingBundleLoadResult` / `SemanticRecordingBundleSidecarLoadDiagnostics` carry loaded/missing/failed sidecar evidence, while `RecordingBundleStore.loadBundleTolerant` falls back to manifest data when an optional sidecar is corrupt. Strict `loadBundle` still throws on corrupt sidecars, and retention cleanup preview now uses the tolerant path so one damaged optional sidecar does not block conservative cleanup scanning. Product-ready live catalog/search still remains gated on authorized live evidence and artifact status.
- 2026-07-06: Added pure bundle readiness audit. `SemanticRecordingBundleReadiness` checks whether a persisted bundle is ready for Review/AI consumption beyond raw schema validity: expected video/keyframes/timeline/AI-safe events, optional OCR/window/AX observations, frame-to-video alignment, and rendered redaction sidecars for sensitive suppressions. Debug-smoke finished payloads now include readiness policy, status, issue counts, issue details and follow-up actions after overlaying rendered redaction sidecars; `--require-ocr` and `--require-window-or-ax` let authorized live evidence review enforce OCR/window/AX observations when a gate requires them. This helps live evidence review but is not live evidence by itself.
- 2026-07-07: Hardened debug-smoke persisted bundle reload evidence, preflight guidance evidence and command handoff evidence. Finished smoke runs reload the just-written bundle through the tolerant sidecar loader before readiness evaluation, then report persisted counts plus memory-vs-persisted count match/mismatch details and loaded/missing/failed sidecar diagnostics in evidence sidecars, JSON `persistedBundleCountCheck` and plain output. Blocked/preflight-only paths explicitly show no persisted reload and `persistedBundleCountCheck.status=none`. JSON/plain/sidecar output now also carries `SemanticRecordingPreflightPresentation` status/title/actions/issue guidance plus a `commandPlan` with invocation, preflight and live-capture commands so recording-start guidance evidence can be reviewed without reconstructing app UI state and authorized machines can rerun the matching live smoke. `SemanticRecordingDebugSmokeEvidenceTests` now covers reload evidence Codable round trip, structured count mismatch status/mismatches, command plan Codable round trip, count mismatch rendering, preflight guidance rendering and absence/presence formatting.
- 2026-07-07: Aligned S2 with the S3/S4 pause. S3 first pass is now considered complete enough to wait for S2 live inputs, and S4 product-ready live catalog/search/suggestion remains blocked on the same evidence/root-policy path. S2 owns the next unblocker: an authorized live bundle plus ordinary Recorder bridge evidence that S3 can open through `SavedMacro.semanticRecording`. The cross-owner gap alignment lives in [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md).
- 2026-07-06: Added first-pass bundle directory identity policy. `SemanticRecordingBundleDirectoryIdentity` defines canonical recording-id directory names and rejects UUID directory names whose manifest id differs; `RecordingBundleStore` now uses it for canonical bundle directories, catalog filtering and sidecar-aware load paths. This stabilizes S2 root/id semantics without opening S4 product-ready live catalog yet.
- 2026-07-07: Added first-pass default root/id CLI handoff. `RecordingBundleStore.defaultRootDirectory` exposes the App Support semantic recordings root, default-source `recording list --json` reports that root, and loaded `recording show/explain/frames/...` commands fall back to loading by recording UUID from that root when no fixture or explicit source option is provided. This enables S4 default-root smoke and future accepted bundles without claiming product-ready live catalog/search.
- 2026-07-07: Added read-only `recording readiness` CLI handoff. The command uses tolerant bundle loading for fixture, explicit-root, explicit bundle-path and default-root sources, returns sidecar diagnostics plus `SemanticRecordingBundleReadiness` status/issues/follow-ups, artifact availability and artifact file evidence, and supports `--require-ocr` / `--require-window-or-ax` for strict S2 live-evidence review. This is an audit entry for future accepted bundles, not live product evidence by itself.
- 2026-07-07: Added read-only saved macro semantic recording link audit. `workflow macros --json` now carries `SavedMacro.semanticRecording`, and `recording macro-links --json` loads linked bundles through the selected/default recording root, reports tolerant sidecar diagnostics plus readiness status, canonical relative-path mismatches and artifact file evidence, and keeps unlinked/failed/not-ready states explicit. This prepares ordinary Recorder bridge evidence review without claiming live installed-app proof.
- 2026-07-07: Added app-edge artifact file audit and canonical saved-macro relative-path helpers. `SemanticRecordingArtifactFileAuditor` checks manifest-declared video/frame/redacted/source/runtime/diff refs for present/missing/empty/directory/unsafe status and byte counts without reading media bytes. `MacroSemanticRecordingReference.defaultBundleRelativePath/defaultManifestRelativePath` now centralizes the default root/id relative path used by `MenuBarController` and audited by CLI macro links.
- 2026-07-07: Hardened `ScreenCaptureKitMovieRecorder.finish` so delegate failures, missing `.mov` files and empty `.mov` files fail the capture instead of reporting a successful `RecordingVideoSegment`. Live `.mov` product proof still requires an authorized macOS 15+ run.
- 2026-07-06: Wired live finish frame redaction. `LiveSemanticRecordingSession.finish` writes the bundle, applies the redaction plan when non-empty, cleans up the temporary bundle on finish/write/redaction failure, returns the redaction result, and debug-smoke now reports redacted frame counts, the redacted frame index path and pending video range redaction count. Redacted `.mov` rendering landed in a later S2 slice.
- 2026-07-06: Wired redacted frame consumption. Core bundle state now carries `redactedFrames`, sidecar loading reads `redacted/frames/index.json`, Review projection/UI prefer redacted frame refs while preserving source refs, S4 frame payloads expose `effectiveImageRef` and `redactedImageRef`, and retention artifact planning includes redacted frame artifacts. Live product evidence remains future work.
- 2026-07-06: Added redacted `.mov` first pass. Core now carries `SemanticRecordingRenderedVideoRedaction` / `SemanticRecordingBundle.redactedVideos`, sidecar loading reads `redacted/video/index.json`, retention and Review/S4 artifact refs include redacted videos, `RecordingBundleStore.applyRedactionPlan` renders planned video range redactions through `SemanticRecordingVideoRedactionRenderer`, and debug-smoke reports redacted video count/index paths. The renderer uses macOS 15 AVFoundation async loading/export and full-frame black overlays for sensitive ranges; live product evidence remains open.
- 2026-07-06: Added pure playable macro text sanitization first pass. `SemanticRecordingPlayableSanitizationPlanner` maps sensitive suppression records back to `RecordedEvent` indices via timeline event ids, frame ids, exact times or time ranges, reports readable fields to withhold (`unicodeString`, `textAnchor.text`, `behaviorGroupName`), and can create an explicit sanitized event copy while marking whether the mutation preserves keyCode-based playback. Automatic application is intentionally limited to playback-preserving fields; reviewed text-anchor mutation remains future work.
- 2026-07-06: Wired playback-preserving playable macro sanitization into saved/exported macros. `MacroPlayableSanitizationSummary` records applied and review-required counts, `MacroLibrary.applyPlayableSanitization` updates persisted macro events and metadata after semantic bundle attachment, `MenuBarController` refreshes the current recording buffer and status copy, and text/script/file export helpers apply the same sidecar-backed playback-preserving subset before writing payloads.
- 2026-07-06: Added first-pass user-facing suppression exclusion settings. `SemanticRecordingSuppressionSettings` normalizes app bundle IDs, window title fragments, domains and max artifact bytes; `AppState` persists the editable text fields/options to the same UserDefaults keys used by `LiveSemanticRecordingSuppressionContext`; and `SettingsPanel` exposes Privacy exclusions under the experimental visual-evidence setting. Live product evidence for excluded app/window/domain suppression remains future S2 work.
- 2026-07-06: Added scheduled retention cleanup first pass. `SemanticRecordingScheduledRetentionCleanupPlanner` makes a pure run/skip decision from retention settings, last-run time and a default 24-hour interval; `AppState` persists the last scheduled cleanup time; and `MenuBarController` reuses the sidecar-aware `RecordingBundleStore.retentionCleanupPreview` / `applyRetentionCleanup` path on launch when cleanup is eligible. Live cleanup product evidence remains future S2 work.

# Parallel Workstreams

更新时间：2026-07-06
状态：并行工作边界草案
Owner：Semantic Recording program coordination

本文把 semantic recording 下一阶段拆成可并行推进的工作人物。目标不是开更多线，而是防止视频录制、视觉索引、Review UI、CLI/AI 和现有 Workflow 证据互相踩边界。

## Folder Status

当前 `docs/semantic-recording-ai/` 已经形成一个可开工的规划工作台：

| File | Status | Purpose |
| --- | --- | --- |
| `README.md` | Active index | 目录入口、愿景、Record & Replay 映射、现有 docs 链接 |
| `00-current-status.md` | Active snapshot | 当前能力、缺口、架构边界 |
| `01-video-recording-bundle.md` | Contract draft | `.mov`、keyframes、bundle shape、隐私和编辑支持 |
| `02-visual-understanding-and-patterns.md` | Contract draft | OCR、pattern、Vision 能力边界和补充技术 |
| `03-cli-ai-contract.md` | Contract draft | CLI-first AI 查询、suggestion、draft 输出 |
| `04-ux-application-knowledge.md` | Product plan | Review UX、AI cleanup、App Knowledge 长线 |
| `05-workflow-continuation-and-direction-review.md` | Direction review | Workflow 证据缺口如何接到 semantic recording |
| `06-current-work-and-next-tasks.md` | Execution ledger | 当前任务账本、立即顺序、过度设计审计 |
| `07-apple-api-implementation-path.md` | API feasibility | macOS 15+ `SCRecordingOutput` 默认视频路径、Vision/AX 路线 |
| `08-parallel-workstreams.md` | Work split | 本文件，并行 owner 和接口边界 |
| `09-template-baseline-preview-refs.md` | Accepted interface contract | S0 对 S1 的 source-frame/runtime-sample preview refs 需求；S1 已接受 first-pass core contract |
| `10-next-stage-reality-check.md` | Direction guard | 用户行为逻辑、剩余任务 P0-P4、过度设计审计、可行性和可维护性规则 |
| `11-user-logic-roadmap-and-scope-audit.md` | Direction guard | 从用户行为、剩余任务、动作词汇、CLI-first/MCP-deferred 和 App Knowledge later 角度审查下一阶段 |
| `12-remaining-work-and-direction-control.md` | Direction control | 当前剩余任务、P0-P4 队列、过度设计裁剪、可维护性规则和“做/不做”决策的一页式控制台 |
| `13-direction-decision-and-remaining-slices.md` | Direction decision | 本轮方向纠偏记录；按 Slice A-E 固定当前剩余任务、用户行为逻辑、过度设计边界和维护状态 |
| `14-s0-s4-final-gap-alignment.md` | Stage closeout / UI focus | S3 first pass 暂停后的 S0-S4 最终差距、S2 live-evidence blocker、验收姿态和后续 UI/UX owner 聚焦 |
| `workstreams/s0-workflow-evidence.md` | Active workstream | S0 当前任务、证据缺口、S1 接口请求和实施日志 |
| `workstreams/s1-contract-core.md` | Active workstream | S1 core schema v0、safe refs、timeline/events/suppression 和 preview comparison 合同 |
| `workstreams/s2-app-capture-visual-index.md` | Active workstream | S2 core session、app-edge ScreenCaptureKit/Vision/store/preflight skeleton、experimental Recorder bridge、Settings preflight panel、live suppression context ingestion、Secure Input diagnostics、capture-level suppression、AI-safe semantic/OCR text redaction、playback-preserving playable macro save/export/status sanitization、pure frame/video redaction planning、app-edge redacted frame PNG writing hook、app-edge redacted `.mov` renderer/store hook、live finish redaction application、Review/CLI redacted-frame preference、retention settings/manual cleanup/scheduled cleanup first pass、pure retention confirmation projection、macro metadata link 和 cancel/failure cleanup first pass；live product evidence、default rollout、redacted frame/video product evidence、reviewed text-anchor mutation 和 live cleanup product evidence 仍 open |
| `workstreams/s3-review-ux-evidence-editing.md` | Paused first pass / maintenance workstream | S3 fixture/stored Review timeline、before/after frame navigation、overlay/source-runtime projection、condition candidates、Run Detail opener、Draft Preview handoff、package-local materialization、Run Target provenance 和 pixel picking first pass 已完成；installed-app linked Review、frame-to-condition live evidence 和 Review -> Draft Preview live evidence 等 S2 live bundle 解锁 |
| `workstreams/s4-cli-ai-app-knowledge.md` | Active workstream | S4 fixture-first `recording` CLI、AI evidence query、suggestion、draft-from-recording 和 later App Knowledge；fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`、fixture/review-only `workflow draft from-recording`、explicit stored-bundle read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search` 和 explicit-source frame-region asset extraction 已实现，product-ready default/live root、stored suggestion synthesis、image-byte visual similarity 和 product-ready stored/live draft-from-recording 仍未实现 |
| `acceptance-checklist.md` | Acceptance | 只记录可验收事实，不把规划当完成 |

已接受的产品基线：

- 最低平台提升到 macOS 15+。
- 语义录制默认保存 `SCRecordingOutput` `.mov` 和 event-aligned keyframes。
- keyframe-only 只是未来轻量/隐私模式，不是默认路径。
- 不规划 macOS 14 `AVAssetWriter` fallback。
- AI 默认通过 CLI 查询本地索引，不默认读取完整视频。
- MCP 暂缓，未来只包装稳定 CLI/shared service。

## Workstream Overview

```text
S0 Workflow Evidence Closure
  -> proves current run evidence UI can be trusted

S1 Contract And Core Schema
  -> freezes bundle, ids, refs, timeline, suppression, query contracts

S2 App Capture And Visual Index
  -> implements ScreenCaptureKit video/keyframes, Vision/AX observations, storage

S3 Review UX And Evidence Editing
  -> makes video/keyframes usable: scrub, overlays, frame-to-condition, asset extraction

S4 CLI AI And App Knowledge
  -> exposes low-token queries, suggestions, draft generation and later app knowledge
```

S1 core schema v0 has a first pass. S2 core session/client spine, app-edge ScreenCaptureKit/Vision/store/preflight skeletons, experimental Recorder bridge, Settings preflight panel, recording-start guidance, live suppression context ingestion, Secure Input diagnostics, capture-level suppression, AI-safe semantic/OCR text redaction, playback-preserving playable macro save/export/status sanitization, pure frame/video redaction planning, app-edge redacted frame PNG writing hook, app-edge redacted `.mov` renderer/store hook, live finish redaction application, Review/CLI redacted-frame preference, sidecar-aware bundle loading/catalog, retention settings/manual cleanup/scheduled cleanup first pass, pure retention confirmation projection, macro metadata link and cancel/failure cleanup also have a first pass, so the next S2 work is live authorized product evidence, recording-start guidance evidence, redacted frame/video product evidence, reviewed text-anchor mutation and live cleanup product evidence, not more schema invention. S3 first pass is paused except for fixture/action-semantics maintenance until S2 provides accepted live bundle inputs. S4 now has fixture `recording list/show/explain/frames/frame show/events-near/ocr search/visual search/asset extract/asset baseline/suggest waits/conditions`, fixture/review-only `workflow draft from-recording`, explicit stored-bundle read-only `recording list/show/explain/frames/frame show/events-near/ocr search/visual search` and explicit-source frame-region asset extraction; product-ready default/live root, stored suggestion synthesis, image-byte visual similarity, product-ready stored/live draft-from-recording and MCP wrappers remain later after S2 live evidence/default root and S3 Review boundaries stabilize.

## S0 Workflow Evidence Closure

Purpose: close the existing Workflow evidence trust gap before semantic recording amplifies it.

Owns:

- live visual diagnostics Open/Reveal product evidence
- branch evidence real-run consistency product evidence, satisfied for strict audit by `live-branch-evidence-consistency.mov`; richer manual Run Detail drill-in can still be recaptured later
- macro evidence Reveal Report / Open Screenshot product evidence, satisfied for strict audit by `live-macro-evidence-open-reveal.mov`
- template/baseline preview refs design note
- authoring WYSIWYG product evidence status/history; task reorder live clip is done, drag-link remains optional/future

Does not own:

- new semantic recording bundle schema
- new ScreenCaptureKit recording implementation
- AI draft-from-recording logic

Deliverables:

- product evidence clips/screenshots linked from `workflow-page-productization/product-evidence/`
- updated `06-current-work-and-next-tasks.md` status
- S0 workstream updates in [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md)
- S1-facing template/baseline preview-ref request in [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md)
- checklist updates when a live-product item is truly proven

## S1 Contract And Core Schema

Purpose: define the versioned semantic recording truth that App, UI and CLI can share.

Owns:

- `SemanticRecordingBundle`
- `RecordingVideoSegment`
- `RecordingFrameReference`
- `RecordingTimelineEvent`
- `RecordingVisualObservation`
- `RecordingSuppressionRecord`
- safe relative artifact refs
- AI-safe `events.jsonl` and private `timeline.jsonl` payload contracts
- pure frame/event/video alignment helpers
- pure query result and suggestion value types
- fixture bundle shape for tests and UI prototypes

Does not own:

- live ScreenCaptureKit, Vision or AX calls
- filesystem mutation in core
- SwiftUI review screens
- natural-language model calls

Deliverables:

- core value types and Codable fixtures: first pass implemented in `Sources/SparkleRecorder/SemanticRecordingBundle.swift` and `Sources/SparkleRecorder/SemanticRecordingFixture.swift`
- tests for ID stability, path safety, schema versioning and event/frame/video alignment: first pass in `SemanticRecordingBundleTests`
- contract notes in `01-video-recording-bundle.md`, `03-cli-ai-contract.md`, [workstreams/s1-contract-core.md](workstreams/s1-contract-core.md) and `acceptance-checklist.md`

## S2 App Capture And Visual Index

Purpose: produce real semantic evidence from a user recording.

Owns:

- `LiveSemanticCaptureClient`
- `ScreenCaptureKitMovieRecorder`
- `ScreenCaptureKitFrameSource`
- `RecordingBundleStore`
- Vision OCR indexing through app-edge adapter
- AX/window metadata snapshots through app-edge adapter
- permission preflight and degraded-mode UX hooks
- suppression record production for sensitive or excluded evidence
- pure redaction planning from suppression records to frame masks and video ranges
- app-edge redacted frame PNG writing from redaction plans
- product evidence for live `.mov` + keyframe capture

Does not own:

- core schema semantics beyond accepted S1 contracts
- SwiftUI review layout decisions
- CLI command naming or AI prompt strategy
- reducer/workflow runtime semantics

Deliverables:

- pure `SemanticRecordingCaptureSession` and fake-client tests: first pass done in `SemanticRecordingCapture.swift` / `SemanticRecordingCaptureTests`
- app-edge ScreenCaptureKit/Vision/store skeletons and sidecar-aware bundle loading/catalog: first pass done in `ScreenCaptureKitSemanticCapture.swift`, `VisionRecordingIndexer.swift`, `RecordingBundleStore.swift`, `RecordingArtifactURL.swift` and `SemanticRecordingBundleSidecars`
- semantic recording preflight contract and live PermissionCenter bridge: first pass done in `SemanticRecordingPreflight.swift` / `LiveSemanticRecordingPreflight.swift`
- semantic recording frame/video redaction planner: first pass done in `SemanticRecordingRedaction.swift` / `SemanticRecordingRedactionTests`
- app-edge redacted frame PNG renderer/store hook, redacted `.mov` renderer/store hook, live finish application and Review/CLI redacted-frame preference: first pass done in `SemanticRecordingFrameRedactionRenderer.swift`, `SemanticRecordingVideoRedactionRenderer.swift`, `RecordingBundleStore.applyRedactionPlan`, `LiveSemanticRecordingSession.finish`, `SemanticRecordingReviewProjection` and S4 frame payloads; live product evidence remains open
- live smoke proving `.mov` plus event-aligned keyframes from the installed App on macOS 15+: adapter compiles; ordinary recording lifecycle wiring and live product evidence still open
- fake-client tests for alignment/indexing, storage and failure paths
- live app-edge smoke/product evidence
- updated `PermissionCenter`/capture docs if permissions or degraded modes change

## S3 Review UX And Evidence Editing

Purpose: turn recording evidence into something a user can inspect, correct and teach.

Owns:

- Macro Review video/keyframe timeline
- event row -> before/after frame navigation
- OCR/visual/AX overlay rendering
- frame region selection
- frame-to-condition UI
- image template, baseline and pixel sample extraction UI
- AI suggestion review affordances
- source-frame/runtime-sample comparison UX

Does not own:

- live Vision execution in view bodies
- raw file path construction
- bundle persistence semantics
- direct workflow reducer mutation outside accepted actions/intents

Deliverables:

- fixture-based Review UI first
- core review projection and fixture snapshot scenario: first pass implemented in `SemanticRecordingReviewProjection`, `SemanticRecordingReviewFixtureView` and `workflow product-evidence snapshot semantic-review-timeline`
- Macro Review / Run Detail first integration: `AutomationTaskRunDetailView` opens real bundle directories through `SemanticRecordingReviewPresenter`; Review shows available keyframe artifacts, source/runtime/diff refs, before/after frame chips and frame drag region selection
- frame-to-condition draft patch first pass: `SemanticRecordingReviewDraftPatchBuilder` generates review-only `AutomationWorkflowDraftPatchDocument` values with visual asset upsert ops before `addTask` / `setCondition`
- Draft Preview handoff first pass: Review-generated patches open `AutomationWorkflowDraftPreviewSheet` and import only through existing confirmed import callbacks
- pixel color picking first pass: Review renders `AutomationVisualColorPickerView` for `pixelMatched` candidates and passes user-reviewed `pixelColorHex` into draft patch generation
- product evidence screenshot/clip for frame-to-condition
- integration with existing `AutomationWorkflowDraftVisualAssets` and artifact presenters
- updated UX docs when review behavior changes

## S4 CLI AI And App Knowledge

Purpose: let AI and power users query local evidence cheaply and generate reviewable drafts.

Owns:

- `recording list/show/explain --json`
- `recording frames/frame show/events-near --json`
- `recording ocr search --json`
- `recording visual search --json`
- `recording asset extract/baseline --json`
- `recording suggest waits/locators/conditions/cleanup --json`
- `workflow draft from-recording --json`
- `sparkle.cli.result.v1` envelopes for recording commands
- low-token AI evidence selection policy
- later app knowledge grouping and natural-language composition

Does not own:

- direct writes to internal `.sparkrec_workflow`
- direct execution of generated workflows
- uploading complete video by default
- separate MCP-only logic path

Deliverables:

- fixture-backed `recording show` / `recording frames` / `recording frame show` / `recording events-near`: first pass done over `SemanticRecordingFixture.checkoutBundle()`, with `sparkle.cli.result.v1`, fixture-mode warning, evidence ids and safe artifact refs
- fixture-backed `recording ocr search` and deterministic `recording suggest waits/conditions`: first pass done over `SemanticRecordingFixture.checkoutQueryResults()` and `checkoutSuggestions()`, with OCR observation ids, bounds, confidence, safe refs, suggestion confidence/risk/fallback and review-only mutation policy
- fixture-backed and explicit stored-bundle metadata-only `recording visual search`: first pass done over persisted `RecordingVisualObservation` kind/label/text filters, with observation ids, bounds, confidence/score and safe refs
- explicit-source `recording asset extract` / `recording asset baseline`: first pass done over selected frame artifacts and caller-supplied regions, writing package-local PNG refs compatible with `AutomationWorkflowDraftVisualAssets`
- explicit stored-bundle read-only `recording list` / `recording show` / `recording explain` / `recording frames` / `recording frame show` / `recording events-near` / `recording ocr search` / `recording visual search`: first pass done through S2 `RecordingBundleStore` with `--recordings-root <path>` and `--bundle-path <dir>` source options; default/live root policy, stored suggestion synthesis and missing/deleted artifact status remain open
- CLI fixtures and transcript evidence
- deterministic local query/suggestion tests
- draft generation that still goes through validate/simulate/dry-run/import
- app knowledge only after several semantic bundles exist

## Parallel Sequence

Recommended order:

1. S0 records live Workflow evidence and closes the highest-risk trust gaps.
2. S1 freezes bundle v0 contracts and fixture bundle shape.
3. S2 runs macOS 15+ ScreenCaptureKit API spike against S1 draft contracts.
4. S3 builds Review UI against S1 fixtures, then swaps to S2 live evidence.
5. S4 first slice exposes fixture `recording show`, `frames`, `frame show` and `events-near` after S1 fixtures exist; this first slice is done.
6. S2 adds OCR/AX/visual observation production; S4 fixture OCR search, metadata-only visual search and deterministic suggestion query are done from fixture data, and explicit stored-bundle read-only queries consume the S2 sidecar-aware loader.
7. S3 ships frame-to-condition; S4 live suggestion commands should cite the same evidence refs after live bundle loading is stable.
8. App Knowledge remains future work until CLI explain/search/draft-from-recording are stable.

## Cross-Owner Rules

- Any schema or artifact-ref change starts in S1 and updates affected docs, tests and owner notes.
- S2 may add provider fields only behind versioned S1 contracts.
- S3 consumes projections and presenter results; SwiftUI does not run Vision, AX, ScreenCaptureKit or raw file IO.
- S4 consumes the same services as UI; it must not create a second private understanding of bundles.
- Every AI suggestion must cite frame/event/evidence IDs, confidence, risk and fallback.
- Every live capability needs fake-client tests first and product evidence before being marked complete.
- If a task cannot improve “录完能看懂、失败能解释、修正有证据、组合前可审阅”, it is not next-phase priority. Use [10-next-stage-reality-check.md](10-next-stage-reality-check.md) and [12-remaining-work-and-direction-control.md](12-remaining-work-and-direction-control.md) when a proposed task feels like MCP/App Knowledge/AI-agent overreach.
- Use [13-direction-decision-and-remaining-slices.md](13-direction-decision-and-remaining-slices.md) when deciding whether a remaining task belongs to Workflow trust, Review and Teach, live capture, CLI/AI collaboration, or workflow packaging/import boundaries.

## Next Target

From the current worktree, the next target should be:

```text
S2 authorized live bundle smoke + ordinary Recorder bridge evidence; S3/S4 product-ready live work resumes only after that evidence
```

Minimum accepted result:

- S1 bundle v0 contract remains green and fixture-backed through `SemanticRecordingFixture.checkoutBundle()`.
- S0 remains at 13/13 live-product evidence after visual diagnostics, macro evidence, branch consistency and task reorder clips; rerun strict audit if any product-evidence files change.
- S2 proves one authorized `.mov` plus event-aligned keyframes, OCR/window/AX observations where required, sidecar reload/readiness diagnostics and ordinary Recorder bridge `SavedMacro.semanticRecording` attachment.
- S3 stays in maintenance mode until it can open a real saved-macro-linked bundle from Run Detail without an open panel before claiming user-facing Review completion.
- S4 fixture OCR/visual/explain query, suggestion commands, fixture/review-only draft-from-recording and explicit stored-bundle read-only catalog/query/explain commands are done on top of S1 fixtures plus S2 sidecar-aware loader/catalog APIs; S4 product-ready default/live catalog still waits for authorized live bundle evidence, root/id policy, stored suggestion synthesis and artifact status surfacing.

That is enough to keep implementation moving without pretending the full AI/App Knowledge vision is already solved.

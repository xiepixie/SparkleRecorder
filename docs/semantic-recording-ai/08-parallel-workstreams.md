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

S1 and S2 may spike in parallel after this planning commit. S3 should begin with fixtures from S1 before depending on live capture. S4 should wait for bundle fixtures and stable query contracts before implementing user-facing commands.

## S0 Workflow Evidence Closure

Purpose: close the existing Workflow evidence trust gap before semantic recording amplifies it.

Owns:

- live visual diagnostics Open/Reveal product evidence
- branch evidence real-run consistency product evidence
- macro evidence Reveal Report / Open Screenshot product evidence
- template/baseline preview refs design note
- real drag/reorder or drag-link WYSIWYG product evidence

Does not own:

- new semantic recording bundle schema
- new ScreenCaptureKit recording implementation
- AI draft-from-recording logic

Deliverables:

- product evidence clips/screenshots linked from `workflow-page-productization/product-evidence/`
- updated `06-current-work-and-next-tasks.md` status
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

- core value types and Codable fixtures
- tests for ID stability, path safety, schema versioning and event/frame/video alignment
- contract notes in `01-video-recording-bundle.md`, `03-cli-ai-contract.md` and `acceptance-checklist.md`

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
- product evidence for live `.mov` + keyframe capture

Does not own:

- core schema semantics beyond accepted S1 contracts
- SwiftUI review layout decisions
- CLI command naming or AI prompt strategy
- reducer/workflow runtime semantics

Deliverables:

- API spike proving `.mov` plus event-aligned keyframes on macOS 15+
- fake capture clients for tests
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
5. S4 starts `recording show` and `recording frames` after S1 fixtures exist.
6. S2 adds OCR/AX observation production; S4 adds OCR search after fixture data exists.
7. S3 ships frame-to-condition; S4 ships suggestion commands that cite the same evidence refs.
8. App Knowledge remains future work until CLI explain/search/draft-from-recording are stable.

## Cross-Owner Rules

- Any schema or artifact-ref change starts in S1 and updates affected docs, tests and owner notes.
- S2 may add provider fields only behind versioned S1 contracts.
- S3 consumes projections and presenter results; SwiftUI does not run Vision, AX, ScreenCaptureKit or raw file IO.
- S4 consumes the same services as UI; it must not create a second private understanding of bundles.
- Every AI suggestion must cite frame/event/evidence IDs, confidence, risk and fallback.
- Every live capability needs fake-client tests first and product evidence before being marked complete.
- If a task cannot improve “录完能看懂、失败能解释、修正有证据、组合前可审阅”, it is not next-phase priority.

## Next Target

After the current commit, the next target should be:

```text
Phase 0 semantic recording contract + macOS 15 ScreenCaptureKit API spike
```

Minimum accepted result:

- S1 defines bundle v0 and fixtures.
- S2 proves one `.mov` plus event-aligned keyframes.
- S3 can open a fixture review timeline.
- S4 can run `recording show` / `recording frames` against a fixture bundle.

That is enough to start implementation without pretending the full AI/app-knowledge vision is already solved.

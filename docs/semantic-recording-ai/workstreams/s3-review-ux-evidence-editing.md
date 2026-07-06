# S3 Review UX And Evidence Editing

更新时间：2026-07-06
状态：Macro Review integration + Draft Preview handoff + pixel color picking + suggestion review first pass; live product evidence open
Owner：S3, Review UX / Evidence Editing
并行对象：S0 Workflow Evidence Closure, S1 Contract/Core, S2 App Capture/Visual Index, S4 CLI/AI

S3 的任务是把 semantic recording bundle 变成用户能审阅、修正和教学的界面。第一版不能等待 live capture 完成；必须先用 S1 fixture 证明 Review UX 的投影、事件导航、overlay、source/runtime comparison 和 suggestion review 逻辑成立。第二版已经把 Review 从 fixture 推到真实 Run Detail 入口和 live bundle presenter：用户可以从 Run Detail 打开一个 semantic recording bundle directory，审阅 frame timeline，框选 frame region，把候选生成 review-only workflow draft patch，并从 Review 直接进入 Draft Preview 走 existing confirm import。

## Scope

S3 owns:

- Macro Review frame strip and event timeline UI
- event row -> before/after frame navigation
- OCR / visual / AX overlay rendering decisions
- frame region selection UX
- frame-to-condition review flow for OCR wait, image appeared/disappeared, region changed and pixel matched
- image template, baseline and pixel sample extraction UI
- AI suggestion review affordances
- source-frame / runtime-sample / decision comparison UX

S3 does not own:

- live ScreenCaptureKit, Vision, AX or file IO providers
- semantic bundle schema changes without S1 request
- bundle persistence, retention or deletion policy
- direct workflow reducer mutation outside accepted actions/intents
- S4 CLI command naming or AI prompt strategy

## Current First Pass

已完成：

- Core review projection: `SemanticRecordingReviewProjection`
- Interactive Review UI: `SemanticRecordingReviewFixtureView`
- Live bundle presenter: `SemanticRecordingReviewPresenter`
- Frame-region to draft patch builder: `SemanticRecordingReviewDraftPatchBuilder`
- Workflow draft patch visual asset upserts: `upsertVisualRegion`, `upsertVisualImage`, `upsertVisualBaseline`
- Run Detail Macro Review entry: `AutomationTaskRunDetailView`
- Review patch -> Draft Preview -> confirm import handoff through the existing draft import path
- Pixel sample color picking UI for `pixelMatched` candidates
- Suggestion accept/reject local review state
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-timeline`
- Unit tests: `SemanticRecordingReviewProjectionTests`

当前 first pass 证明：

- `SemanticRecordingFixture.checkoutBundle()` 可以打开一个 Review timeline projection。
- 默认选中 recorded event，并能在同一 event row 暴露 before/after frame ids。
- 选中 wait frame 时，projection 暴露 OCR overlay、source preview ref、runtime watched-region sample、comparison decision、score/threshold、diff artifact ref。
- Suggestion rows 保持 review-only mutation policy，并引用 frame/event/observation/artifact evidence。
- Frame-to-condition 现在可以生成 `AutomationWorkflowDraftPatchDocument`：OCR region -> `ocrText`；image template -> `imageAppeared` / `imageDisappeared`；region baseline -> `regionChanged`；pixel sample -> `pixelMatched` when color evidence is supplied。
- Draft patch 先 upsert `AutomationWorkflowDraftVisualAssets` region/image/baseline refs，再 `addTask` 或 `setCondition`。测试会把 patch apply 到真实 `AutomationWorkflowDraftDocument`，不是只检查 UI 字符串。
- Review UI 可以从 app-edge presenter 加载 live bundle manifest，显示存在的 frame image artifact，Open/Reveal source/runtime/diff artifacts，并允许用户在 frame canvas 上拖拽生成 region selection。
- Review UI 的候选 patch 现在可以打开 `AutomationWorkflowDraftPreviewSheet`。用户确认前不会修改原 workflow；确认时复用既有 Draft Preview import path，并在已有 workflow 上覆盖 compiled id/createdAt，避免生成重复 workflow。
- Pixel candidates now expose `AutomationVisualColorPickerView` inside Review, and the selected hex is passed into `SemanticRecordingReviewDraftPatchRequest.pixelColorHex` so `pixelMatched` patches no longer require metadata-provided `colorHex` when the user supplies a reviewed target color.
- Suggestion rows now show evidence refs and explicit `Accept Patch` / `Reject` actions. `Accept Patch` jumps to the cited frame/event, resolves the matching condition candidate, and generates the same review-only draft patch path; `Reject` records local review state only and does not mutate the workflow.
- Run Detail 已提供 Macro Review 入口；由于 `AutomationTaskRun` 还没有 semantic recording id，当前入口是用户选择真实 bundle directory / `manifest.json`，不是自动绑定某一次 run。
- SwiftUI Review 只消费 presenter 解析好的 artifact statuses，不在 view body 内运行 Vision/AX/ScreenCaptureKit，也不自己拼 raw bundle paths。

尚未完成：

- 自动 run/macro -> semantic recording bundle id 绑定；这需要 S2/Recorder 把 recording id 写入可查询元数据。
- frame crop file copy / package materialization semantics；当前 patch 登记 safe refs，真实文件复制仍属于 app-edge presenter/package import 层。
- frame-to-condition live clip and real product evidence.
- image/baseline crop extraction UI still needs package-local file materialization before broad shipping.
- refreshed product evidence snapshot for suggestion review accept/reject; current shared worktree build is blocked by S2 `LiveSemanticRecordingSuppressionContext.swift`, so screenshot refresh waits for that compile issue to clear.

## Accepted S1 Contract Usage

S3 当前只消费 S1 已接受的 value model：

| S1 Type | S3 Usage |
| --- | --- |
| `SemanticRecordingBundle` | Review projection input |
| `RecordingFrameReference` | frame strip, selected frame, before/after navigation |
| `RecordingTimelineEvent` | event rows |
| `RecordingVisualObservation` | OCR/template/window/AX overlay rows |
| `RecordingSourcePreviewReference` | source-frame refs and frame-to-condition candidates |
| `RecordingRuntimeSampleReference` | runtime sample side of comparison |
| `RecordingPreviewComparison` | source/runtime/decision panel |
| `RecordingSuggestion` | review-only suggestion rows |
| `RecordingSuppressionRecord` | safety summary |

No S1 schema change request is active.

## Interface Requests

### To S1

No schema change request yet.

Potential future request:

- If frame-to-condition needs to preserve user-edited search regions separately from source crop bounds, S3 should request a first-class field or accepted metadata key before shipping import.

### To S2

S3 can keep developing against fixtures, and the first app-edge presenter is now in place. S2 still needs to provide the automatic association from ordinary macro recording / run detail back to a semantic bundle:

- recording id or bundle directory metadata that can be reached from `AutomationTaskRun`, `SavedMacro`, or a macro package manifest
- lifecycle timing that proves the bundle was written before Run Detail opens review
- product evidence for a live `.mov` / keyframe bundle opened through the installed app

SwiftUI should not receive raw bundle directory paths and construct file URLs itself. `SemanticRecordingReviewPresenter` is the accepted app-edge path for now.

### To S4

Suggestion review and CLI suggestions must cite the same frame/event/observation/source refs. S4 should not create separate evidence identifiers.

## Verification

Current targeted verification:

```bash
swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'SemanticRecordingReviewProjectionTests'
swift build -Xswiftc -swift-version -Xswiftc 6
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-timeline --output docs/workflow-page-productization/product-evidence/semantic-review-timeline.png
```

Observed status on 2026-07-06:

- `SemanticRecordingReviewProjectionTests`: 7 tests passed; coverage includes OCR wait patch, image appeared patch, visual asset upsert operations, manual frame region override and user-picked pixel color -> `pixelMatched` patch.
- Swift 6 build: passed.
- Product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-timeline.png` with sidecar `semantic-review-timeline.md`.

## Next Tasks

1. Add S2 automatic run/macro -> semantic bundle association so Run Detail can open the correct Review without an open panel.
2. Define frame crop file copy/package materialization semantics for package-local image/baseline refs.
3. Refresh `semantic-review-timeline.png` once the shared app build is green, so fixture product evidence shows suggestion evidence refs plus Accept Patch / Reject actions.
4. Capture live product evidence for frame-to-condition creation once a live bundle can be opened from the installed app.
5. Add product evidence for pixel color picking and the Review -> Draft Preview -> confirm import handoff from an installed-app bundle once automatic binding lands.

## Implementation Log

- 2026-07-06: Added `SemanticRecordingReviewProjection` and tests. The projection converts S1 fixture bundle values into frame strip rows, event rows with before/after frame ids, selected-frame overlays, source/runtime comparison rows, frame-to-condition candidates and review-only suggestion rows.
- 2026-07-06: Added `SemanticRecordingReviewFixtureView` and `semantic-review-timeline` product-evidence snapshot scenario. This is a fixture Review UI proof, not the final Macro Review integration.
- 2026-07-06: Added `SemanticRecordingReviewDraftPatchBuilder`, visual asset upsert patch operations, app-edge `SemanticRecordingReviewPresenter`, Run Detail Macro Review entry, frame drag selection and patch save flow. The original workflow remains review-only; generated patches can be saved and applied through the existing draft patch pathway.
- 2026-07-06: Connected Review-generated frame-to-condition patches to `AutomationWorkflowDraftPreviewSheet` and the existing confirmed import callback, preserving review-only behavior until the user explicitly imports.
- 2026-07-06: Added Review-side pixel color picking for `pixelMatched` candidates and a pure test proving user-picked color can generate and apply a valid pixel condition patch without metadata color evidence.
- 2026-07-06: Added suggestion review actions. Suggestions now expose cited evidence rows, `Accept Patch` to create a review-only patch from matching evidence, and `Reject` as a local non-mutating review decision.

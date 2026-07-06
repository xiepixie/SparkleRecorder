# S3 Review UX And Evidence Editing

更新时间：2026-07-07
状态：Macro Review integration + linked Run Detail opener + Draft Preview handoff + selected-region draft selection + Review action semantics / S4 evidence alignment first pass + Bundle Health / Run Target first passes done; live product evidence open
Owner：S3, Review UX / Evidence Editing
并行对象：S0 Workflow Evidence Closure, S1 Contract/Core, S2 App Capture/Visual Index, S4 CLI/AI

S3 的任务是把 semantic recording bundle 变成用户能审阅、修正和教学的界面。第一版不能等待 live capture 完成；必须先用 S1 fixture 证明 Review UX 的投影、事件导航、overlay、source/runtime comparison 和 suggestion review 逻辑成立。第二版已经把 Review 从 fixture 推到真实 Run Detail 入口和 live bundle presenter：Run Detail 会优先从 `SavedMacro.semanticRecording` 打开 linked Macro Review，缺少绑定时仍保留手动 bundle picker fallback。用户可以审阅 frame timeline，框选 frame region，把候选生成 review-only workflow draft patch，并从 Review 直接进入 Draft Preview 走 existing confirm import。

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
- Review visual asset materialization: `SemanticRecordingReviewAssetMaterializer`
- Review manual frame-crop extraction for image/template and baseline candidates
- Reviewed selected-region inspector and `Draft Selection` action
- Review action semantics vocabulary for S3/S4 evidence alignment
- Draft Preview visual asset provenance badges for Review-generated crops
- Review source/runtime/diff evidence drill-in tiles
- Review Bundle Health inspector for validation issues, artifact availability and suppression alignment
- Candidate-level `review.draftCandidate` / `review.draftSelection` action semantics before the user creates a patch
- Run Detail target explanation inside the opened Macro Review sheet
- Codable Run Target provenance evidence for S4/CLI summaries
- Run Detail Macro Review entry: `AutomationTaskRunDetailView`
- Run Detail Macro Review source-scope projection: `AutomationMacroReviewSourcePresentation`
- Run Detail linked Macro Review metadata and bundle Reveal action
- Review patch -> Draft Preview -> confirm import handoff through the existing draft import path
- Pixel sample color picking UI for `pixelMatched` candidates
- Suggestion accept/reject local review state
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-timeline`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-stored-bundle`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-missing-artifacts`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-run-detail`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-run-target`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-draft-preview`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-pixel-color`
- Product evidence snapshot scenario: `workflow product-evidence snapshot semantic-review-materialized-actions`
- Unit tests: `SemanticRecordingReviewProjectionTests`

当前 first pass 证明：

- `SemanticRecordingFixture.checkoutBundle()` 可以打开一个 Review timeline projection。
- 默认选中 recorded event，并能在同一 event row 暴露 before/after frame ids。
- 选中 wait frame 时，projection 暴露 OCR overlay、source preview ref、runtime watched-region sample、comparison decision、score/threshold、diff artifact ref。
- Suggestion rows 保持 review-only mutation policy，并引用 frame/event/observation/artifact evidence。
- Frame-to-condition 现在可以生成 `AutomationWorkflowDraftPatchDocument`：OCR region -> `ocrText`；image template -> `imageAppeared` / `imageDisappeared`；region baseline -> `regionChanged`；pixel sample -> `pixelMatched` when color evidence is supplied。
- Draft patch 先 upsert `AutomationWorkflowDraftVisualAssets` region/image/baseline refs，再 `addTask` 或 `setCondition`。测试会把 patch apply 到真实 `AutomationWorkflowDraftDocument`，不是只检查 UI 字符串。
- Review UI 可以从 app-edge presenter 加载 live bundle manifest，显示存在的 frame image artifact，Open/Reveal source/runtime/diff artifacts，并允许用户在 frame canvas 上拖拽生成 region selection。
- Frame canvas 上的 reviewed region selection 现在会在 inspector 中显示 candidate kind、frame id、surface id 和 bounds；`Draft Selection` 会把该 selection 作为 `SemanticRecordingReviewDraftPatchRequest.regionSelection` 传入 frame-to-condition builder，清除按钮只清本地 selection/draft 状态，不修改 workflow。
- Source / Runtime comparison rows now render Source / Runtime / Diff evidence tiles. In fixture mode they expose the safe refs inline; when opened from a real bundle state they show available/missing status and image thumbnails from presenter-resolved artifact URLs before the user opens or reveals files.
- `semantic-review-stored-bundle` product evidence now persists the checkout bundle manifest and its PNG artifact refs under `fixture-semantic-review-stored-bundles/<recording-id>/`, then renders `SemanticRecordingReviewFixtureView(state:)` with a real bundle directory and artifact status map. This proves file-backed Available thumbnails and candidate artifact affordances without claiming live capture or writing a fake `.mov`.
- `semantic-review-missing-artifacts` product evidence now persists the checkout bundle manifest and frame PNGs while intentionally omitting source/runtime/diff/candidate artifact files. This proves Review keeps the safe refs visible as `Missing file`, explains why Open/Reveal is unavailable, and treats retention/sidecar gaps as evidence status rather than silently hiding the refs.
- Stored bundle Review now surfaces `Bundle Health` before Teach/Draft actions: validation status, Available/Missing artifact counts, suppression count and suppression detail are visible in the same inspector where users accept suggestions or create draft patches. The stored-bundle fixture intentionally has one missing `.mov` artifact because it does not fake live video; the missing-artifacts fixture proves the larger missing-ref path.
- Teach System candidates now show `review.draftCandidate` or, when a reviewed frame region is active, `review.draftSelection` before the user presses `Draft Patch`. The visible action row cites the same frame/source preview/source artifact/bounds evidence that S4 `reviewActions` and `reviewActionPresentations` use, so the product surface no longer hides candidate mutation semantics until after a patch is staged.
- Review UI 的候选 patch 现在可以打开 `AutomationWorkflowDraftPreviewSheet`。用户确认前不会修改原 workflow；确认时复用既有 Draft Preview import path，并在已有 workflow 上覆盖 compiled id/createdAt，避免生成重复 workflow。
- Pixel candidates now expose `AutomationVisualColorPickerView` inside Review, and the selected hex is passed into `SemanticRecordingReviewDraftPatchRequest.pixelColorHex` so `pixelMatched` patches no longer require metadata-provided `colorHex` when the user supplies a reviewed target color.
- `semantic-review-pixel-color` fixture snapshot now layers a deterministic pixel sample on the checkout confirmation frame and renders the real Review inspector with selected `#2BC66A`, a `Wait for pixel color` candidate and a staged `pixelMatched` draft patch. This proves the pixel color picking affordance in fixture product evidence while live installed-app sampling remains open.
- Suggestion rows now show evidence refs and explicit `Accept` / `Reject` actions. `Accept` jumps to the cited frame/event, resolves the matching condition candidate, and generates the same review-only draft patch path; `Reject` records local review state only and does not mutate the workflow. Review decisions now show accepted/rejected status, cited evidence, staged patch operation, Draft Preview import boundary and an Undo control; rejecting or undoing the accepted suggestion clears the staged draft patch if that patch came from the same suggestion.
- Review actions now have explicit semantics through `SemanticRecordingReviewActionSemantics`. `review.acceptSuggestion`, `review.rejectSuggestion`, `review.draftCandidate`, `review.draftSelection`, `review.previewDraft` and `review.importDraft` carry a mutation boundary and evidence alignment. The S3/S4 alignment tests compare the shared `RecordingSuggestion` fixture evidence consumed by S4 with S3 Review action evidence refs, and now also generate Codable Review action semantics directly from raw `RecordingSuggestion` values so S4 can surface the same action names without depending on SwiftUI projection rows.
- Review suggestion rows now render the same action contract before the user acts: `review.acceptSuggestion`, `review.rejectSuggestion` and `review.clearDecision` are shown next to the shared evidence refs and mutation boundaries. This keeps S3 Review and S4 `reviewActions` JSON aligned in the product surface, not only in pure tests.
- S3 now exposes `SemanticRecordingReviewActionPresentation`, the same row model used by Review UI for action name, mutation boundary, mutation effect, suggestion/frame/observation/artifact/bounds evidence. This lets S4 display or summarize Review actions without inventing a second evidence vocabulary.
- Run Detail 已提供 Macro Review 入口；如果当前 run 或 task 能解析到带 `SavedMacro.semanticRecording` 的 macro，`AutomationTaskRunDetailView` 会直接通过 `SemanticRecordingReviewPresenter.reviewState(from:)` 打开 linked bundle。缺少该 metadata 或打开失败时，用户仍可以手动选择真实 bundle directory / `manifest.json`。
- Run Detail 的 Review source/scope now comes from `AutomationMacroReviewSourcePresentation` instead of ad hoc SwiftUI conditionals. The projection resolves direct `AutomationTaskRun.macroID` and workflow task macro fallback, exposes saved-macro vs manual bundle source, keeps `Scope: Macro-level` separate from `Run: Not bound`, and is covered by `AutomationViewProjectionTests`.
- Run Detail 的 linked Macro Review 区现在会在打开前显示 recording id、event count、captured date 和 manifest ref，并通过 `SemanticRecordingReviewPresenter.revealBundle(from:)` 提供 Reveal Linked Bundle 操作。SwiftUI 仍不直接拼 App Support 路径；路径解析留在 presenter。
- Run Detail -> Macro Review now computes an initial review target from `AutomationTaskRun` plus the loaded bundle before presenting the sheet. Failed runs prefer the exact `recordedEventIndex`, fall back to the nearest recorded event when older reports use a shifted index, and timeout / condition-not-matched runs open on condition-candidate evidence. This is still macro-level targeting, not a per-run semantic recording id.
- Opened Macro Review sheets now show a `Run Target` inspector block when they come from Run Detail. The block explains why Review selected the initial event/frame, including failed event, nearest-event fallback, condition evidence, first-event and timeline fallback reasons, so users do not see a preselected frame without provenance.
- `semantic-review-run-detail` fixture snapshot 现在会把带 `SavedMacro.semanticRecording` 的 `Upload report` macro 注入 Run Detail，证明 linked Macro Review metadata、Open/Reveal/manual bundle controls 在真实 Workflow inspector surface 中可见。
- `semantic-review-run-target` fixture snapshot renders the opened Macro Review state with `Run Target` context for a failed run, proving the target explanation is visible before Teach/Draft actions.
- Review -> Draft Preview 现在会把 image/template 和 baseline 候选引用的 semantic bundle artifact 复制到 app-managed `ReviewVisualAssets/<digest>/assets/images|baselines`，并把 patch 中的 `visualAssets.images/baselines.path` 重写成 package-local safe refs。确认导入后，既有 `AutomationMainContentView.importWorkflowFromDraftPreview` 会把该 package directory 写入 visual asset package-root manifest，而不是把 workflow 绑定到可能被 retention 清理的 semantic bundle。
- 当用户在 Review frame 上手动画框并生成 image/template 或 baseline condition 时，`SemanticRecordingReviewDraftPatchResult.assetExtractions` 会记录从 source frame image 裁剪的计划；`SemanticRecordingReviewPresenter` 在打开 Draft Preview 前用 ImageIO/AppKit 从 frame PNG 裁出新的 package-local PNG，并用裁剪后的 bytes 计算 SHA-256。`AutomationWorkflowDraftVisualImageAsset` 也会保留 source frame id、surface id、source artifact path、crop bounds 和 bounds space，方便之后做 evidence drill-in。
- Draft Preview 的 visual asset rows 现在会把 Review-generated crop 的 frame id、crop bounds、source artifact、surface 和 hash 摘要显示成 provenance badges。用户确认 import 前可以看到 image/template 或 baseline 资产来自哪一帧、哪块区域，而不是只看到 package-local path。
- `semantic-review-draft-preview` fixture snapshot 现在会从 checkout bundle 生成 `imageAppeared` review patch、apply 到真实 draft document，并渲染 `AutomationWorkflowDraftPreviewSheet`，证明 provenance badges 出现在确认 import 前的真实 Draft Preview surface。
- `semantic-review-materialized-actions` fixture snapshot 现在会渲染真实 Macro Review inspector，证明 Draft Preview handoff 后 `review.previewDraft` / `review.importDraft` rows 显示 source artifact、package-local artifact、SHA-256 digest、draft task/condition 和 visual asset key，而不是只停留在原 bundle ref。
- SwiftUI Review 只消费 presenter 解析好的 artifact statuses，不在 view body 内运行 Vision/AX/ScreenCaptureKit，也不自己拼 raw bundle paths。

尚未完成：

- 完整 run/session -> semantic recording evidence drill-in；当前已支持 `SavedMacro.semanticRecording` 的 macro 级 linked opener，并会按当前 run outcome 选择初始 Review event/frame，但还没有每次 workflow run 的独立 semantic recording id / run evidence id。
- frame-to-condition live clip and real product evidence.
- installed-app product evidence for linked Run Detail opener, suggestion accept/reject and Review -> Draft Preview remains open; current proof is fixture product evidence plus compiled product wiring.

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

S3 can keep developing against fixtures, and the first app-edge presenter is now in place. S2 has provided the first ordinary macro association through `SavedMacro.semanticRecording`; S3 now consumes it from Run Detail. S2 still needs to provide stronger run/session association and live acceptance evidence:

- recording id or bundle directory metadata that can be reached from each `AutomationTaskRun`, not only the saved macro
- lifecycle timing that proves the bundle was written before Run Detail opens review
- product evidence for a live `.mov` / keyframe bundle opened through the installed app

SwiftUI should not receive raw bundle directory paths and construct file URLs itself. `SemanticRecordingReviewPresenter` is the accepted app-edge path for now.

### To S4

Suggestion review and CLI suggestions must cite the same frame/event/observation/source refs. S4 should not create separate evidence identifiers.

Current accepted vocabulary:

| S3 action | Mutation boundary | S4 requirement |
| --- | --- | --- |
| `review.acceptSuggestion` | `draftPreviewRequired` | cite the suggestion id plus frame/event/observation/artifact refs needed to resolve a patchable Review candidate |
| `review.rejectSuggestion` | `reviewLocal` | keep the same evidence refs but record no workflow mutation |
| `review.draftCandidate` | `draftPreviewRequired` | preserve source preview / observation / artifact refs for a candidate generated from a frame |
| `review.draftSelection` | `draftPreviewRequired` | preserve selected bounds plus frame/surface/source preview refs when a user-reviewed region overrides candidate bounds |
| `review.previewDraft` | `draftPreviewRequired` | preserve source artifact refs plus package-local materialized asset paths, SHA-256 digests and draft task/condition ids after the Draft Preview handoff |
| `review.importDraft` | `confirmedImport` | only after Draft Preview confirmation; S4 must not model suggestions as direct workflow writes |

S4 coordination update:

- `SemanticRecordingReviewActionSemantics` is now Codable.
- S4 can call `acceptSuggestion(_:)`, `rejectSuggestion(_:)` and `clearDecision(_:)` with the raw `RecordingSuggestion` returned by CLI/query services.
- S4 can wrap those semantics with `SemanticRecordingReviewActionPresentation` for stable row-level evidence display.
- The generated semantics preserve `suggestionID`, primary `frameID`, `eventIDs`, `observationIDs`, `artifactPath`, bounds and summary.
- Preview/import semantics preserve `materializedAssets`, so CLI/AI summaries can explain source bundle artifact -> package-local draft asset alignment without treating the semantic recording bundle as a durable workflow dependency.
- S4 fixture/stored/live suggestion payloads should expose these semantics as `reviewActions`; when a user-facing CLI/AI surface needs rows, it should expose a lossless `reviewActionPresentations` projection before calling stored/live suggestions product-ready.
- No S4 schema change is required for the current S3 Bundle Health / candidate-action polish. S4 should keep using the existing Codable `SemanticRecordingReviewActionSemantics` / `SemanticRecordingReviewActionPresentation` for actions, and treat artifact availability, validation issues and suppression rows as evidence context until a future S4 source deliberately adds an availability/status payload.
- If S4 later exposes stored/live suggestion availability, it should preserve S3's artifact refs and missing/available meaning rather than minting alternate evidence identifiers or modeling missing artifacts as rejected suggestions.
- Run Target is provenance, not mutation. S4 can reuse `SemanticRecordingReviewRunTargetEvidence` when summarizing why a Run Detail entry opens a specific Review event/frame. The Codable payload uses `semanticReview.runTarget`, `provenanceOnly`, selected event/frame ids, requested/matched recorded-event indexes and presentation rows; it should not be exposed as a new `review.*` mutation action or use alternate failure/condition evidence ids.

## Verification

Current targeted verification:

```bash
swift test --scratch-path .build-test --enable-swift-testing --disable-xctest --filter 'AutomationViewProjectionTests|SemanticRecordingReviewActionSemanticsTests|SemanticRecordingReviewProjectionTests'
swift build -Xswiftc -swift-version -Xswiftc 6
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-timeline --output docs/workflow-page-productization/product-evidence/semantic-review-timeline.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-stored-bundle --width 1680 --output docs/workflow-page-productization/product-evidence/semantic-review-stored-bundle.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-missing-artifacts --output docs/workflow-page-productization/product-evidence/semantic-review-missing-artifacts.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-pixel-color --output docs/workflow-page-productization/product-evidence/semantic-review-pixel-color.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-run-detail --output docs/workflow-page-productization/product-evidence/semantic-review-run-detail.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-run-target --output docs/workflow-page-productization/product-evidence/semantic-review-run-target.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-draft-preview --output docs/workflow-page-productization/product-evidence/semantic-review-draft-preview.png
swift run SparkleRecorder workflow product-evidence snapshot semantic-review-materialized-actions --output docs/workflow-page-productization/product-evidence/semantic-review-materialized-actions.png
```

Observed status on 2026-07-07:

- S3 targeted tests: passed across `AutomationViewProjectionTests`, `SemanticRecordingReviewActionSemanticsTests` and `SemanticRecordingReviewProjectionTests`; coverage includes OCR wait patch, image appeared patch, visual asset upsert operations, package-local materialization path rewriting, manual frame region override, manual frame crop extraction data flow, user-picked pixel color -> `pixelMatched` patch, shared suggestion evidence refs, Codable S4-aligned Review action semantics from raw `RecordingSuggestion` values, row-level presentation evidence from raw S4 suggestions, Run Detail Macro Review source/scope projection, run-outcome initial Review targeting, visible Run Target presentation copy and Codable Run Target provenance evidence.
- Swift 6 build: passed.
- Product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-timeline.png` with sidecar `semantic-review-timeline.md`; current artifact includes the selected-region inspector, `Draft Selection`, candidate-level `review.draftSelection`, source/runtime/diff evidence tiles, suggestion evidence refs, S4-aligned Review Actions contract, `Accept` / `Reject` controls, accepted status, evidence-backed staged patch explanation and an Undo review-decision control.
- Stored bundle product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-stored-bundle.png` with sidecar `semantic-review-stored-bundle.md`; current artifact persists a checkout bundle manifest plus PNG artifact refs and renders Bundle Health, file-backed `Available` source/runtime/diff thumbnails and candidate-level `review.draftCandidate` from `SemanticRecordingReviewState`.
- Missing artifact product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-missing-artifacts.png` with sidecar `semantic-review-missing-artifacts.md`; current artifact renders a stored bundle whose frame PNGs exist while source/runtime/diff/candidate artifacts are missing, proving Bundle Health counts missing refs, the Review inspector keeps refs visible, labels them `Missing file`, and explains unavailable Open/Reveal actions.
- Pixel color product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-pixel-color.png` with sidecar `semantic-review-pixel-color.md`; current artifact shows Review-side color picking for `pixelMatched`, selected `#2BC66A`, and a staged review-only pixel draft patch before Draft Preview import.
- Run Detail product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-run-detail.png` with sidecar `semantic-review-run-detail.md`; current artifact shows linked Macro Review metadata, Open/Reveal/manual bundle controls, and explicit `Source` / `Scope` / `Run` / `Fallback` review-source chips from the Workflow inspector.
- Run Target product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-run-target.png` with sidecar `semantic-review-run-target.md`; current artifact opens Macro Review from deterministic failed run evidence and shows `Run Target` context before Teach/Draft actions.
- Draft Preview product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-draft-preview.png` with sidecar `semantic-review-draft-preview.md`; current artifact shows Review-generated package-local image asset provenance before confirmed import.
- Materialized action product evidence snapshot: generated `docs/workflow-page-productization/product-evidence/semantic-review-materialized-actions.png` with sidecar `semantic-review-materialized-actions.md`; current artifact shows Macro Review action rows after Draft Preview handoff with source artifact, package-local artifact, digest and draft task/condition evidence.

## Next Tasks

1. Capture installed-app product evidence for linked Run Detail -> Macro Review opening from a `SavedMacro.semanticRecording` bundle, including Open/Reveal artifact actions.
2. Add per-run/session semantic recording evidence drill-in once S2 exposes run-level metadata beyond the saved macro reference.
3. Capture live product evidence for frame-to-condition creation once a live bundle can be opened from the installed app.
4. Add installed-app product evidence for pixel color picking, suggestion accept/reject and the Review -> Draft Preview -> confirm import handoff from a live bundle.

## Implementation Log

- 2026-07-06: Added `SemanticRecordingReviewProjection` and tests. The projection converts S1 fixture bundle values into frame strip rows, event rows with before/after frame ids, selected-frame overlays, source/runtime comparison rows, frame-to-condition candidates and review-only suggestion rows.
- 2026-07-06: Added `SemanticRecordingReviewFixtureView` and `semantic-review-timeline` product-evidence snapshot scenario. This is a fixture Review UI proof, not the final Macro Review integration.
- 2026-07-06: Added `SemanticRecordingReviewDraftPatchBuilder`, visual asset upsert patch operations, app-edge `SemanticRecordingReviewPresenter`, Run Detail Macro Review entry, frame drag selection and patch save flow. The original workflow remains review-only; generated patches can be saved and applied through the existing draft patch pathway.
- 2026-07-06: Connected Review-generated frame-to-condition patches to `AutomationWorkflowDraftPreviewSheet` and the existing confirmed import callback, preserving review-only behavior until the user explicitly imports.
- 2026-07-06: Added Review-side pixel color picking for `pixelMatched` candidates and a pure test proving user-picked color can generate and apply a valid pixel condition patch without metadata color evidence.
- 2026-07-06: Added `semantic-review-pixel-color` fixture product evidence. The snapshot layers a deterministic pixel sample source preview onto the checkout bundle and renders the Review color picker plus staged `pixelMatched` patch using selected `#2BC66A`.
- 2026-07-06: Added suggestion review actions. Suggestions now expose cited evidence rows, `Accept Patch` to create a review-only patch from matching evidence, and `Reject` as a local non-mutating review decision.
- 2026-07-06: Tightened suggestion review decision UX. Accepted suggestions now mark their staged patch source, rejected/undone decisions clear only that suggestion-owned patch, and the timeline fixture renders accepted status plus Undo so the review-only mutation state is visible.
- 2026-07-06: Connected Run Detail Macro Review to `SavedMacro.semanticRecording`. The primary button now opens the linked bundle through `SemanticRecordingReviewPresenter.reviewState(from:)` when macro metadata exists, keeps a manual bundle fallback, and guards async open results so a stale request cannot present Review for a different selected run.
- 2026-07-06: Added linked Macro Review metadata and bundle Reveal from Run Detail. The section now surfaces recording id, event count, capture date and manifest ref before opening, and resolves Reveal through `SemanticRecordingReviewPresenter` rather than SwiftUI path construction.
- 2026-07-06: Added `semantic-review-run-detail` product evidence snapshot. The snapshot injects `SavedMacro.semanticRecording` into the `Upload report` fixture macro and renders Run Detail with linked Macro Review metadata plus Open/Reveal/manual bundle controls.
- 2026-07-06: Added package-local materialization for Review-generated image/template and baseline assets. `SemanticRecordingReviewAssetMaterializer` rewrites patch asset refs to `assets/images` or `assets/baselines`, computes SHA-256 from copied bytes, and `SemanticRecordingReviewPresenter.previewState` writes those files under app-managed `ReviewVisualAssets` before opening Draft Preview.
- 2026-07-06: Added manual frame-crop extraction for Review-generated image/template and baseline assets. Manual region selections now travel as `SemanticRecordingReviewAssetExtraction` plans, Draft Preview materialization reads the selected frame artifact, crops it to PNG, writes package-local assets, and stores visual asset provenance fields for source frame, surface and crop bounds.
- 2026-07-06: Added Draft Preview provenance badges for Review-generated visual assets, so frame id, crop bounds, source artifact, surface and hash are visible before confirmed import.
- 2026-07-06: Added `semantic-review-draft-preview` product evidence snapshot. The snapshot command builds a Review-generated image condition patch from the checkout fixture, applies it to a real draft document, and renders `AutomationWorkflowDraftPreviewSheet` with provenance badges visible in Draft Visual Assets.
- 2026-07-06: Added `semantic-review-materialized-actions` product evidence snapshot. The snapshot command renders Macro Review with materialized `review.previewDraft` / `review.importDraft` presentation rows, proving package-local asset path and digest are visible in the Review action contract after Draft Preview handoff.
- 2026-07-06: Added Review source/runtime evidence drill-in tiles. The Macro Review inspector now renders Source, Runtime and Diff artifact slots with safe refs in fixture mode and available/missing/thumbnail states for real bundles loaded through `SemanticRecordingReviewPresenter`; `semantic-review-timeline.png` was regenerated to show the drill-in slots in the S3 fixture surface.
- 2026-07-06: Added `semantic-review-stored-bundle` product evidence. The snapshot writes the checkout semantic recording manifest plus PNG artifacts to disk, renders Review through `SemanticRecordingReviewState`, and proves Available source/runtime/diff thumbnails and file-backed candidate artifact affordances without requiring S2 live capture or fake video.
- 2026-07-06: Added `semantic-review-missing-artifacts` product evidence and missing-artifact UI polish. Candidate and Source/Runtime/Diff artifact rows now keep safe refs visible as `Missing file`, explain that Open/Reveal is unavailable when presenter status says the file is absent, and show a stored fixture where frame PNGs remain while source/runtime/diff assets are intentionally omitted.
- 2026-07-06: Added evidence-backed suggestion decision explanations. Accepted suggestions now show the cited frame/artifact, staged patch operation and Draft Preview import boundary inline; rejected suggestions keep their evidence refs while making the no-mutation decision explicit.
- 2026-07-06: Added selected-region draft selection polish. A reviewed frame region now appears as a first-class inspector block with bounds/frame/surface metadata, `Draft Selection` routes that region into frame-to-condition patch generation, and the timeline product evidence snapshot shows the selected overlay plus review-only mutation boundary.
- 2026-07-06: Added Review action semantics for S4 alignment. `SemanticRecordingReviewActionSemantics` defines stable Review action names, mutation boundaries and evidence alignment for accept/reject/draft-selection/import; the action semantics test now compares the shared suggestion fixture refs consumed by S4 with the S3 Review action refs.
- 2026-07-06: Extended S4 Review action alignment. `SemanticRecordingReviewActionSemantics` is now Codable and can generate accept/reject/clear semantics directly from raw `RecordingSuggestion`, preserving the same suggestion/frame/event/observation/artifact refs that S4 CLI/query payloads already expose.
- 2026-07-06: Added visible Review action contract rows to Suggestion Review. The product evidence timeline now shows `review.acceptSuggestion`, `review.rejectSuggestion` and `review.clearDecision` with the same evidence refs and mutation boundaries that S4 emits in `reviewActions`.
- 2026-07-06: Added raw-S4-suggestion presentation coverage. `SemanticRecordingReviewActionPresentation` now has direct test coverage from raw `RecordingSuggestion` values, proving S4 can preserve mutation boundary/effect plus suggestion/frame/observation/artifact/bounds evidence without treating suggestions as direct workflow writes.
- 2026-07-06: Added Run Detail Macro Review source/scope projection. `AutomationMacroReviewSourcePresentation` makes saved-macro linked evidence, macro-level scope, unbound per-run evidence and manual bundle fallback a tested core projection; `AutomationTaskRunDetailView` now renders those chips from projection instead of local conditional text.
- 2026-07-06: Added run-outcome initial Review targeting. `SemanticRecordingReviewRunTarget` maps failed `recordedEventIndex`, nearest legacy index fallback and timeout/condition outcomes to initial Review event/frame ids before Run Detail presents the Macro Review sheet.
- 2026-07-06: Added Review Bundle Health and candidate-action evidence alignment. Stored-bundle Review now shows validation, available/missing artifact counts and suppression detail before Teach/Draft actions, and Teach System candidates show `review.draftCandidate` / `review.draftSelection` with frame/source/artifact/bounds evidence before any patch is created.
- 2026-07-07: Added visible Run Detail target context inside Macro Review. `SemanticRecordingReviewRunTargetPresentation` explains failed-event, nearest-event fallback, condition-evidence and timeline fallback targeting; Run Detail passes that presentation into the sheet, and `semantic-review-run-target` proves the explanation is visible before Teach/Draft actions.
- 2026-07-07: Added S4-safe Run Target provenance evidence. `SemanticRecordingReviewRunTargetEvidence` is Codable, uses `semanticReview.runTarget` rather than a `review.*` mutation action, marks the boundary as `provenanceOnly`, preserves selected event/frame ids plus requested/matched recorded-event indexes, and round-trips in projection tests.

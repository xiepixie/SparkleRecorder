# Acceptance Checklist

更新时间：2026-07-06
状态：规划验收清单

只有代码存在、测试通过、文档匹配真实行为，并且有产品证据时，才能把条目标为 done。

当前状态和执行顺序维护在 [06-current-work-and-next-tasks.md](06-current-work-and-next-tasks.md)。本清单只标记可验收事实；不能因为方向文档、fixture 或 mock 通过就把 live-product 条目标为 done。

## Bridge Phase: Workflow Evidence Closure

- [ ] Capture live visual diagnostics run from the installed App, including last-sample/watched-region artifact preview.
- [ ] Capture real Open/Reveal interactions for visual diagnostic artifacts through the app-edge presenter.
- [ ] Capture real Reveal Report / Open Screenshot interactions for macro run evidence.
- [ ] Capture real branch evidence drill-in consistency: FlowGraph edge state, selected run row, and Run Detail durable branch evidence agree.
- [ ] Accept template/baseline preview refs as source-frame/runtime-sample evidence, not just string fields. Draft request: [09-template-baseline-preview-refs.md](09-template-baseline-preview-refs.md).
- [ ] Capture real drag/reorder or drag-link clip proving indicator and reducer mutation match.
- [ ] Keep fixture evidence sidecars explicit about what is fixture-proven versus live-product-proven.
- [ ] Keep `06-current-work-and-next-tasks.md` updated whenever evidence status, owner boundary, accepted contract, or immediate next slice changes.
- [ ] Keep [workstreams/s0-workflow-evidence.md](workstreams/s0-workflow-evidence.md) updated while S0 is active.

## Phase 0: Contract Freeze

- [ ] Confirm S1/S2/S3/S4 owner boundaries from `08-parallel-workstreams.md` before implementation PRs split.
- [ ] Define `SemanticRecordingBundle` schema.
- [ ] Define `RecordingFrameReference`, `RecordingVisualObservation`, `RecordingSemanticEvent`.
- [ ] Define private `timeline.jsonl`, AI-safe `events.jsonl`, and `suppressed.jsonl` boundaries.
- [ ] Define Apple API policy: macOS 15+ baseline, default `SCRecordingOutput` video, event-aligned keyframes, no macOS 14 fallback.
- [ ] Define recording retention and deletion policy.
- [ ] Update format/versioning docs when schema is accepted.
- [ ] Define how frame-derived image/baseline/OCR/pixel assets map into existing `AutomationWorkflowDraftVisualAssets`.
- [ ] Define safe relative artifact refs and presenter boundaries shared with Workflow run evidence.

## Phase 1: Video And Keyframes

- [ ] Record target-window `.mov` during macro recording through `SCRecordingOutput`.
- [ ] Record target-window keyframes during macro recording.
- [ ] Persist video segment metadata with start/end time, capture target and codec/file info.
- [ ] Provide keyframe-only light mode only after default video path is safe and reviewable.
- [ ] Persist frame index with event time alignment.
- [ ] Show recorded video/keyframes in Macro Review.
- [ ] Click an event row and jump to before/after frame.
- [ ] Unit-test timestamp/frame/event alignment with fake clocks and fixtures.

## Phase 2: Visual Index

- [ ] Run OCR on selected/key frames through app-edge Vision adapter.
- [ ] Persist OCR observations with frame IDs and bounding boxes.
- [ ] Persist window/surface metadata snapshots.
- [ ] Support pixel sampling from recorded frames.
- [ ] Support image template/baseline extraction from recorded frames.
- [ ] Store source frame ID, surface ID, crop bounds, search region and threshold for every extracted visual asset.
- [ ] Preview template/baseline refs in UI with thumbnail/diff/source-frame evidence.
- [ ] Add fixture tests for path safety, coordinate transforms, OCR observation parsing and asset references.

## Phase 3: Editing UX

- [ ] User can create OCR wait from recorded frame selection.
- [ ] User can create image appeared/disappeared condition from recorded frame crop.
- [ ] User can create region changed baseline from recorded frame region.
- [ ] User can replace one fragile coordinate click with visual locator suggestion.
- [ ] UI shows evidence-backed explanation for each accepted suggestion.
- [ ] User can compare recording baseline, runtime last sample, and watched-region crop in one drill-in.
- [ ] User can reject an AI/automatic suggestion without mutating the original playable macro.

## Phase 4: CLI

- [ ] `recording list/show/explain --json`
- [ ] `recording frames/frame show/events-near --json`
- [ ] `recording ocr search --json`
- [ ] `recording visual search --json`
- [ ] `recording asset extract/baseline --json`
- [ ] `recording suggest waits/locators/conditions/cleanup --json`
- [ ] `workflow draft from-recording --json`
- [ ] CLI results use stable `sparkle.cli.result.v1` envelopes.
- [ ] CLI returns evidence refs by default and only exports image data when explicitly requested.

## Phase 5: AI Draft Integration

- [ ] AI can generate a `sparkle.workflow.draft.v1` from one recording.
- [ ] Draft Preview shows evidence references from recording frames.
- [ ] Validate/simulate/dry-run/import works without AI writing internal workflow JSON.
- [ ] User can reject or patch AI suggestions.

## Phase 6: App Knowledge

- [ ] Group recordings/macros by app bundle ID and surface family.
- [ ] Build app knowledge summary from existing recordings.
- [ ] CLI can answer which existing macros/anchors may satisfy a natural-language goal.
- [ ] AI can compose a draft from existing macros without requiring a new recording when evidence is sufficient.
- [ ] UI explains reused recordings and missing evidence.

## Product Evidence

- [ ] Recording review screenshot with video frame, event row and OCR overlay.
- [ ] Frame-to-condition creation clip.
- [ ] AI cleanup suggestion screenshot with evidence explanation.
- [ ] CLI transcript showing low-token query flow over local visual index.
- [ ] Draft-from-recording preview screenshot.

## Safety Gates

- [ ] Secure Input and password fields suppress visual/text evidence.
- [ ] Excluded apps/windows/domains produce suppression records.
- [ ] Full video is never sent to AI by default.
- [ ] User can delete semantic bundle artifacts.
- [ ] App-edge presenters handle reveal/open; SwiftUI does not construct raw paths.
- [ ] AI suggestions cite frame/event/evidence IDs; suggestions without evidence stay marked low confidence.
- [ ] Semantic recording can be disabled without breaking ordinary macro recording/playback.

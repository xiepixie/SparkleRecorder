# CLI AI Contract

更新时间：2026-07-06
状态：CLI-first 规划

## Recommendation

本阶段先做 CLI，不做 MCP。MCP 将来只包装同一套 service/CLI 语义，不另写一套推理逻辑。

原因：

- CLI 可测试、可脚本化、可被本地 AI agent 调用。
- CLI 输出可以稳定为 JSON envelope，符合现有 `AutomationCLIResult` 方向。
- AI 可以低 token 查询本地索引，不需要重复上传完整视频。
- 用户可以在 App UI 里审阅 CLI 生成的 draft 或 suggestion。

## AI Should Not

- 不直接写 `.sparkrec_workflow`。
- 不直接写内部 Swift Codable JSON。
- 不直接生成原始坐标序列作为主产物。
- 不自动运行新生成 workflow。
- 不默认读取完整视频。

AI should generate:

- macro explanation
- locator/condition suggestions
- wait cleanup suggestions
- visual asset extraction suggestions
- `sparkle.workflow.draft.v1`
- app knowledge summaries

## Proposed Commands

### Recording Catalog

```bash
SparkleRecorder recording list --json
SparkleRecorder recording show <recording-id> --json
SparkleRecorder recording explain <recording-id> --json
SparkleRecorder recording readiness <recording-id> --json
SparkleRecorder recording macro-links --json
SparkleRecorder workflow macros --json
```

`explain` returns a compact local summary: app surfaces, user-visible purpose, key steps, possible fragile steps, available visual evidence.

`readiness` returns a compact audit of schema/reference validity, sidecar load diagnostics, expected video/keyframes/timeline/events, optional OCR/window/AX requirements and follow-up actions. It should stay read-only and should not load image or video bytes by default.

`macro-links` audits saved macro `semanticRecording` references against the selected/default recording root. `workflow macros --json` should expose the reference so AI can discover which playable macros already have local semantic evidence without reading `macro.json` directly.

### Frame And Video Queries

```bash
SparkleRecorder recording frames <recording-id> --json
SparkleRecorder recording frame show <recording-id> --frame <frame-id> --json
SparkleRecorder recording frame export <recording-id> --frame <frame-id> --out frame.png --json
SparkleRecorder recording events-near <recording-id> --time 12.4 --window 1.0 --json
```

These let AI inspect only the relevant window of evidence.

### OCR And Search

```bash
SparkleRecorder recording ocr search <recording-id> --text "Submit" --json
SparkleRecorder recording visual search <recording-id> --image asset.png --json
SparkleRecorder recording pattern search <recording-id> --kind buttonLike --text-near "Submit" --json
SparkleRecorder recording pixel sample <recording-id> --frame <frame-id> --point 120,80 --json
```

Search results should include frame IDs, bounding boxes, surface IDs, confidence/score, and suggested search regions.

### Asset Extraction

```bash
SparkleRecorder recording asset extract <recording-id> \
  --frame <frame-id> \
  --region 100,120,80,40 \
  --kind imageTemplate \
  --name submit-button \
  --json

SparkleRecorder recording asset baseline <recording-id> \
  --frame <frame-id> \
  --region 100,120,300,80 \
  --name result-panel \
  --json
```

Extraction should copy/crop into managed visual assets and return references usable by workflow drafts.

### Optimization Suggestions

```bash
SparkleRecorder recording suggest waits <recording-id> --json
SparkleRecorder recording suggest locators <recording-id> --json
SparkleRecorder recording suggest conditions <recording-id> --json
SparkleRecorder recording suggest cleanup <recording-id> --json
```

Suggestions must include evidence references and should be non-destructive.

### Draft Generation

```bash
SparkleRecorder workflow draft from-recording <recording-id> --out draft.json --json
SparkleRecorder workflow draft from-recordings <folder-or-app-id> --goal "..." --out draft.json --json
```

The output is still `sparkle.workflow.draft.v1`, then goes through existing validate/simulate/dry-run/import.

### Application Knowledge

```bash
SparkleRecorder app-knowledge build --app com.example.App --json
SparkleRecorder app-knowledge show --app com.example.App --json
SparkleRecorder app-knowledge suggest-macro --app com.example.App --goal "..." --json
```

This supports the future where AI can compose a new macro from existing recordings without asking the user to re-record.

## Output Shape

All CLI commands should return stable JSON:

```json
{
  "schema": "sparkle.cli.result.v1",
  "ok": true,
  "command": "recording.ocr.search",
  "recordingID": "recording-123",
  "results": [],
  "warnings": [],
  "nextActions": []
}
```

Evidence references should be stable, relative, and safe:

```json
{
  "frameID": "frame-00042",
  "eventIDs": ["event-91"],
  "surfaceID": "checkout-window",
  "artifactRef": "frames/000042.png",
  "boundingBox": { "x": 864, "y": 672, "width": 96, "height": 24 }
}
```

S1 first pass gives S4 these shared value types before command implementation:

- `RecordingQueryResult`
- `RecordingSuggestion`
- `RecordingEvidenceReference`
- `RecordingArtifactRef`
- `RecordingFrameReference`
- `RecordingVisualObservation`
- `RecordingPreviewComparison`

S4 should wrap these in the existing `sparkle.cli.result.v1` envelope pattern rather than inventing a recording-only result schema. CLI outputs should cite ids and safe artifact refs by default; exporting image bytes or frame crops should remain an explicit command.

S1 also provides `SemanticRecordingFixture.checkoutQueryResults()` and `SemanticRecordingFixture.checkoutSuggestions()` so first CLI fixtures can validate envelope shape and evidence citation before live recording storage exists.

## Token Strategy

The local CLI should do the heavy lifting:

- search OCR locally
- score template locally
- summarize timeline locally
- crop keyframes locally
- return only top candidates
- include evidence refs instead of bulk image data by default

AI requests should operate on:

- compact timeline summaries
- top N evidence candidates
- selected frame crops only when needed
- structured suggestions with confidence and risks

This keeps AI useful without turning every macro edit into a full video-analysis prompt.

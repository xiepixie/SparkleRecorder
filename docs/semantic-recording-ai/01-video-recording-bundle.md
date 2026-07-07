# Video Recording Bundle

更新时间：2026-07-06
状态：目标合同草案

## Why Record Video

宏录制天然需要视频母带。文件名只能描述“这大概是什么宏”，而视频能证明用户当时在哪个应用、看到了什么状态、什么时候等待、哪里出现了文字或图案、最终结果是什么。

视频的产品价值：

- 让用户回看并理解宏的真实目的。
- 让 AI 解释每一步的意图，而不是只看坐标。
- 从录制帧中直接提取 OCR region、image template、baseline、pixel sample。
- 修正人类录制瑕疵，例如等待过长、点击偏移、误触、重复输入。
- 为失败诊断提供 recorded baseline 与 run-time sample 的对照。

## Recording Flow

推荐流程：

1. 用户点击 Record。
2. App 做权限 preflight：Input Monitoring / Accessibility / Screen Recording。
3. Recording session 创建 bundle，并开始双轨采集。
4. 输入轨记录 `RawInputEvent`，生成 `RecordedEvent`。
5. 视觉轨用 ScreenCaptureKit 录 target window 或 selected display 的视频母带。
6. 同时按策略抽关键帧：启动、window focus change、mouse down/up、scroll burst、keyboard text burst、等待间隙、用户 marker、录制结束。
7. 对关键帧异步运行 OCR / AX snapshot / window metadata / optional pattern candidate extraction。
8. 停止录制后封存 bundle，生成 AI-safe summary 和可编辑 timeline。
9. 用户进入 Macro Review：剪掉误操作、调整等待、选择锚点、保存宏。
10. 用户可选择生成 workflow draft 或 visual assets。

## Apple API Feasibility

2026-07-06 的 API 调研结论：实现路径清晰，但需要按 macOS availability 分层。

| Need | Preferred API | Platform Decision |
| --- | --- | --- |
| full `.mov` capture | `SCStream` + `SCRecordingOutput` | macOS 15+ 产品默认路径 |
| event-aligned keyframes | `SCScreenshotManager.captureImage(contentFilter:configuration:)` or `SCStreamOutput` sample buffers | macOS 15+ 默认视觉索引路径 |
| target window / display selection | `SCShareableContent.current`, `SCContentFilter` | macOS 15+，复用现有 `ScreenCaptureService` 思路并扩展 surface mapping |
| new screenshot output model | `SCScreenshotManager.captureScreenshot` | macOS 26+，可作为未来增强，不能阻塞第一版 |

因此第一版 acceptance 应是 video plus keyframes：先证明 `.mov`、event/frame/surface alignment、OCR/index 和 frame-to-condition；keyframe-only 可以作为隐私/轻量模式，但不是默认产品路径。macOS 14 `AVAssetWriter` fallback 不进入当前路线。

## Bundle Shape

目标 bundle 可以跟随未来 `.sparkrec` / macro package 演进。规划结构：

```text
recording/
  manifest.json
  raw-events.jsonl
  recorded-events.json
  timeline.jsonl
  events.jsonl
  suppressed.jsonl
  video/
    recording.mov
    segments.json
  frames/
    000001.png
    000002.png
    index.jsonl
  ocr/
    observations.jsonl
  accessibility/
    snapshots.jsonl
  windows/
    surfaces.json
    snapshots.jsonl
  visual-index/
    index.sqlite
    templates/
    baselines/
  ai/
    summary.json
    draft-context.json
    suggestions.json
  runs/
```

`timeline.jsonl` is internal and complete. `events.jsonl` is filtered and safe for AI/CLI. `suppressed.jsonl` records withheld evidence counts/reasons, such as secure input, password fields, excluded apps, excluded domains, or over-size artifacts.

## Core Contract v0

S1 first pass exists in `Sources/SparkleRecorderCore/SemanticRecordingBundle.swift`.

Current mapping:

- `manifest.json` -> `SemanticRecordingBundle`
- `video/segments.json` -> `RecordingVideoSegment`
- `frames/index.jsonl` -> `RecordingFrameReference`
- `timeline.jsonl` -> `RecordingTimelineEvent`
- `events.jsonl` -> `RecordingSemanticEvent`
- `ocr/observations.jsonl`, future AX/window/pattern observations -> `RecordingVisualObservation`
- `suppressed.jsonl` -> `RecordingSuppressionRecord`
- source template/baseline/OCR/pixel previews -> `RecordingSourcePreviewReference`
- runtime last-sample/watched-region previews -> `RecordingRuntimeSampleReference`
- source/runtime decision evidence -> `RecordingPreviewComparison`

All local artifact pointers use `RecordingArtifactRef`, which accepts only safe relative paths. The core contract does not create files, run Vision, run ScreenCaptureKit, open previews, or copy visual assets; those stay in app-edge S2/S3 work.

`SemanticRecordingFixture.checkoutBundle()` is the deterministic S1 fixture bundle for S2 API spikes, S3 Review UI prototypes and S4 CLI fixtures. It includes one `.mov` segment, event-aligned frames, semantic events, OCR/template observations, source/runtime preview refs, one comparison and one suppression record.

S2 first pass exists in core and app-edge code: fake movie/frame/index clients can drive `SemanticRecordingCaptureSession` and return a validating `SemanticRecordingBundle`; app-edge skeletons exist for `SCRecordingOutput` movie capture, `SCScreenshotManager` keyframe PNGs, `RecordingBundleStore` persistence/loading, Vision OCR indexing and permission preflight snapshots. Experimental Recorder bridge, preflight UI/gating, AX/window/suppression production, AI-safe text redaction, playback-preserving playable macro save/export/status sanitization, pure frame/video redaction planning, app-edge redacted frame PNG writing, app-edge redacted `.mov` range rendering, live finish redaction application, sidecar-aware bundle loading/catalog, Review/CLI redacted-frame preference, retention/deletion planning, retention settings/manual cleanup/scheduled cleanup and pure retention confirmation presentation have first-pass wiring. This is not product-complete semantic recording yet: live `.mov` product evidence, default rollout, redacted frame/video product evidence, reviewed text-anchor mutation and live cleanup product evidence remain open.

## Video Capture Policy

Default capture should be useful without exploding storage:

- Record target window when a stable `PlaybackSurface` exists.
- Fall back to display crop only when the target window cannot be captured.
- Record H.264/HEVC `.mov` through `SCRecordingOutput` for semantic recording.
- Extract keyframe PNGs for visual indexing and AI-safe evidence queries.
- Cap frame extraction rate by semantic events, not raw FPS.
- Allow “light recording” mode with keyframes only.
- Allow “diagnostic rich” mode for debugging fragile automation.

## Keyframe Policy

Extract frames at:

- recording start and stop
- app/window focus changes
- first click in each active surface
- mouse up after click/drag
- before and after long waits
- before and after text input bursts
- after scroll bursts settle
- user marker points
- visible UI state changes detected by frame difference
- visual condition candidate regions selected by user

Each keyframe should have:

```json
{
  "frameID": "frame-00042",
  "time": 12.420,
  "videoTime": 12.420,
  "surfaceID": "safari-1",
  "source": "mouseUp",
  "imagePath": "frames/000042.png",
  "windowFrame": { "x": 80, "y": 90, "width": 1200, "height": 800 },
  "displayScale": 2.0,
  "relatedEventIDs": ["event-91", "event-92"]
}
```

## Editing Support

The video timeline should make macro editing concrete:

- Scrub video and see raw/processed events below it.
- Select a click and see the frame before and after the click.
- Turn a frame region into OCR wait, image appeared, image disappeared, region changed, baseline comparison, or pixel match.
- Mark a wait as intentional or accidental.
- Trim dead time and compress waits into condition waits.
- Replace a fragile coordinate click with a text/image/AX locator when evidence supports it.
- Show “why this click is fragile” when it landed on blank space, near an edge, or without stable visual/AX target.

## Privacy And Safety

Video is sensitive. Required controls:

- Explicit Screen Recording permission and clear recording indicator.
- Excluded apps/domains/windows.
- Secure Input and password field suppression.
- Local-only default storage.
- User review before sending frames to any AI API.
- AI payloads use summaries and selected keyframes, not full video by default.
- Deletion and retention policy per macro.

## Acceptance Slice

First implementation should prove:

- a recording bundle contains playable events plus video/keyframes
- keyframes align with event times
- OCR observations can point back to frame IDs
- a user can create one visual condition from a recorded frame
- CLI can list frames and search OCR text without sending the whole video to AI
- full `.mov` support uses the macOS 15+ product baseline and does not require a macOS 14 fallback

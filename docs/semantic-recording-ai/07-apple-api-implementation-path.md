# Apple API Implementation Path

更新时间：2026-07-06
状态：2026 Apple API 可行性调研与实施路径
Owner：Recording / Vision / App-edge adapters

本文回答一个更落地的问题：SparkleRecorder 要做“录制时保存视频/关键帧，并让 AI 低成本理解录制语义”，Apple 当前 API 能不能支撑，第一版应该怎么切。

结论：可以实现，而且项目已决定把下一阶段最低平台提升到 macOS 15+。这让 `SCRecordingOutput` 可以成为语义录制的视频默认路径，避免为 macOS 14 维护一条 `AVAssetWriter` fallback。

1. 语义录制默认保存 `SCRecordingOutput` `.mov`。
2. 同一录制过程生成 event-aligned keyframes，用于 OCR、pattern search、baseline 和 AI 低 token 查询。
3. keyframe-only 可以作为隐私/轻量模式，但不是产品默认能力边界。
4. 视觉语义用 Apple Vision / AX / CoreImage / Accelerate 组合；不要假设 Vision 单个 API 能完成任意 UI pattern search。

## Research Basis

本轮核对了 Apple 官方 API surface 和本机 Xcode macOS 26.5 SDK headers。关键文档入口：

- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- `SCRecordingOutput`: https://developer.apple.com/documentation/screencapturekit/screcordingoutput
- `SCScreenshotManager`: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- `SCStream`: https://developer.apple.com/documentation/screencapturekit/scstream
- Apple Vision: https://developer.apple.com/documentation/vision
- `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- `VNGenerateImageFeaturePrintRequest`: https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest
- `VNFeaturePrintObservation`: https://developer.apple.com/documentation/vision/vnfeatureprintobservation
- `VNTrackObjectRequest`: https://developer.apple.com/documentation/vision/vntrackobjectrequest
- Accessibility `AXUIElement`: https://developer.apple.com/documentation/applicationservices/axuielement
- CoreGraphics TCC preflight/request APIs: https://developer.apple.com/documentation/coregraphics

本地 SDK 可行性点：

- `SCStream.addRecordingOutput(_:)` / `SCRecordingOutput` 是 macOS 15+，适合作为完整视频默认路径。
- `SCStreamOutput` 可收到 screen/audio/microphone sample buffer；这可支撑 keyframe extraction 和实时观察。
- `SCScreenshotManager.captureImage(contentFilter:configuration:)` 可用于单帧截图和补帧。
- `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)` 是 macOS 26+ 的新截图输出形态，不能作为第一版必需依赖。
- `VNRecognizeTextRequest` 可返回 `VNRecognizedTextObservation`；适合本地 OCR。
- `VNGenerateImageFeaturePrintRequest` + `VNFeaturePrintObservation.computeDistance` 可做图像相似度，但不等于精确 UI template localization。
- `VNTrackObjectRequest` / `VNSequenceRequestHandler` 可在用户选定区域后跨帧跟踪目标。
- `VNDetectRectanglesRequest`、`VNDetectContoursRequest`、`VNTrackOpticalFlowRequest` 可辅助 UI shape、region change 和 motion，但需要我们自己的评分和证据模型。

## Capability Matrix

| Product Need | Apple API Path | Minimum OS | First Slice Decision |
| --- | --- | --- | --- |
| Full `.mov` recording | `SCStream` + `SCRecordingOutput` | macOS 15 | Default semantic recording video path |
| Target-window frame capture | `SCShareableContent.current`, `SCContentFilter(desktopIndependentWindow:)`, `SCScreenshotManager.captureImage` | macOS 15 product baseline | Default frame path |
| Display fallback frame capture | `SCContentFilter(display:excludingWindows:)`, `SCScreenshotManager.captureImage` | macOS 15 product baseline | Default fallback |
| Event-aligned keyframes | `SCStreamOutput` sample buffers or one-shot `SCScreenshotManager.captureImage` | macOS 15 product baseline | Default visual index path |
| OCR text and bounding boxes | `VNRecognizeTextRequest` | macOS 15 product baseline | First visual index provider |
| Image similarity | `VNGenerateImageFeaturePrintRequest`, `VNFeaturePrintObservation.computeDistance` | macOS 15 product baseline | Coarse candidate scoring, not final locator alone |
| Precise template/pixel/region diff | CoreGraphics, CoreImage, Accelerate/vImage, custom scoring | macOS 15 product baseline | Needed for reliable pattern search |
| Object/region tracking across frames | `VNTrackObjectRequest`, `VNSequenceRequestHandler`, optical flow | macOS 15 product baseline | Useful after user selects a region |
| AX semantic snapshots | `AXUIElementCreateApplication`, `AXUIElementCopyMultipleAttributeValues`, `AXUIElementCopyElementAtPosition`, `AXObserver` | macOS 15 product baseline | Event-triggered snapshots only |
| Permissions | `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, `CGPreflightListenEventAccess`, `CGRequestListenEventAccess`, `AXIsProcessTrustedWithOptions` | macOS 15 product baseline | Extend existing `PermissionCenter` flow |

## Recommended Capture Architecture

Do not put ScreenCaptureKit, Vision or AX into core. Add a thin app-edge semantic capture layer next to the existing recording pipeline.

```text
EventTapThread
  -> LiveRecordingEngineClient
  -> RecordingSessionProcessor
  -> RecordedEvent

LiveSemanticCaptureClient
  -> ScreenCaptureKit target window/display capture
  -> SCRecordingOutput movie writer
  -> keyframe writer
  -> Vision/AX/window observation jobs
  -> RecordingBundleStore

RecordingBundleService
  -> safe relative refs
  -> frame/event/surface alignment
  -> CLI/UI query results
  -> workflow draft evidence refs
```

Core should define value contracts:

- `SemanticRecordingBundle`
- `RecordingVideoSegment`
- `RecordingFrameReference`
- `RecordingTimelineEvent`
- `RecordingVisualObservation`
- `RecordingSuppressionRecord`
- `RecordingCapturePolicy`
- `RecordingFrameQuery`
- `RecordingSuggestion`

App should implement live adapters:

- `LiveSemanticCaptureClient`
- `ScreenCaptureKitMovieRecorder`
- `ScreenCaptureKitFrameSource`
- `VisionRecordingIndexer`
- `AccessibilitySnapshotClient`
- `RecordingBundleStore`

Tests should use fake movie/frame sources, fake clocks, static image fixtures and fake OCR/AX observations. Ordinary unit tests must not start ScreenCaptureKit, Vision, AX, real mouse or real keyboard.

## First Implementation Slice

### Slice 0: API Spike

Goal: prove the macOS 15+ target can capture `.mov` video and event-aligned keyframes from the same semantic recording session.

Acceptance:

- Start a recording session and create a bundle directory.
- Capture a `.mov` through `SCStream` + `SCRecordingOutput`.
- Capture a start frame through `SCScreenshotManager.captureImage` or `SCStreamOutput`.
- Capture before/after click frames around one `RecordedEvent`.
- Persist `video/segments.json` with recording file, start/end time, capture target and codec metadata.
- Persist `frames/index.jsonl` with frame ID, event IDs, surface ID, capture source, window/display bounds and timestamp.
- Run with fake clients in tests; live spike can be a manual product-evidence clip.

### Slice 1: Bundle v0, Video Plus Keyframes

Video is the audit trail; keyframes are the semantic index. The bundle should store both by default for semantic recording, while still allowing a user-facing light mode that keeps only keyframes.

Implementation:

- Use current `ScreenCaptureService` as the starting point, then extract a more general `FrameCaptureClient`.
- Capture target window when `PlaybackSurface` can map to an `SCWindow`.
- Fall back to display capture plus recorded window rect when target-window capture is unavailable.
- Write a `.mov` through `SCRecordingOutput`.
- Write PNG keyframes and an index.
- Defer OCR and AX to async post-processing jobs.

### Slice 2: Full Video Recording Details

- Create `SCStream` from the same `SCContentFilter` and `SCStreamConfiguration`.
- Create `SCRecordingOutput` with output URL and delegate.
- Add recording output before `startCapture` when possible, so the first captured sample is included.
- Keep one recording output per stream.
- Treat stream configuration updates during recording as recording-ending events.
- Store video segment metadata in `video/segments.json`.

No macOS 14 `AVAssetWriter` fallback is planned for this phase. The product baseline is macOS 15+.

## Visual Understanding Implementation

Apple Vision can support the first layer, but it is not a complete UI understanding engine.

Use Vision for:

- OCR: `VNRecognizeTextRequest`.
- Coarse image similarity: `VNGenerateImageFeaturePrintRequest`.
- User-selected region tracking: `VNTrackObjectRequest` / `VNSequenceRequestHandler`.
- Shapes: rectangle, contour, optical-flow helpers.

Use deterministic local code for:

- Pixel sampling and color ranges.
- Exact crop/template comparison.
- Local region diff.
- Perceptual hash.
- Search-region narrowing.
- Combining OCR, AX, image, pixel and proximity scores.

Use AI for:

- naming a step
- explaining likely user intent
- suggesting wait/locator replacements
- composing draft workflow proposals

AI should not be the first component asked to scan the whole video. It should query the local bundle through CLI and request selected frame crops only when needed.

## Permission And Privacy Path

Semantic recording adds one more explicit permission posture:

- Input recording needs Listen Event / Input Monitoring.
- Playback needs Post Event / Accessibility fallback.
- Screen evidence needs Screen Recording.
- AX snapshots need Accessibility.

Existing `PermissionCenter` already has most checks. The semantic recording flow should add:

- preflight summary before recording starts
- disabled/degraded mode when Screen Recording is missing
- suppression records for excluded windows/apps/domains
- Secure Input / password-field suppression
- local-only storage by default
- user-confirmed frame export for AI

## Why This Matches OpenAI Record & Replay

The OpenAI-style flow is not “raw video -> giant prompt -> replay coordinates.” It is:

```text
demo evidence bundle
  -> timeline
  -> AI-safe event stream
  -> screenshots / OCR / AX / browser/window context
  -> reusable skill or draft
```

SparkleRecorder should implement the same idea in product-native form:

- `RecordedEvent` remains the replay truth.
- video/keyframes are the evidence truth.
- OCR/AX/visual index are the searchable semantic truth.
- CLI is the low-token AI access path.
- Workflow draft preview is the user-review path.

This means our implementation can be stronger than a generic agent recorder for our domain: it can improve waits, locators, visual assets and workflow conditions while still keeping deterministic playback and reducer tests.

## Decision Summary

- Implementation path is now clear enough to start a Phase 0 contract PR.
- First code should prove video plus event-aligned keyframes through ScreenCaptureKit.
- Full video is feasible with `SCRecordingOutput` because the product baseline is macOS 15+.
- No macOS 14 `AVAssetWriter` fallback is planned.
- Vision supports OCR and useful visual primitives, but reliable UI pattern search needs custom deterministic matching and scoring.
- CLI should come after bundle fixtures and frame refs, not before.
- MCP remains deferred until the CLI/shared service contract stabilizes.

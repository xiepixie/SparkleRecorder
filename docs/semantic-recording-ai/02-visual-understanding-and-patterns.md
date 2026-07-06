# Visual Understanding And Patterns

更新时间：2026-07-06
状态：目标合同草案

## Capability Model

Visual understanding should be layered, not one monolithic “AI vision” feature:

| Layer | Purpose | Default Provider |
| --- | --- | --- |
| Window metadata | Know which app/window/surface the frame belongs to | AppKit, Accessibility, ScreenCaptureKit metadata |
| OCR text | Find visible text and text boxes | Apple Vision `VNRecognizeTextRequest` |
| AX semantics | Find native roles, labels, values, selected/focused elements | `AXUIElement` |
| Pixel/color | Detect simple state indicators, badges, toggles | CoreGraphics/CoreImage/vImage |
| Template/image | Find a recorded icon, button, thumbnail, sprite, or visual region | Vision feature print plus custom template matching |
| Region change | Detect whether a specific area changed | frame diff, perceptual hash, SSIM-like local metric |
| Higher-level pattern | Detect repeated visual structures, panels, rows, cards, dialogs | local CV heuristics first, AI-assisted labeling later |

## Text/OCR

Apple Vision is a strong first provider for macOS OCR:

- It can recognize text in screenshots.
- It returns bounding boxes and confidence-like observations.
- It works locally and fits the current privacy posture.
- It already aligns with existing `TextAnchor`, `AutomationConditionKind.ocrText`, and visual condition work.

But OCR alone is not enough:

- It does not reliably understand semantic UI hierarchy.
- It can miss stylized, tiny, disabled, rotated, or low-contrast text.
- It does not know which repeated text instance is the intended target without region, occurrence, surface and proximity scoring.

Required data model:

```json
{
  "text": "Submit",
  "normalizedText": "submit",
  "frameID": "frame-00042",
  "boundingBox": { "x": 0.72, "y": 0.84, "width": 0.08, "height": 0.03 },
  "pixelBox": { "x": 864, "y": 672, "width": 96, "height": 24 },
  "surfaceID": "checkout-window",
  "confidence": 0.92,
  "relatedEventIDs": ["event-91"]
}
```

Runtime text locator should score by:

- text similarity
- proximity to recorded frame
- search region match
- surface/window match
- OCR confidence
- relationship to previous/next events

## Pattern Matching

The product should support finding more than text:

- exact or near-exact image template
- icon appeared / disappeared
- region changed from recorded baseline
- pixel matched a color or color range
- button-like pattern near OCR text
- repeated row/card pattern
- dialog/panel appeared

Apple Vision can help with image similarity through feature print style comparisons and has useful building blocks, but it should not be the only implementation. We should expect to supplement it with:

- CoreImage / vImage for crop, resize, color histogram, threshold, pixel sampling and diffs.
- Accelerate for fast normalized cross-correlation or simpler template scoring.
- Perceptual hash for cheap frame/region change detection.
- Optional OpenCV or custom Swift/C++ module later if template matching requirements exceed what Vision/CoreImage can comfortably provide.
- Optional model-backed detector later for app-specific widgets, but only after local deterministic matchers are exhausted.

## 2026 Apple Vision API Map

Apple Vision can supply important primitives, but it is not a single “find any UI pattern” API.

| Need | Apple API | Product Interpretation |
| --- | --- | --- |
| visible text search | `VNRecognizeTextRequest`, `VNRecognizedTextObservation` | first OCR provider; returns text candidates and bounding boxes |
| coarse image similarity | `VNGenerateImageFeaturePrintRequest`, `VNFeaturePrintObservation.computeDistance` | useful for candidate ranking, not enough for exact button/icon localization |
| selected-object tracking | `VNTrackObjectRequest`, `VNSequenceRequestHandler` | useful after the user selects a region in a recorded frame |
| rectangle / panel candidates | `VNDetectRectanglesRequest`, `VNDetectContoursRequest` | helpful for dialogs, panels, cards and crop suggestions |
| region motion/change | `VNTrackOpticalFlowRequest` plus local diff | helpful for loading/progress regions, still needs our thresholds |
| generic UI semantics | no single Vision API | must combine OCR, AX, window metadata, template scoring, proximity and optional AI labeling |

The first reliable implementation should therefore be a scorer:

```text
candidate = OCR text + AX element + image/template score + pixel/region score + surface match + proximity to recorded event
```

Vision improves candidates; SparkleRecorder owns the final locator contract, thresholds, fallback and explainability.

## Recorded Visual Assets

Recorded frames should become first-class source material:

- `imageRef` can point to a crop from a recorded frame.
- `baselineRef` can point to a full region crop used for future diff.
- `pixel` can be sampled from recorded frame coordinates.
- `regionRef` can be created from user selection on the frame.
- visual assets should retain source frame ID, macro ID, surface ID and coordinate transform.

Example:

```json
{
  "assetID": "checkout-submit-button",
  "source": {
    "macroID": "macro-checkout",
    "frameID": "frame-00042",
    "surfaceID": "checkout-window"
  },
  "kind": "imageTemplate",
  "imagePath": "visual-index/templates/checkout-submit-button.png",
  "observedFrame": { "x": 864, "y": 672, "width": 96, "height": 24 },
  "searchRegion": { "x": 760, "y": 620, "width": 280, "height": 120 },
  "threshold": 0.82
}
```

## Explainability

Every AI or automatic optimization must preserve evidence:

- why this wait can become OCR wait
- why this click can be anchored to a text/image/AX target
- why this screenshot region is the recommended search region
- what changed between before/after frames
- what fallback remains if visual matching fails

The UI should show this as a reviewable suggestion, not silent mutation.

## Runtime Policy

Default execution remains coordinate-first, vision-assisted:

- Coordinate playback is still fastest.
- Visual locator runs only when a step is marked as locator/condition/assertion or when fallback policy requires it.
- OCR/template search should crop to search region, not scan full screen by default.
- Runtime evidence writes last sample, matched region, score, threshold and failure reason.

## Testing Strategy

Unit tests should use fixtures:

- OCR observations from static images
- frame metadata and coordinate transforms
- template matching score fixtures
- region diff fixtures
- visual asset path safety
- AI suggestion fixtures that reference frame IDs and region refs

Live Vision, ScreenCaptureKit and AX tests should remain app-edge smoke tests, not ordinary unit tests.

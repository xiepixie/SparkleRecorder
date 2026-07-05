# Vision Architecture & System Evolution Plan

## 1. 核心理念 (Core Philosophy)
系统遵循 **Coordinate-first, Vision-assisted** 的原则：
- **坐标是默认真相**：主执行路径应依赖坐标（速度最快、效率最高）。
- **识图是辅助证据**：在需要动态定位时（如文字选择）介入。
- **断言是可靠性保障**：在关键节点验证执行状态。
- **素材是可选增强**：用于高精度或非标准 UI 的图像匹配。
- **视频/截图是回放和诊断证据**：不阻碍核心流程。

Vision / OCR 技术不应该放置在执行的“热路径”上。它的合理使用场景为：
1. **录制后**：辅助用户理解页面结构和选取目标。
2. **编辑时**：辅助用户将坐标转化为文字/图片定位锚点。
3. **执行中**：仅在特定的 `wait`、`assert` 或用户指定的 `locator` 动作中使用。
4. **执行后**：验证是否成功，并作为失败的诊断证据。

---

## 2. 核心数据结构 (Minimal Scalable Data Model)
不进行过度设计，避免立刻引入复杂的 FlowGraph。系统分为三类核心 Action：

### 2.1 CoordinateAction（坐标主执行）
默认动作，不涉及 OCR。
```swift
struct CoordinateAction: Codable {
    var id: String
    var kind: ActionKind // click, drag, scroll, wait, keyDown
    var timeRange: TimeRange
    var coordinate: CoordinateTarget
    var sourceEventIDs: [String]
}

struct CoordinateTarget: Codable {
    var point: RectValue // 坐标点
    var coordinateSpace: CoordinateSpace // recordedWindow 等
    var fallbackPolicy: FallbackPolicy
}
```

### 2.2 LocatorAction（动态定位执行）
用户明确要求“运行时动态识别”的动作。
```swift
struct LocatorAction: Codable {
    var id: String
    var kind: ActionKind
    var locator: LocatorSpec
    var clickPolicy: ClickPolicy
    var fallback: CoordinateTarget?
}

enum LocatorSpec: Codable {
    case text(TextAnchor)
    case image(ImageAnchor)
}
```

### 2.3 AssertionAction（验证动作）
用于 `verifyText`、`waitForText` 等逻辑，不一定包含点击。
```swift
struct AssertionAction: Codable {
    var id: String
    var condition: AssertionSpec
    var timeout: TimeInterval
    var onFail: FailurePolicy
}

enum AssertionSpec: Codable {
    case textExists(TextAnchor)
    case imageExists(ImageAnchor)
}
```

---

## 3. 定位锚点设计 (Anchors)

### 3.1 TextAnchor（避免只存 String 的不稳定性）
```swift
struct TextAnchor: Codable, Equatable {
    var text: String
    var matchMode: TextMatchMode
    var observedFrame: RectValue       // 录制/选定时的文字框位置
    var searchRegion: RectValue?       // 优化的搜索范围（防重复匹配，省资源）
    var occurrenceHint: Int?           // 第几次出现（辅助提示，非主键）
    var coordinateFallback: RectValue  // 识别失败的回退坐标
}
```

### 3.2 ImageAnchor
```swift
struct ImageAnchor: Codable, Equatable {
    var assetID: String
    var observedFrame: RectValue
    var searchRegion: RectValue?
    var clickPointInAsset: RectValue
    var coordinateFallback: RectValue
    var matchThreshold: Double
}
```

---

## 4. Text Picker 交互方案 (Text Picker MVP)
为了生成包含 `observedFrame` 和 `searchRegion` 的 `TextAnchor`，提供可视化 Picker：
1. 用户点击 TextField 旁边的 🎯。
2. 隐藏 `MacroEditor` 和 `CoordinatePreviewOverlay`。
3. 截取当前窗口或全屏。
4. 后台执行 `VNRecognizeTextRequest`，获取所有文本的 `boundingBox`。
5. 显示全屏透明 `TextPickerOverlay`，将所有文本框高亮。
6. 用户点击某个高亮框。
7. 自动生成 `TextAnchor`，并基于 `observedFrame` 生成默认扩大的 `searchRegion`。
8. 填入 Inspector 并保存。

### 4.1 Search Region 自动生成算法
局部识别不仅防重，更能节省性能。
```swift
func defaultSearchRegion(for frame: CGRect, in window: CGRect) -> CGRect {
    frame.insetBy(dx: -max(120, frame.width), dy: -max(80, frame.height))
         .intersection(window)
}
```

---

## 5. Vision 运行时优化 (Execution OCR Logic)
不要在运行时盲目 `first match` 文本，而应改为 `Score` 评估：

```swift
struct TextDetection {
    var text: String
    var frame: RectValue
    var confidence: Double
}

func resolve(anchor: TextAnchor, detections: [TextDetection]) -> TextDetection? {
    detections
        .filter { matches($0.text, anchor.text, mode: anchor.matchMode) }
        .sorted { score($0, anchor) > score($1, anchor) }
        .first
}
```
**Score 计算** = (文本相似度 * 0.6) + (与 observedFrame 的距离分 * 0.3) + (confidence * 0.1)。

---

## 6. 保存与录制策略 (Evidence & Packages)
- **文档包结构 (`.sparklemacro`)**：
  最小化设计：`manifest.json`、`actions.json`、`raw-events.json`、`assets/images/`、`runs/`。暂时不引入复杂的 flow graph。
- **证据记录策略 (`EvidencePolicy`)**：
  默认使用 `screenshotsOnFailure`。只有在用户手动要求记录、或不断调试失败时，才启用完整的 ScreenCaptureKit `videoOnFailure` 录制。

---

## 7. 最小可验证验收标准 (v2.5 MVP Acceptance Criteria)
1. **实现 TextPickerOverlay**：能基于当前截屏展示所有 OCR 文字框，支持鼠标点击选中。
2. **重构 Locator 数据结构**：`waitForText` / `verifyText` 能够存储 `TextAnchor` 而不仅是 String。
3. **运行时 SearchRegion**：运行时识别必须只在 `searchRegion` 区域内裁切截图并进行 OCR，而非全屏。
4. **失败截图保存**：若定位或断言失败，将当前 `searchRegion`（或全屏）的截图以及 Detection JSON 保存作为诊断证据。
5. **不引入过度功能**：当前阶段不开发状态树、复杂 FlowGraph、AX Tree 语义映射或每次运行的全屏视频录制。

# Visual Repeat-Until Design

更新时间：2026-07-08
状态：设计对齐；bounded Repeat-Until import first slice 已有，runtime loop evidence / graph container / live product proof 仍 open
Owner：S2 App-edge capture / Owner 2 Workflow UX / S3 Review / S4 CLI

本文对齐一组用户最容易感知的能力：录制时保存视频和关键帧，录完后从帧里提取文字、图标、区域变化和像素条件，并把“重复做某个行为，直到某个文字或图案出现/消失”做成可解释、可审阅、可运行的 Workflow 能力。

结论先写清楚：

1. 首版实时图像源必须是 ScreenCaptureKit。不要再用 `CGWindowListCreateImage` 或 `AVCaptureScreenInput` 作为产品路径。
2. 语义录制视频母带继续使用 `SCStream` + `SCRecordingOutput`；运行中视觉条件和 Repeat-Until 需要新增 `SCStreamOutput` / `CMSampleBuffer` live observation path。
3. OCR 只解决文字，不解决图标。图标、按钮、状态图案、某块 UI 出现/消失，应该走 visual condition：image appeared/disappeared、region changed、pixel matched。
4. 默认只在用户选定区域或绑定窗口内找；只有用户明确选择“整个窗口/显示器”时才扩大到全局搜索。
5. Repeat-Until 的产品形态采用 Workflow 画布里的结构化循环节点：graph-first，但不是任意 dependency back-edge；Macro Editor 只提供“把选中行为变成 Repeat Until...”的入口。

## Research Basis

本轮校准资料来自 Apple 官方文档入口和本机 macOS SDK headers / Swift interface：

- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Capturing screen content in macOS: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
- `SCStream`: https://developer.apple.com/documentation/screencapturekit/scstream
- `SCRecordingOutput`: https://developer.apple.com/documentation/screencapturekit/screcordingoutput
- `SCScreenshotManager`: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- Vision: https://developer.apple.com/documentation/vision
- `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- `VNGenerateImageFeaturePrintRequest`: https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest
- `VNFeaturePrintObservation`: https://developer.apple.com/documentation/vision/vnfeatureprintobservation
- Accelerate / vImage: https://developer.apple.com/documentation/accelerate/vimage
- Metal compute functions: https://developer.apple.com/documentation/metal/compute_functions

SDK 校准点：

- `SCStreamOutputTypeScreen` 输出的是包在 `CMSampleBuffer` 里的 screen sample buffer，并带有 ScreenCaptureKit frame metadata。
- `SCStream.addStreamOutput(_:type:sampleHandlerQueue:)` 是实时样本入口。
- `SCRecordingOutput` 可以添加到 `SCStream`，写出录制文件；当前项目已有 `ScreenCaptureKitMovieRecorder` skeleton。
- `SCScreenshotManager.captureSampleBuffer` 可返回单帧 `CMSampleBuffer`，适合作为补帧或一次性取样；Repeat-Until 的持续观察不应靠反复单帧截图拼起来。
- `VNImageRequestHandler` 支持 `CMSampleBuffer` 输入；Vision 可以直接消费 ScreenCaptureKit 的 live sample buffer 或裁剪后的 `CVPixelBuffer`。
- `VNGenerateImageFeaturePrintRequest` 生成 `VNFeaturePrintObservation`，`computeDistance` 可以比较两个 feature print；距离越大越不相似。
- 当前 SDK 没有在 quick grep 中确认 `vImageAbsoluteDifference_ARGB8888` 这个精确符号；实现 spike 应把方案写成 Accelerate 管线：vImage 做格式/ROI/通道准备，vDSP/BNNS 或可用的 vImage primitive 做差值、绝对值、阈值和统计。不要在计划里绑定一个未验证函数名。

## Current State

当前项目已经有几个重要基础：

- `ScreenCaptureKitMovieRecorder` 用 `SCRecordingOutput` 写 `.mov`，并在 finish 时拒绝缺失或空文件。
- `ScreenCaptureKitFrameSource` 用 `SCScreenshotManager.captureImage` 写 keyframe PNG。
- `ScreenCaptureKitLiveFrameSource` skeleton 可以启动 `SCStreamOutput(.screen)`、接收 complete `CMSampleBuffer` 并产出低成本 `AutomationVisualFrameSample` metadata stream；它也提供 app-edge-only raw live frame wrapper，后续 detector job 可以在不污染 core 的情况下消费最新 `CMSampleBuffer`。它不运行 Vision/Accelerate，也不声明 live product evidence 完成。
- `AutomationVisualLatestFrameRouter` / `AutomationVisualFrameCropper` app-edge first slice 可以保存最新 image frame，根据 core route 把 selected/window/full-display ROI 映射到像素 crop，并把 crop 交给后续 detector；测试使用合成 `CGImage`，不启动 ScreenCaptureKit/Vision。
- `AutomationVisualPollingDispatcher` app-edge first slice 可以按 polling cadence 调用 fake/prototype detector，跳过 stale frame，只在新帧到来时再次 dispatch；测试覆盖 fresh-frame match、stale-frame exhaustion 和 route failure。
- `AutomationVisualFrameDetectorClient.ocrText` / `AutomationVisualTextDetectorClient` app-edge first slice 可以对 routed crop 运行可注入 OCR detector；默认 live factory 走 `VisionDetector.detectText(in:)`，单元测试用 fake text detector 证明 contains/exact matching、routed crop 尺寸和 OCR normalized bounds -> display/window region 回投。
- `AutomationVisualFrameDetectorClient.featurePrintImage` / `AutomationVisualFeaturePrintClient` / `AutomationVisualImageLocatorClient` app-edge first slices 可以对 routed crop 和模板图运行可注入 feature-print distance detector，也可以在 routed ROI 内做 fixture-safe template locator；默认 live feature-print factory 走 `VNGenerateImageFeaturePrintRequest` + `VNFeaturePrintObservation.computeDistance`，单元测试用 fake distance / locator 证明 image appeared/disappeared、distance threshold evidence、locator similarity/threshold/local bounds 和 watched-pattern region 回投。
- `AutomationVisualConditionEvaluatorClient.live` 的现有 Workflow visual condition path 也会在 `imageAppeared` / `imageDisappeared` evidence 中输出 template locator similarity、threshold 和相对 watched region 的 local bounds；测试用注入 display/template `CGImage`，不触发真实 ScreenCaptureKit。
- `AutomationVisualFrameDetectorClient.pixelColor` app-edge first slice 可以在 routed crop 中采样显式 normalized/display/crop-local point，或在用户 selected region 中无显式 point 时采样中心点；当前默认取 3x3 small-radius average，且 `AutomationVisualCondition.pixelSampleRadius` / draft `pixelSampleRadius` / Task Inspector / AI Draft Preview / CLI `--pixel-sample-radius` 可以把半径调到 0...8。单元测试证明 sampled color、target color、similarity threshold evidence、sample radius/count fields、sampled region 回投、单点噪声容忍，以及 radius=0 strict center behavior。
- `AutomationVisualFrameDetectorClient.regionDiff` app-edge first slice 可以把 routed crop 与 baseline image 做 fixture-safe bitmap sampling comparison；单元测试证明 region changed 的 baseline ref、change score、threshold evidence、changed ratio / max delta / sample count fields、matched watched region 和 missing-baseline rejection。
- `VisionRecordingIndexer` 从存储的 frame PNG 运行 Vision OCR，产出 `RecordingVisualObservation.ocrText`。
- Workflow visual condition 已有 `ocrText`、`imageAppeared`、`imageDisappeared`、`regionChanged`、`pixelMatched` 的 draft/core/UI first pass。
- OCR 条件已经按 `searchRegion` crop 后再识别；无区域时才扫描整个显示器。
- fixed-count draft loop 已有 first pass，并在 import 前展开成 acyclic workflow。2026-07-08 新增 bounded Repeat-Until import first slice：`AutomationWorkflowDraftLoop.kind = repeatUntil` 必须带 `until` condition 和 `maxAttempts`，`AutomationWorkflowDraftLoopExpander` 会把它降低为普通 DAG：每轮执行 body、轮尾检查 until，`conditionNotMatched` 进入下一轮，任意一轮 `conditionMatched` 通过 `firstMatched` complete 节点提前退出；`onFailure = continue` 会在最后一次未命中后继续，`requireManualApproval` 会生成人工确认出口，`failRun` 首版让后续路径不触发。Draft Preview 现在显示最多导入步数和 acyclic import 边界。foreach、结构化 runtime loop evidence 和 graph container 编辑仍未实现。
- `SemanticRecordingReviewDraftPatchBuilder` 现在可以把 Review condition candidate + 用户框选 frame crop + 明确提供的 body draft tasks 生成 bounded `repeatUntil` loop patch：继续 upsert visual region/image/baseline assets，把候选条件写入 `loop.until`，并保留 max attempts / timeout / polling / failure policy。测试覆盖 image disappeared candidate、manual frame crop asset extraction、Draft Preview loop row 和 bounded import path。
- `SemanticRecordingReviewRepeatUntilBodyResolver` / `SemanticRecordingReviewFixtureView` 已有 Review UI body first slice：当前 bundle 能通过 `SavedMacro.semanticRecording.recordingID` 解析 linked macros；唯一 linked macro 会自动作为 `Do` body，多 linked macros 会暴露 `Body` 菜单让用户选择，调用方也可以显式提供 preferred macro id；无 linked macro 时仍不会猜测循环体。测试覆盖唯一 linked macro、body options 排序、ambiguous guard、preferred macro 消歧，以及 resolved macro body -> bounded repeat-until patch。
- Macro Editor 已有 OCR 文本类 Repeat-Until first slice：用户选中一段可执行行为和一个 `Wait Text` / `Wait Text Gone` / `Verify Text` 条件后，sidebar 可以把选中行为保存成新的 behavior macro，并打开 bounded Repeat-Until Preview。builder 会把 body event 时间归一化、清除原 behavior metadata，把 until 条件写成 `ocrText`，优先保留 content-normalized search region，并带默认 `maxAttempts` 通过 Draft Preview 的 bounded DAG import path。当前 slice 不处理图标/图案、区域变化、像素条件，也不提供 graph loop runtime。
- `AutomationVisualRepeatUntil.swift` 已提供纯 core first slice：frame sample metadata、selected/window/full scope、scope inference、detector request/result、frame route ROI resolution、implicit full-display fallback audit flag、native detector score threshold、Repeat-Until policy、attempt evidence 和 loop state transition；`AutomationVisualRepeatUntilTests` 覆盖 detector mapping、feature-print distance threshold、region-diff threshold、scope/safe refs、selected-region routing、target-window default routing、implicit full-display fallback、unavailable ROI rejection、max attempts、timeout 和 manual-approval exhaustion。

当前缺口也很明确：

- 还没有 `SCStreamOutput -> live CMSampleBuffer image frame -> production OCR/Vision/Accelerate detector` 的完整产品 evaluator；core scope/ROI route contract、app-edge raw frame stream、latest-frame store、`CGImage` ROI crop、fake/prototype polling dispatch、可注入 OCR routed-crop detector、可注入 feature-print routed-crop detector、live visual condition template locator evidence、pixel routed-crop sampler 和 region-diff routed-crop sampler first slice 已有。
- 还没有 recorded crop feature-print precompute/cache、production 多尺度/full-window locator、Accelerate/Metal-backed region diff、region diff runtime/storage persistence、Lab/display-profile color matching 和 live product proof；deterministic verifier 与 fixture-safe routed-ROI template locator 已有 first slice，但还不是 product-ready image locator。
- 没有从 recorded frame crop 到 repeat-until visual condition 的完整产品 UX。当前已完成 builder/API first slice、linked saved macro body resolver、Review linked-macro `Body` 菜单、Review `Repeat Until` action、Macro Editor selected body + OCR text until draft preview first slice，以及 Workflow draft/preview/import-gate 表达；尚未完成 Macro Editor 图标/图案/region/pixel 条件入口、跨宏/任务组合 body picker、graph loop node 预览/编辑和 live product evidence 的完整产品路径。
- 还没有把 Repeat-Until state 接入结构化 Automation runtime loop evidence；bounded `kind = repeatUntil` 当前会在 import 前展开为普通 DAG，所以 reducer/runtime 可以执行，但 run history 还不会把多轮尝试折叠成一个 loop attempt evidence 模型。
- 没有 product-ready live evidence 证明 ordinary Recorder 产生真实 `.mov` / keyframe bundle 并被 Review / CLI / Workflow 消费。

## Product Shape

Repeat-Until 不应该是纯线性缩进代码块，也不应该是自由节点图里任意拉一条回边。

推荐产品形态是：Workflow 画布里的结构化循环节点。

```text
Repeat Until
  Do: bound behavior / macro / task group
  Until: text appears / image appears / image disappears / region changed / pixel matched
  Guardrails: max attempts, timeout, polling interval, cooldown, failure policy
```

中心画布表达为一个 loop container node：用户能看到“先执行行为 -> 检查条件 -> 未满足则回到行为 -> 满足后继续”。这个回路是 UI 上的结构化 return ribbon，不是底层 dependency graph 的任意 cycle。

这条决策原因：

- 当前 Workflow 页面已经以 FlowGraph、branch evidence、timeline 为产品方向；Repeat-Until 是控制流，放在 graph 里比藏在 Inspector 更符合用户直觉。
- 纯 Shortcuts 式嵌套块在小脚本里清楚，但在 SparkleRecorder 里用户还需要同时看到 macro source bin、视觉证据、运行 timeline 和失败 evidence。
- 自由节点成环会让 reducer、validation、run evidence、cancel/timeout 和资源锁复杂度暴涨，也会冲突当前 dependency cycle rejection。
- 结构化循环节点可以向用户展示循环，但让 core/runtime 用明确的 loop state machine 执行，而不是让任意图结构控制执行。

Macro Editor 的首版入口应该更轻：

- 用户选中一段连续行为。
- 用户同时选中一个文本类 visual wait：`Wait Text`、`Wait Text Gone` 或 `Verify Text`。
- sidebar 选择 `Preview Repeat Until`。
- 系统把选中行为另存为一个 behavior macro，再打开 Workflow Draft Preview：`Do` 指向新 body macro，`Until` 指向 OCR 文本条件和已记录的 search region。
- Macro Editor 不承担复杂嵌套循环编辑；它继续做录后清理、绑定行为、修正点击/等待。

2026-07-07 已落地的 Macro Editor 入口只覆盖上面的 OCR 文本类路径。2026-07-08 后，带 `maxAttempts` 的 Repeat-Until draft 可以先走 bounded acyclic import path。下一步要把用户从录制帧里框选图标/图案、baseline region 或 pixel sample 的 Review/Macro Editor affordance 接进同一个 Draft Preview 合同；graph container、结构化 runtime state machine 和 attempt evidence 仍属于后续 Workflow/runtime work。

## User Journey

第一条用户路径应长这样：

```text
Record
  -> Review recording frames
  -> Select a region / text / icon / pixel / baseline
  -> Choose "Repeat this behavior until..."
  -> See generated Workflow draft
  -> Adjust scope, threshold, timeout, max attempts
  -> Validate / simulate
  -> Import
  -> Run
  -> Inspect attempt evidence if it fails
```

用户在 UI 里不应该先看到 `VNGenerateImageFeaturePrintRequest`、`CMSampleBuffer` 或 `vDSP_vsub`。用户应该看到：

- 等待文本出现
- 等待图标出现
- 等待图标消失
- 等待这个区域变化
- 等待颜色/像素变成这样
- 在这个窗口中找
- 只在这个框里找
- 最多重复几次
- 超时后停止 / 报错 / 继续下一步

## Image Source Architecture

首版 live observation 架构：

```text
SCShareableContent
  -> SCContentFilter(window or display)
  -> SCStream
      -> SCRecordingOutput (.mov evidence)
      -> SCStreamOutput(.screen, CMSampleBuffer live samples)
          -> FrameRouter
              -> ROI crop
              -> Detector jobs
              -> ConditionEvaluationResult + evidence
```

关键边界：

- App target 持有 `SCStream`、`CMSampleBuffer`、Vision、Accelerate、Metal 和文件写入。
- Core target 只定义 value contracts：condition request、detector config、score、threshold、attempt evidence、loop policy、failure policy。
- SwiftUI 只渲染 projection / presenter result，并发送 accepted intent。
- Unit tests 用 fake frame samples、fixture bitmaps、fake detector clients，不启动 ScreenCaptureKit、Vision、AX 或真实输入。

`SCScreenshotManager.captureImage` 可以继续服务 keyframe PNG 和低频补帧，但 Repeat-Until 的运行时等待应接入 `SCStreamOutput`，因为它需要持续观察、丢弃过期帧、按 polling cadence 处理最新样本。

## Frame Router

Frame Router 是性能和隐私的核心。它不把每一帧广播给所有 detector，而是按条件订阅处理。

每个 active visual condition 应声明：

- target surface：窗口、显示器、或 workflow visual asset package root。
- scope：selected region、target window、full display。
- detector：OCR、feature print image、region diff、pixel color。
- polling interval：例如 250ms / 500ms / 1s。
- stability requirement：连续 N 次满足，或满足后等待 cooldown。
- evidence policy：保存 last sample、matched crop、score/threshold、source frame/baseline refs。

运行时策略：

- `SCStreamOutput` 回调只保留最新可用 sample buffer，不在主线程做重活。
- 到达 condition 的 polling tick 时，取最新 complete frame。
- 先做 coordinate transform 和 ROI crop，再运行 detector。
- 多个 condition 共享同一 target stream，但 detector job 有预算和取消能力。
- 默认不做全屏滑动窗口；只有用户选择 full window/full display 或 AI suggestion 明确要求，才扩大搜索。
- 失败或超时时保存最后一次 watched region 和评分，不保存无界全屏样本。

## Detector Ladder

### OCR Text

用途：文字出现、文字消失、点击文字、验证文字。

实现路径：

- 对 resolved `searchRegion` crop 后运行 Vision `VNRecognizeTextRequest`。
- 记录 text、bounds、confidence、frame id、scope、provider version。
- 无 region 时只扫描用户绑定窗口或显示器；UI 必须显示 `Scope: full window/display`，避免用户误以为只看某个框。

边界：

- OCR 不识别图标含义。
- OCR 可以辅助定位按钮文字，但不能替代 image/pattern matcher。

### Image Appeared / Disappeared

用途：图标、按钮、加载状态、某个 UI pattern 出现或消失。

推荐首版路径：

1. 用户从录制帧中裁出目标小图。
2. 存储 source frame id、crop bounds、search region、thumbnail、hash 和 feature print。
3. 运行时从 selected region 或 target window 中生成候选 crop。
4. 用 `VNGenerateImageFeaturePrintRequest` 生成 runtime feature print。
5. 用 `VNFeaturePrintObservation.computeDistance` 得到 distance。
6. distance 小于阈值时视为候选命中，再用 deterministic verifier 复核。

阈值不应写死成产品真理。`15.0` 可以作为调试默认或 calibration seed，但 UI 和证据必须显示实际 score、threshold、candidate crop 和 source crop。

当前 first slice 已经把 `AutomationVisualFrameDetectorClient.featurePrintImage` 接到 routed crop：`imageAppeared` 在 distance <= threshold 时 matched，`imageDisappeared` 在 distance > threshold 时 matched，并把 distance/threshold 写入 `AutomationVisualDetectorResult.score`。2026-07-07 的后续切片加入可注入 `AutomationVisualImageVerifierClient`，可以用 fixture-safe pixel/template similarity 对 Vision feature-print 的粗命中做第二阶段复核，并把 verifier similarity/threshold 写入 diagnostic fields；测试覆盖 false-positive 被复核拒绝和 verifier 接受后的命中。同日的 template locator slice 加入可注入 `AutomationVisualImageLocatorClient`，可以在用户 routed ROI 内滑动搜索模板小图，输出 locator similarity/threshold/local bounds，并把命中图案框回投到 display region；测试覆盖 feature-print 粗距离未命中但 locator 找到图案，以及 feature-print 粗距离命中但 locator 未找到时把 `imageDisappeared` 判为满足。这个 slice 仍不是完整 product locator：它不做 recorded crop feature-print 预计算/缓存、多尺度候选、全窗口高性能搜索、边缘/梯度复核或 live bundle product evidence。

Vision feature print 的价值是容忍缩放、轻微颜色变化和截图压缩；它不是精确 UI locator。对小图标、细线按钮和文本图形，首版应采用两阶段：

- coarse: feature print / perceptual hash / metadata prefilter
- verify: crop/template score、edge/gradient similarity、尺寸比例约束、邻近 OCR/AX 语义

### Region Changed

用途：等待页面加载完成、等待某个区域刷新、等待 spinner 消失后区域稳定。

实现路径：

- 录制/教学时保存 baseline crop。
- 运行时裁剪同一 ROI。
- Accelerate 管线计算 baseline 与 runtime 的差异。
- 输出 changedPixelRatio、meanDelta、maxDelta、score、threshold。

实现 spike 应校准具体 primitive。当前 SDK 搜索未确认 `vImageAbsoluteDifference_ARGB8888` 精确符号，所以首版更稳的写法是：

- vImage / CoreVideo 准备 ROI buffer 和像素格式。
- 必要时抽取 luminance 或 RGB channels。
- vDSP 做向量 subtract、absolute value、threshold/statistics，或选择 SDK 中可用的 vImage/BNNS primitive。
- 小中 ROI 走 CPU Accelerate；大 ROI 或高频监控再上 Metal compute。

Region changed 不等于 image appeared。它只证明“这块变了”或“这块稳定了”，不证明出现了某个具体图案。

当前 first slice 已经把 `AutomationVisualFrameDetectorClient.regionDiff` 接到 routed crop：它通过 injected baseline provider 读取 baseline crop，用 fixture-safe bitmap sampler 输出 `changeScore`，并以 `changeScore >= threshold` 判定 `regionChanged`。2026-07-07 的后续切片把 metrics 加入同一 detector：`observedSummary` 会报告 changed sample ratio、max delta 和 sample count，`AutomationVisualDetectorResult.fields` 也会携带 `baselineRef`、`changeScore`、`changedRatio`、`maxDelta`、`sampleCount` 和 `threshold`；测试覆盖全变、不变、半区域变化和 legacy payload decode。这个 slice 仍不是最终性能实现：它还没有 Accelerate/vDSP/Metal backend，也没有 live `CMSampleBuffer` product proof。

### Pixel Matched

用途：等待某个状态灯、颜色块、开关状态。

实现路径：

- 用户选择一个点或小半径样本。
- 存储 coordinate space、source frame id、sampled color、tolerance。
- 运行时在 ROI 中取样，比较 RGB 或 Lab distance。
- 输出 sampled color、target color、distance、threshold。

Pixel matcher 很快，但脆弱。UI 应提示它适合稳定颜色，不适合动态阴影、抗锯齿文字或不同显示 profile 的复杂图案。

当前 first slice 已经把 `AutomationVisualFrameDetectorClient.pixelColor` 接到 routed crop：显式 `pixel` 可作为 watched crop 内 normalized point、display point 或 crop-local point；如果用户明确选了 selected region 但未保存 point，则采样该 selected region 的中心点。2026-07-07 的后续切片把单点采样升级为默认 3x3 small-radius average，并把 sampled color、target color、similarity、threshold、sample radius 和 sample count 写入 `AutomationVisualDetectorResult.fields`；再进一步的切片把采样半径升为可配置合同/UI/CLI 字段，0 表示严格单点，1 表示 3x3，2 表示 5x5，上限 8。它仍不是完整色彩鲁棒检测：不做 Lab distance、显示 profile 校正或复杂阴影策略，也没有 live product proof。

### Metal Compute

Metal 不做首版默认路径。只有当这些证据出现时再升级：

- ROI 很大，Accelerate CPU 路径影响录制/播放流畅度。
- 多个视觉条件同时高频运行。
- 需要在 GPU texture 上直接做并行 diff / threshold / reduction。

Metal path 的产品语义不变，只替换 detector backend；CLI/UI/evidence 不应该知道它用了 CPU 还是 GPU。

## Repeat-Until Runtime Semantics

Repeat-Until 不是连续播放宏的另一个名字。它是“执行 body，观察 condition，未满足则再次执行 body”的结构化运行状态。

建议 core contract：

```text
AutomationLoopPolicy
  kind: repeatUntil
  bodyTaskIDs or bodyDraftTasks
  conditionTaskID / condition spec
  maxAttempts
  timeout
  pollingInterval
  cooldown
  onFailure: failRun | continue | requireManualApproval
```

执行规则：

1. attempt 开始，记录 attempt index。
2. 执行 body。
3. 进入 condition waiting。
4. 满足则 loop completed，继续下游 task。
5. 不满足且未超限，进入下一 attempt。
6. 超时或 max attempts 用 `onFailure` 决策。
7. 每次 attempt 保存 condition score/threshold/evidence summary；只在策略允许时保存 artifact crop。

第一版不要把 Repeat-Until 表示成 dependency graph 回边。当前 fixed-count draft loop 在 import 前展开成 acyclic workflow；Repeat-Until 因为依赖运行时条件，不能简单无界展开。它需要 Owner 1 增加结构化 loop state 或先保留在 Draft Preview / simulation 阶段，不应偷偷变成不受控 cycle。

## UI / UX Contract

Repeat-Until 节点在画布上的信息层级：

- Title：Repeat Until
- Body summary：要重复的行为或宏名
- Until summary：等待文字 / 图标 / 区域变化 / 像素状态
- Scope chip：selected region / target window / full display
- Guardrails：max attempts、timeout、polling
- Evidence affordance：source crop、runtime last sample、score/threshold

Inspector 负责精修：

- 切换 detector kind。
- 选择或重画 search region。
- 调整 threshold。
- 设置 max attempts / timeout / polling interval。
- 设置失败策略。
- 查看 source/runtime crop。

Review 负责教学：

- 从录制帧上框选文字、图标、区域或像素。
- 把框选结果保存为 draft visual asset。
- 生成 repeat-until draft patch。
- 用户确认后才进入 Workflow Draft Preview / import。

CLI 负责低 token 协作：

- `recording frames` / `events-near` 找到候选时刻。
- `recording ocr search` 找文字。
- `recording visual search` 先返回 persisted visual observations 和 metadata；image-byte similarity 后置到 product-ready live bundle 稳定后。
- `recording asset extract` 把用户/AI 明确选择的 frame crop 变成 package-local visual asset。
- `recording suggest waits/conditions` 给出 evidence refs、confidence、risk、fallback，不直接修改 macro。

## AI Explainability

AI 能帮我们优化人工录制的瑕疵，但前提是它看到的是可解释证据，而不是一整段视频黑箱。

每个 AI suggestion 应引用：

- source recording id
- event id / frame id
- source crop ref
- search region ref
- detector kind
- score / threshold
- confidence / risk
- fallback if detection fails

AI 可优化的内容：

- 把固定 wait 改成 OCR 或 visual condition。
- 把坐标点击改成 click text 或 image locator。
- 缩小 search region，降低误检。
- 调整 polling / timeout / max attempts。
- 把重复人工尝试变成 Repeat-Until。
- 将同一 app 下已有宏、视觉锚点和等待条件组合成新 workflow draft。

AI 不应该直接：

- 扫完整视频并输出最终 workflow。
- 写内部 Codable JSON。
- 绕过 Draft Preview/import。
- 在没有 evidence refs 的情况下生成高置信 locator。

## Workstream Split

| Workstream | Scope |
| --- | --- |
| S1/Core | 定义 loop policy、visual detector score、attempt evidence、safe refs 和 fake-test contracts；不引入 ScreenCaptureKit/Vision/Accelerate。 |
| S2/App Capture | 新增 `SCStreamOutput` live frame source、ROI cropper、routed-crop OCR/feature-print/pixel/region-diff detector first slices、Accelerate/Metal production diff backend 和 artifact evidence writer。 |
| S3/Review UX | 从 recorded frame 选择 OCR/image/region/pixel，生成 visual asset 和 repeat-until draft patch；显示 source/runtime comparison。 |
| Owner 2/Workflow UX | 设计结构化 Repeat-Until graph node、Inspector guardrails、runtime attempt evidence 和 no-cycle UI contract。 |
| S4/CLI AI | 在 accepted live bundle 后补 product-ready visual similarity search、stored/live suggestions 和 draft-from-recording repeat-until generation。 |

## First Implementation Slices

1. [x] Contract slice：定义 `AutomationVisualFrameSample` / `AutomationVisualDetectorRequest` / `AutomationVisualDetectorResult` / `AutomationRepeatUntilAttemptEvidence` 等 core value model；fake tests 覆盖 threshold、attempt policy、timeout/max-attempt semantics。
2. [x] S2 live stream skeleton：app-edge 建 `ScreenCaptureKitLiveFrameSource`，通过 `SCStreamOutput(.screen)` 接收 `CMSampleBuffer` 并输出 sample metadata stream；现在也能为 app-edge detector 提供 raw live frame wrapper；尚未包含 ROI crop 或 detector jobs。
3. [x] Core frame route slice：根据 condition 和 `AutomationOCRSearchRegionContext` 推断 selected region / target window / full display scope，解析 processing ROI，并标记 implicit full-display fallback；fake tests 覆盖选区、窗口默认、全屏 fallback 和不可用 ROI。
4. [x] Latest-frame ROI crop slice：app-edge `AutomationVisualLatestFrameRouter` 保存最新 image frame，按 core route 裁剪 selected/window/full-display ROI；合成 `CGImage` tests 覆盖最新帧选择、display-to-pixel 坐标映射和 route unavailable 错误。
5. [x] Live stream polling / fake detector dispatch slice：按 polling cadence 取最新 image frame，避免重复处理 stale frame，并向 fake/prototype detector 交付 routed crop；tests 覆盖 fresh frame match、stale frame skip/exhaustion 和 sleep cadence。
6. [x] OCR routed-crop detector slice：让 OCR condition 可在 latest-frame routed crop 上通过可注入 fake/live Vision detector 评估，并把 matched OCR bounds 回投 watched region；live product proof 仍开放。
7. [x] Feature-print routed-crop detector slice：让 `imageAppeared` / `imageDisappeared` 可在 latest-frame routed crop 上通过可注入 fake/live Vision feature-print distance 评估，并写出 distance threshold evidence；可注入 deterministic verifier first slice 已能用 pixel/template similarity 复核粗命中并写出 verifier evidence；可注入 deterministic template locator first slice 已能在 routed ROI 内滑动找模板小图，写出 locator similarity/threshold/local bounds，并把命中框回投到 display region。
   recorded crop precompute/cache、production 多尺度/full-window locator 和 live product proof 仍开放。
8. [x] Pixel sampler slice：实现 routed crop selected point / selected-region center color sampler，默认 3x3 small-radius average，输出 sampled color、target color、similarity threshold、sample radius/count evidence；`pixelSampleRadius` 已贯通 core/draft/import/export/patch/Task Inspector/AI Draft Preview/CLI，并由 routed detector 与 live visual evaluator 消费；Lab distance / display-profile robustness 仍开放。
9. [x] Region diff slice：实现 fixture-safe routed-crop baseline/current sampler，固定输出 score/threshold/evidence，并在 summary 与 `AutomationVisualDetectorResult.fields` 中输出 changed ratio / max delta / sample count；Accelerate/vDSP/Metal primitive spike、runtime/live persistence 和 live evidence 仍开放。
10. [ ] Product UX slice：Workflow Draft Preview 的 bounded `repeatUntil` loop intent / until summary / guardrails / acyclic import first slice 已完成；Review Draft Patch Builder 可以从 frame crop condition candidate + body draft tasks 生成 repeat-until patch；Review 产品 UI 里选择 body 行为并一键生成 `imageAppeared` / `imageDisappeared` / `regionChanged` / `pixelMatched` repeat-until draft 仍开放；完整 graph loop node 与结构化 runtime attempt evidence 仍按 Owner 1 contract 状态控制。
11. [ ] Runtime loop slice：Owner 1 增加结构化 Repeat-Until state machine、attempt evidence 和 cancel/timeout behavior；拒绝 arbitrary dependency cycles。

## Acceptance Gates

不能因为本文存在就把功能标完成。验收至少需要：

- macOS 15+ authorized live bundle：真实 `.mov`、event-aligned keyframes、OCR/window/AX sidecars、readiness diagnostics。
- `SCStreamOutput` live sample path：能够在条件等待时处理 `CMSampleBuffer`，并保存 watched-region evidence。
- OCR scope proof：选区 OCR 只看选区；full-window/full-display 必须由用户明确选择。
- Image appeared/disappeared proof：recorded frame crop -> visual asset -> runtime match score/threshold -> evidence artifact。
- Region changed proof：baseline crop -> runtime crop -> diff score/threshold -> evidence artifact。
- Repeat-Until UX proof：用户从录制行为和 frame target 生成结构化 loop draft，看见 max attempts/timeout/polling/failure policy。
- Runtime proof：attempt history、condition evidence、timeout/max-attempt/cancel 都能在 graph + timeline + Run Detail 中解释。
- Safety proof：敏感窗口、Secure Input、password field、exclusion 和 retention/cleanup 不会把私密帧静默暴露给 AI。

## Non-Goals

- 不使用 `CGWindowListCreateImage` 或 `AVCaptureScreenInput` 作为首版图像源。
- 不做 every-frame OCR。
- 不把 Vision 当成任意图标语义识别器。
- 不让 SwiftUI 调用 ScreenCaptureKit、Vision、Accelerate、Metal 或 raw file IO。
- 不把 Repeat-Until 做成任意 graph cycle。
- 不在没有 live bundle evidence 前声明 S3/S4 product-ready。
- 不默认把图片 bytes、视频 bytes 或完整帧送给 AI；CLI 默认返回 evidence refs 和 compact metadata。

## Relationship To Existing Docs

- [07-apple-api-implementation-path.md](07-apple-api-implementation-path.md) 记录 macOS 15+ ScreenCaptureKit/Vision/AX 总路线。
- [11-user-logic-roadmap-and-scope-audit.md](11-user-logic-roadmap-and-scope-audit.md) 记录用户动作词汇、OCR/visual scope 和 loop open gate。
- [15-s2-live-evidence-playbook.md](15-s2-live-evidence-playbook.md) 记录 S2 live bundle 取证路径。
- [workstreams/s2-app-capture-visual-index.md](workstreams/s2-app-capture-visual-index.md) 记录 S2 app-edge capture 当前状态。
- [../workflow-page-productization/workstreams/product-ui-ux.md](../workflow-page-productization/workstreams/product-ui-ux.md) 记录 Owner 2 Workflow UI 产品方向。

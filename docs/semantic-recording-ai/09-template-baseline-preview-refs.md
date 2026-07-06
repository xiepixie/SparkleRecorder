# Template And Baseline Preview Refs

更新时间：2026-07-06
状态：S1 accepted first-pass core contract
Requesting owner：S0 Workflow Evidence Closure
Target owner：S1 Contract And Core Schema

当前 Workflow 已有 `imageRef`、`baselineRef`、visual asset registry、condition diagnostics artifact refs 和 Run Detail first pass。但从用户角度看，字符串 ref 仍然不够：用户需要看到“录制时拿什么当模板/基准”和“运行时系统实际看到了什么”，再理解为什么通过、失败或走了某条分支。

本文定义 S0 对 S1 的合同需求。S1 可以调整类型命名，但需要保留这些语义，让 S2/S3/S4 不再各自发明 preview/ref 结构。

## 1. User Problem

用户不会自然理解 `imageRef: confirm-button` 或 `baselineRef: battle-result-panel`。用户真正想知道：

- 这个 ref 指向哪一次录制的哪一帧、哪块区域？
- 运行时最后一次截图看到的区域是什么？
- 系统用了什么 matcher、score 和 threshold 做决定？
- 如果 ref 丢了、图像解码失败、区域越界或 sample 不可读，下一步该检查哪里？

所以 preview ref 不是装饰 UI。它是用户能不能信任 visual condition、AI suggestion 和 branch evidence 的核心证据。

## 2. Product Shape

Run Detail / future Review UI should be able to render this shape:

```text
Source Reference
  recorded frame or package asset thumbnail
  source frame/event/surface ids
  crop/search bounds

Runtime Sample
  last display sample or watched-region crop
  capturedAt / runID / taskID

Decision
  outcome, score, threshold
  matcher kind/version
  fallback or failure reason
  optional diff artifact
```

For `imageAppeared` / `imageDisappeared`, Source Reference is an image template.
For `regionChanged`, Source Reference is a baseline region.
For `pixelMatched`, Source Reference is a coordinate/color sample plus optional tiny source crop.
For OCR/text conditions, Source Reference is the selected source-frame OCR region when it exists; otherwise UI should say the condition has no recording-backed source ref.

## 3. Requested S1 Semantics

S0 requests S1 to define versioned value-model support for these concepts.

### Source Preview Ref

Required semantics:

- stable `refID`
- `kind`: `ocrRegion`, `imageTemplate`, `regionBaseline`, `pixelSample`
- optional `recordingID`
- optional `frameID`
- optional `eventID`
- optional `surfaceID`
- `artifactRef`: safe relative path to thumbnail/template/baseline/source crop when available
- `bounds`: crop/search bounds in a declared coordinate space
- `imageSize`
- `createdAt` or recording-relative time
- optional `contentDigest`
- optional user-facing `label`

### Runtime Sample Ref

Required semantics:

- stable `sampleID`
- `runID`
- `taskID`
- optional `conditionID`
- `artifactRef`: safe relative path to display sample, watched-region crop, or decoded preview
- `capturedAt`
- `bounds` and coordinate space
- `imageSize`
- optional `contentDigest`

### Preview Comparison

Required semantics:

- source preview ref id
- runtime sample ref id
- `outcome`: matched, changed, unchanged, missingSource, missingSample, unreadable, rejected, unavailable
- `score`
- `threshold`
- matcher kind/version
- optional `diffArtifactRef`
- optional failure/fallback reason

## 4. Relationship To Existing Workflow Types

Do reuse:

- `AutomationWorkflowDraftVisualAssets.regions/images/baselines`
- workflow/package-local visual asset refs
- `AutomationConditionDiagnosticArtifact`
- `AutomationTaskRun.conditionEvidence`
- `AutomationConditionEvidenceArtifactPresenter`
- `AutomationTaskRunEvidencePresenter`

Do not create:

- a separate global visual asset library in S0
- absolute file paths in SwiftUI
- UI-only IDs that cannot be traced back to bundle/run evidence
- AI-only image refs that cannot be rendered to the user

## 5. S0 Acceptance Criteria

The contract is accepted when S1 can provide fixture values proving:

- source template/baseline refs round-trip through a bundle or workflow fixture
- runtime sample refs can point to the existing condition diagnostic artifact path shape
- source and runtime previews can be compared without SwiftUI reading raw paths
- missing/unreadable/unsafe refs have explicit states, not silent empty UI
- the same refs can be cited by CLI/AI suggestions without embedding image bytes by default

S0 marked the fixture-level semantic checklist item complete after S1 accepted this contract and `docs/workflow-page-productization/product-evidence/template-baseline-preview-refs.png` rendered the source-reference/runtime-sample/decision shape. The user-facing Review/Run Detail integration remains open for S3.

## 6. Open Questions For S1

- Should source preview refs live inside `SemanticRecordingBundle` only, or can workflow packages also persist a copied source preview?
- Should `contentDigest` be required for all image artifacts, or only for package-local assets?
- Should matcher version be a string owned by S1 or a provider-specific field owned by S2?
- How should privacy/suppression records hide source previews while still keeping the condition understandable?

## 7. S1 Response

Accepted in first-pass core schema v0:

- source preview refs map to `RecordingSourcePreviewReference`
- runtime sample refs map to `RecordingRuntimeSampleReference`
- decision payloads map to `RecordingPreviewComparison`
- matcher identity maps to `RecordingMatcherDescriptor`
- outcomes map to `RecordingPreviewComparisonOutcome`
- safe paths map to `RecordingArtifactRef`
- missing/unreadable/deferred states are explicit validation or comparison outcomes

Open-question answers for v0:

- Source preview refs live in `SemanticRecordingBundle` first. Workflow packages may later persist copied source previews, but they should preserve the same stable ids and safe relative artifact refs instead of creating UI-only ids.
- `contentDigest` is optional in v0. S2/S3 should provide it when copying package-local image assets or when stale/missing diagnostics need content identity.
- Matcher version is a S1 value field (`RecordingMatcherDescriptor.kind/version/provider`). S2 owns the actual matcher implementation and version values.
- Suppressed evidence should keep a `RecordingSuppressionRecord` with reason/count/redacted ref when available. UI/CLI should render “withheld because ...” rather than silently dropping the source preview.

Verification: `SemanticRecordingBundleTests.previewRefsRoundTripSourceRuntimeSampleAndComparisonSemantics` proves the requested source/runtime/comparison shape round-trips through a bundle fixture.

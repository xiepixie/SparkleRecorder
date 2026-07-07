# S4 CLI AI And App Knowledge

更新时间：2026-07-07
状态：fixture/explicit stored-bundle/default-root explain/readiness/macro-link/artifact audit, fixture OCR/visual query, persisted stored-bundle deterministic suggestion synthesis, deterministic suggestion query/result availability contract, no-evidence suggestion low-confidence guard, retention-pruned deleted-artifact status, read-only CLI, explicit asset extraction, low-token transcript and fixture workflow draft-from-recording first passes done; product-ready live work paused until S2 live bundle evidence and S3 Review alignment are accepted
Owner：S4, CLI / AI collaboration / later App Knowledge
并行对象：S1 Contract/Core, S2 App Capture/Visual Index, S3 Review UX

S4 的任务是把 semantic recording bundle 暴露给 AI 和高级用户，让它们能查询本地证据、提出可审阅建议、生成 workflow draft。S4 不负责 live capture、不负责 Review UI，也不负责让 AI 直接运行自动化。

当前 S4 first pass 暂告一段落。Fixture、explicit stored-bundle 和 default-root read-only CLI 已经足够证明低 token 查询模式；stored-bundle suggestion 现在有一条 metadata-only、Review-only 第一刀，但 product-ready live catalog/search/cleanup suggestion/draft 工作必须等待 S2 产出 accepted live bundle evidence，并等待 S3 的 Review/Draft Preview live 边界稳定。S0-S4 总差距维护在 [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md)。

## 1. Scope

S4 owns:

- `recording list/show/explain/readiness --json`
- `recording macro-links --json`
- `recording frames/frame show/events-near --json`
- `recording ocr search --json`
- `recording visual search --json`
- `recording asset extract/baseline --json`
- `recording suggest waits/locators/conditions/cleanup --json`
- `workflow draft from-recording --json`
- `workflow macros --json` semantic recording link visibility
- CLI JSON envelope and low-token evidence selection
- later app/macro/surface/anchor grouping for App Knowledge

S4 does not own:

- direct writes to internal workflow storage without validate/simulate/import
- direct execution of generated workflow drafts
- workflow runtime semantics such as dependency dynamic delays, structured loop execution, timers or resource arbitration
- live ScreenCaptureKit, Vision, AX or file IO implementation
- SwiftUI Review UX
- MCP-only logic path
- full-video upload by default

## 2. Current State

Already available for S4:

- `sparkle.workflow.draft.v1` validate/simulate/dry-run/import/edit/patch first pass exists in Workflow CLI.
- `AutomationCLIResult` / `sparkle.cli.result.v1` style envelope direction exists.
- S1 has `SemanticRecordingBundle`, `RecordingFrameReference`, `RecordingVisualObservation`, `RecordingQueryResult`, `RecordingSuggestion` and safe `RecordingArtifactRef`.
- S1 has deterministic fixtures: `SemanticRecordingFixture.checkoutBundle()`, `checkoutQueryResults()` and `checkoutSuggestions()`.
- S1/S4 now share `SemanticRecordingQueryEngine`, a pure core query boundary for fixture OCR search, persisted-bundle OCR search, deterministic fixture suggestion filtering and stored-bundle metadata suggestion synthesis. The OCR and suggestion result contracts are Codable and carry availability, query echo, matches/suggestions and unavailable reason when synthesis is not available, so future CLI/MCP/UI callers can tell fixture evidence, persisted bundle reads and unavailable live/product paths apart without guessing from warnings.
- S2 has fake-client capture session, app-edge live capture skeleton, first-pass `RecordingBundleStore` sidecar-aware load/catalog/readiness APIs, saved macro semantic recording references and a stable default App Support root exposed through `RecordingBundleStore.defaultRootDirectory`, but live bundle product evidence is not complete.
- S3 has fixture/stored Review projection, Run Detail Macro Review opener, Draft Preview handoff, and shared Review action semantics. Fixture suggestion envelopes now carry `reviewActions` for accept/reject/clear plus `reviewActionPresentations` rows, so CLI/AI payloads cite and display the same review-only mutation boundary used by Macro Review.

Not implemented yet:

- Default-root/id read-only CLI first pass exists: commands without `--fixture`, `--recordings-root` or `--bundle-path` use `RecordingBundleStore.defaultRootDirectory`, default-root next actions omit explicit temporary source options, `recording readiness` can audit fixture/explicit/default-root bundles with loaded/missing/failed sidecar diagnostics plus artifact file status/byte counts, and `recording macro-links` can audit saved macro references against the same root.
- No product-ready live catalog/explain yet; S2 now has a first-pass UUID directory name -> manifest id policy and default-root load path for stored bundle loading, but live search/suggestion discovery stays deferred until authorized live evidence and suggestion synthesis are stable.
- No image-byte visual similarity search yet; `recording visual search` currently filters persisted observation metadata only.
- Stored-bundle deterministic suggestion synthesis has a first pass for persisted OCR/image/pattern/region/pixel observations, and suggestion payloads can surface `artifactFiles` status for bundle artifacts including visual observation refs and retention/user-deleted refs. Product-ready live/default-root suggestions, cleanup suggestions and image-byte similarity remain open.
- No product-ready stored/live recording-to-draft compiler; fixture/review-only `workflow draft from-recording` first pass exists and still routes through validate/simulate/import.
- No App Knowledge index beyond planning.
- Product-ready S4 work is intentionally paused until the S2 live bundle / default root / S3 Review boundary gates in [../14-s0-s4-final-gap-alignment.md](../14-s0-s4-final-gap-alignment.md) are satisfied.

Implemented first slice:

- `recording list --fixture checkout --json`
- `recording show checkout-demo --fixture checkout --json`
- `recording explain checkout-demo --fixture checkout --json`
- `recording readiness checkout-demo --fixture checkout --json`
- `recording frames checkout-demo --fixture checkout --json`
- `recording frame show checkout-demo --frame <frame-uuid> --fixture checkout --json`
- `recording events-near checkout-demo --time <seconds> --window <seconds> --fixture checkout --json`
- `recording ocr search checkout-demo --text "Order" --fixture checkout --json`
- `recording visual search checkout-demo --kind imageTemplateCandidate --label button --fixture checkout --json`
- `recording asset extract checkout-demo --frame <frame-uuid> --region 1,2,80,40 --name checkout-button --fixture checkout --source-root <fixture-artifact-root> --output-root <draft-package-root> --json`
- `recording asset baseline checkout-demo --frame <frame-uuid> --region 0,0,120,80 --name checkout-baseline --fixture checkout --source-root <fixture-artifact-root> --output-root <draft-package-root> --json`
- `recording suggest conditions checkout-demo --fixture checkout --json`
- `recording suggest waits checkout-demo --fixture checkout --json`
- `workflow draft from-recording checkout-demo --fixture checkout --out draft.json --json`
- All implemented fixture commands return `sparkle.cli.result.v1`, mark `fixtureMode: true`, warn that S1 fixture data is being used, and return only ids plus safe relative artifact refs, not image bytes or video bytes.
- Fixture `recording ocr search` and `recording suggest ...` now route through `SemanticRecordingQueryEngine`, so the same deterministic, no-Vision-in-tests behavior is available to CLI payloads and future shared services. Fixture OCR no longer depends on caller-supplied query results; stored-bundle OCR is explicitly marked `persistedBundle`; suggestion payloads include `query.allowedKinds`, `availability` and `unavailableReason` when synthesis is unavailable.
- Fixture `recording readiness` routes through the same `SemanticRecordingBundleReadiness` audit used by S2 debug-smoke, returns sidecar load diagnostics, status, issue counts, issue details, follow-ups, artifact availability and artifact file evidence when a persisted bundle directory is available, and supports `--require-ocr` / `--require-window-or-ax` for stricter evidence review.

Implemented stored-bundle read-only slice:

- `recording list --recordings-root <path> --json`
- `recording show <recording-uuid> --recordings-root <path> --json`
- `recording explain <recording-uuid> --recordings-root <path> --json`
- `recording readiness <recording-uuid> --recordings-root <path> --json`
- `recording macro-links --recordings-root <path> --json`
- `recording frames <recording-uuid> --recordings-root <path> --json`
- `recording frame show <recording-uuid> --frame <frame-uuid> --recordings-root <path> --json`
- `recording events-near <recording-uuid> --time <seconds> --window <seconds> --recordings-root <path> --json`
- `recording ocr search <recording-uuid> --text <text> --recordings-root <path> --json`
- `recording visual search <recording-uuid> --kind <kind> --label <label> --recordings-root <path> --json`
- `recording show|explain|frames|frame show|events-near|ocr search|visual search <recording-uuid> --bundle-path <bundle-dir> --json`
- Default-root read-only commands are also available without a source option:
  - `recording list --json`
  - `recording show <recording-uuid> --json`
  - `recording explain <recording-uuid> --json`
  - `recording readiness <recording-uuid> --json`
  - `recording frames <recording-uuid> --json`
  - `recording frame show <recording-uuid> --frame <frame-uuid> --json`
  - `recording events-near <recording-uuid> --time <seconds> --window <seconds> --json`
  - `recording ocr search <recording-uuid> --text <text> --json`
  - `recording visual search <recording-uuid> --kind <kind> --label <label> --json`
- Stored commands use `RecordingBundleStore.listBundleCatalog`, `loadBundle(recordingID:)` and `loadBundle(from:)`, keep `fixtureMode: false`, preserve explicit source options in `nextActions` when provided, and omit explicit root options for default-root product commands.
- Stored `recording readiness` uses tolerant loading instead of strict failure for optional sidecars, exposes sidecar diagnostics, readiness issues and artifact file evidence without reading image/video bytes, and preserves the same default-root/id policy as `show` / `explain`.
- Stored `recording macro-links` loads saved macro manifests from the default or explicit `--macros-dir`, reads `SavedMacro.semanticRecording`, audits linked bundles through the default or explicit `--recordings-root`, checks canonical relative path policy, and reports linked/unlinked/failed/not-ready plus artifact-file states without reading image/video bytes.
- Stored/fixture `recording explain` summarizes existing semantic events, visual observations, evidence notes and safe refs without reading image bytes, invoking Vision or synthesizing suggestions.
- Stored `recording ocr search` filters persisted `RecordingVisualObservation` OCR text from the loaded bundle without invoking Vision and reports `availability: persistedBundle`.
- Stored `recording visual search` filters persisted `RecordingVisualObservation` kind/label/text metadata from the loaded bundle without invoking Vision or reading image bytes.
- Stored `recording suggest` accepts stored sources and has a metadata-only deterministic first pass: persisted OCR text can propose reviewed OCR waits, persisted image/pattern observations can propose reviewed image conditions and locator replacement candidates, persisted region baseline/diff observations can propose region-change conditions, and persisted pixel samples can propose pixel conditions. This path returns `availability: persistedBundle`, cites frame/event/observation/artifact refs, can include `artifactFiles` present/missing/deleted/empty/directory/unsafe status when a bundle directory is available, does not read image/video bytes into the payload, does not invoke Vision and does not mutate workflows. It is still not product-ready live/cleanup synthesis.
- Fixture `recording suggest ... --json` summaries include S3 `reviewActions` (`review.acceptSuggestion`, `review.rejectSuggestion`, `review.clearDecision`) with mutation boundaries and evidence refs copied from the same `RecordingSuggestion` payload.
- Fixture `recording suggest ... --json` summaries also include S3 `reviewActionPresentations`, a row-level action/evidence model for CLI/AI display that mirrors Macro Review without implying direct workflow mutation.
- Explicit `recording asset extract` / `recording asset baseline` first pass reads a selected frame artifact from a stored bundle directory or explicit fixture `--source-root`, crops the caller-supplied region, writes a PNG under `--output-root/assets/images` or `--output-root/assets/baselines`, and returns `AutomationWorkflowDraftVisualAssets`-compatible refs plus SHA-256 and evidence refs. It does not choose a default output package, import a workflow, or perform image similarity search.
- Explicit asset extraction should reuse S3 `review.materializeAsset` semantics when exposed as user-facing action evidence: source artifact, package-local asset path, SHA-256 digest, frame/event refs, bounds and visual asset key are evidence alignment, while workflow mutation remains false until a reviewed draft patch/import exists.
- `workflow draft from-recording` first pass uses the same source options as recording CLI, reuses S3 Review suggestion-to-patch semantics, writes a `sparkle.workflow.draft.v1` document when `--out` is provided, and returns validation warnings plus review-only evidence/action refs. Fixture suggestion-driven generation is verified; product-ready stored/live draft synthesis remains open.
- Workflow runtime now has a first-pass `AutomationDependency.dynamicDelay` contract for OCR/visual condition evidence -> downstream delay. S4 may later suggest such links from recording evidence, but only as reviewable draft patches/imports; S4 does not parse live OCR into timers, schedule runs, or claim general variable/expression support.

## 3. User And AI Logic

The CLI should help AI collaborate in small, reviewable steps:

```text
AI asks what recordings exist
  -> CLI returns compact summaries and evidence availability
AI asks for frames near a click/wait
  -> CLI returns frame IDs, event IDs and safe refs
AI searches OCR or visual candidates
  -> CLI returns ranked local evidence, not full video
AI proposes waits/locators/conditions
  -> CLI returns suggestions with evidence refs, confidence, risk and fallback
User reviews inside App or draft preview
  -> only accepted suggestions become draft patches/imports
```

The CLI should not try to be a hidden remote control surface. It should make initialization faster and safer:

- initialize a workflow draft from one recording
- find fragile waits and clicks
- extract visual assets from selected frames
- explain why a condition or branch is suggested
- reuse existing macros only when evidence is sufficient

## 4. MVP Command Sequence

### S4-1: Fixture Recording Summary

```bash
SparkleRecorder recording show checkout-demo --fixture checkout --json
```

Acceptance:

- returns `schema: "sparkle.cli.result.v1"`
- includes recording id, app/surface summary, event count, frame count, video/keyframe availability, suppression summary and next actions
- uses S1 fixture only; no live capture required

### S4-2: Fixture Frames And Events

```bash
SparkleRecorder recording frames checkout-demo --fixture checkout --json
SparkleRecorder recording events-near checkout-demo --time 4.2 --window 1.0 --fixture checkout --json
```

Acceptance:

- returns frame IDs, related event IDs, recording time, video time, surface ID and safe artifact refs
- no image bytes by default
- warnings explain missing/unreadable refs instead of crashing

### S4-3: OCR Query

```bash
SparkleRecorder recording ocr search checkout-demo --text "Pay" --fixture checkout --json
```

Acceptance:

- searches `RecordingVisualObservation` values from fixture/service
- returns bounding boxes, confidence/score, frame IDs and source refs
- no Vision execution in CLI unit tests
- uses the pure `SemanticRecordingQueryEngine.ocrSearch` path, so fixture and explicit stored-bundle search are deterministic bundle reads
- payload reports `availability` as `deterministicFixture` for fixture reads and `persistedBundle` for explicit stored-bundle reads

### S4-4: Visual Query

```bash
SparkleRecorder recording visual search checkout-demo --kind imageTemplateCandidate --label button --fixture checkout --json
```

Acceptance:

- searches persisted `RecordingVisualObservation` metadata by kind, label and optional text
- returns observation ids, frame ids, bounds, confidence/score, labels and safe artifact refs
- does not read image bytes or run Vision/template matching inside CLI tests
- uses the pure `SemanticRecordingQueryEngine.visualSearch` path, so fixture and explicit stored-bundle search are deterministic bundle reads

### S4-5: Explicit Stored Bundle Queries

```bash
SparkleRecorder recording list --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording show <recording-uuid> --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording readiness <recording-uuid> --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording frames <recording-uuid> --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording ocr search <recording-uuid> --text "Ready" --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording visual search <recording-uuid> --kind imageTemplateCandidate --label button --recordings-root /path/to/SemanticRecordings --json
SparkleRecorder recording show <recording-uuid> --bundle-path /path/to/SemanticRecordings/<recording-uuid> --json
```

Acceptance:

- lists bundle ids from an explicit root without reading image/video bytes
- loads manifest plus sidecars via S2 `RecordingBundleStore`
- source options propagate into `nextActions`
- does not pick a default product root or imply live evidence is complete
- `recording readiness` uses tolerant sidecar loading and reports readiness status/issues/follow-ups plus artifact file evidence for fixture, explicit-root, bundle-path and default-root sources
- `recording ocr search` uses persisted OCR observations only
- `recording visual search` uses persisted visual observation metadata only

### S4-5A: Readiness Audit

```bash
SparkleRecorder recording readiness checkout-demo --fixture checkout --require-ocr --require-window-or-ax --json
SparkleRecorder recording readiness <recording-uuid> --json
SparkleRecorder recording macro-links --require-ocr --require-window-or-ax --json
```

Acceptance:

- returns `SemanticRecordingBundleReadiness` status, blocking/degraded issue counts, issue details and follow-up actions
- includes tolerant sidecar diagnostics so corrupt optional sidecars can be distinguished from missing required live evidence
- supports default-root/id lookup without temporary source options, while preserving explicit `--recordings-root` / `--bundle-path` in next actions when provided
- does not read image or video bytes; it audits manifest/sidecar structure, safe artifact refs and file status only
- `recording macro-links` is the saved-macro bridge audit: it proves whether `workflow macros --json` references can load and pass readiness/artifact-file checks from the selected recording root
- product-ready live readiness remains blocked until accepted S2 bundles exist under the default root with installed-app saved macro links

### S4-6: Suggestion Query

```bash
SparkleRecorder recording suggest waits checkout-demo --fixture checkout --json
SparkleRecorder recording suggest locators checkout-demo --fixture checkout --json
SparkleRecorder recording suggest conditions checkout-demo --fixture checkout --json
```

Acceptance:

- returns non-destructive `RecordingSuggestion` payloads
- each suggestion cites evidence refs and includes confidence, risk and fallback
- no macro/workflow mutation
- fixture suggestions are category-filtered by `SemanticRecordingQueryEngine.deterministicSuggestions`
- payload reports `query.allowedKinds`, `availability` and `unavailableReason` when synthesis is unavailable, so AI callers know whether the suggestions came from deterministic fixture evidence, persisted stored-bundle metadata, or an unavailable live/product path
- stored-bundle suggestions are deterministic and evidence-only; artifact file status can be surfaced for persisted bundle refs, including `deleted` when `.userDeleted` suppression evidence records retention/user cleanup, while live/default-root product suggestions and cleanup suggestions remain unavailable until live bundle evidence, installed-app saved macro links and Review/Draft Preview acceptance semantics stabilize

### S4-7: Asset Extraction

```bash
SparkleRecorder recording asset extract checkout-demo \
  --frame frame-00042 \
  --region 100,120,80,40 \
  --kind imageTemplate \
  --name submit-button \
  --output-root /path/to/draft-package \
  --json
```

Acceptance:

- writes only through an accepted app-edge store/copy service
- returns refs compatible with `AutomationWorkflowDraftVisualAssets`
- refuses unsafe output paths and missing source frames
- first pass is explicit-source only: stored bundles use their bundle directory; fixture extraction requires `--source-root`; output requires `--output-root`

### S4-8: Draft From Recording

```bash
SparkleRecorder workflow draft from-recording checkout-demo --out draft.json --json
```

Acceptance:

- outputs `sparkle.workflow.draft.v1`
- includes evidence refs in draft metadata/suggestions
- does not import or run automatically
- generated draft passes existing validate/simulate/dry-run path before import
- first pass is fixture/review-only: deterministic fixture suggestions become draft condition tasks, output can be validated/simulated, and workflow mutation still requires Draft Preview/import

## 5. JSON Envelope Rules

Every command should use the same envelope family:

```json
{
  "schema": "sparkle.cli.result.v1",
  "ok": true,
  "command": "recording.show",
  "recordingID": "recording-checkout-demo",
  "results": [],
  "warnings": [],
  "nextActions": []
}
```

Rules:

- Include stable ids and safe relative artifact refs.
- Do not include image bytes or full video by default.
- Include `warnings` for missing assets, suppressed content, unsupported schema and degraded evidence.
- Include `nextActions` that point users toward Review, asset extraction, draft validation or permission fixes.
- Keep fixture mode explicit in output so product docs do not confuse fixture proof with live capability.

## 6. Interface Requests

### To S1

Current S1 contract is enough for fixture MVP:

- `SemanticRecordingBundle`
- `RecordingQueryResult`
- `RecordingSuggestion`
- `RecordingEvidenceReference`
- `RecordingArtifactRef`
- `RecordingFrameReference`
- `RecordingVisualObservation`
- `RecordingPreviewComparison`

Future request may be needed for:

- user-edited suggestion review state
- app knowledge summary identity
- stable recording catalog IDs beyond fixture/local path

### To S2

S2 now has a first-pass sidecar-aware bundle loader/catalog entry point:

- `RecordingBundleStore.listBundleCatalog`
- `RecordingBundleStore.loadBundle(recordingID:)`
- `RecordingBundleStore.loadBundle(from:)`
- `SemanticRecordingBundleDirectoryIdentity`
- `SemanticRecordingReviewPresenter` consumes the full loader instead of manifest-only snapshots

S4 now consumes those APIs in explicit and default-root read-only stored-bundle commands. S2 rejects UUID bundle directories whose manifest id does not match the directory id, so stored catalog ids now have a first-pass consistency rule. S4 still needs before product-ready live commands:

- authorized live bundle evidence proving real `.mov`, keyframes and sidecars exist
- installed-app evidence that ordinary saved macros link to those default-root recording ids
- live suppressed/missing/empty artifact status surfaced through CLI payloads, building on the stored present/missing/deleted first pass
- expose preview-safe refs without CLI constructing raw Application Support paths

### To S3

S4 suggestions must match S3 Review UI affordances:

- same evidence refs
- same action names
- same accept/reject semantics
- same row-level action presentation when CLI/AI needs to explain the action to a user
- no hidden mutation outside user-reviewed draft patch
- current fixture suggestion JSON exposes this as `reviewActions` and `reviewActionPresentations`; stored/live suggestion synthesis must keep both fields before it is called product-ready
- asset extraction payloads should use S3 `review.materializeAsset` / `packageAssetOnly` for materialized package refs instead of treating copied PNGs as imported workflow changes

### To S0

S4 docs and fixture transcripts should not count as S0 live product evidence. If CLI output is used in product evidence, sidecars must label fixture/live source clearly.

## 7. App Knowledge Later

App Knowledge should wait until semantic bundles and CLI queries exist. First useful layer:

- app bundle id
- window/surface family
- macro group
- visual anchor group
- known waits
- known failures and successful fixes

Do not start:

- large graph database
- cross-app autonomous planner
- natural-language agent that bypasses draft validation
- MCP server with separate logic

## 8. Acceptance Gates

S4 first slice is complete when:

- fixture `recording show` and `recording frames` commands exist
- commands return `sparkle.cli.result.v1`
- outputs cite S1 evidence refs and safe artifact refs
- unit tests use fixtures and do not touch ScreenCaptureKit, Vision, AX, mouse or keyboard
- docs include a transcript showing AI can inspect evidence without full video

Status: complete for fixture `list`, `show`, `explain`, `readiness`, `frames`, `frame show`, `events-near`, `ocr search`, `visual search`, explicit `asset extract` / `asset baseline`, deterministic `suggest conditions` / `suggest waits`, and fixture/review-only `workflow draft from-recording`; complete for explicit and default-root read-only stored-bundle `list`, `show`, `explain`, `readiness`, `macro-links`, `frames`, `frame show`, `events-near`, `ocr search`, metadata-only `visual search`, metadata-only `suggest waits` / `suggest locators` / `suggest conditions`, suggestion `artifactFiles` present/missing/deleted status for persisted bundle refs, and explicit frame-region asset extraction over S2 loader/catalog/readiness APIs. The latest S4 slices harden fixture OCR/suggestion query availability, cap suggestions without evidence refs at low confidence, add explicit-source asset materialization, generate a validated/simulatable/import-dry-run draft from fixture suggestions, synthesize persisted stored-bundle suggestions from OCR/image/pattern/region/pixel observation metadata, expose read-only semantic-event explain output, expose saved macro semantic recording references through `workflow macros`, expose S3 `reviewActionPresentations` alongside `reviewActions`, audit visual observation and retention-pruned deleted artifacts, and add default-root read-only listing/loading/readiness/macro-link/artifact audit without claiming live product readiness. `docs/workflow-page-productization/product-evidence/semantic-recording-cli-low-token-transcript.md` records the low-token explain/OCR/visual/suggest/draft/validate/simulate/import dry-run flow without image/video bytes. Product-ready CLI still requires authorized live bundle evidence, installed-app saved macro links, cleanup suggestions, Review alignment with S3 and live artifact status. Image-byte visual similarity search, product-ready stored/live draft-from-recording and MCP remain deferred until these gates are green.

## 9. Fixture Transcript Evidence

Smoke commands run on 2026-07-06:

```bash
swift run --scratch-path .build-test SparkleRecorder recording list --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording show checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording explain checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording readiness checkout-demo --fixture checkout --require-ocr --require-window-or-ax --json
swift run --scratch-path .build-test SparkleRecorder recording macro-links --json
swift run --scratch-path .build-test SparkleRecorder recording frames checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording frame show checkout-demo --frame 74000000-0000-0000-0000-000000000004 --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording events-near checkout-demo --time 2.4 --window 0.25 --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording ocr search checkout-demo --text "Order" --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording visual search checkout-demo --kind imageTemplateCandidate --label button --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder recording suggest conditions checkout-demo --fixture checkout --json
swift run --scratch-path .build-test SparkleRecorder workflow draft from-recording checkout-demo --fixture checkout --out /tmp/s4-from-recording-draft.json --json
swift run --scratch-path .build-test SparkleRecorder recording list --recordings-root .build-test/s4-empty-recordings --json
```

Representative output excerpt:

```json
{
  "schema": "sparkle.cli.result.v1",
  "ok": true,
  "command": "recording.show",
  "data": {
    "requestedRecordingID": "checkout-demo",
    "recordingID": "74000000-0000-0000-0000-000000000001",
    "fixtureMode": true,
    "fixture": "checkout",
    "videoAvailable": true,
    "keyframesAvailable": true,
    "frameCount": 3,
    "timelineEventCount": 3,
    "aiSafeEventCount": 3,
    "artifactAvailability": {
      "videoRefs": ["video/recording.mov"],
      "frameRefs": [
        "frames/000001-start.png",
        "frames/000014-before-click.png",
        "frames/000016-after-click.png"
      ]
    }
  },
  "warnings": [
    {
      "code": "fixtureMode",
      "message": "This result uses the S1 'checkout' fixture, not a live semantic recording bundle."
    }
  ]
}
```

OCR query excerpt:

```json
{
  "command": "recording.ocr.search",
  "data": {
    "query": { "text": "Order", "matchMode": "contains" },
    "count": 1,
    "results": [
      {
        "observationID": "74000000-0000-0000-0000-00000000000C",
        "queryResultIDs": ["74000000-0000-0000-0000-000000000013"],
        "frameID": "74000000-0000-0000-0000-000000000005",
        "text": "Order confirmed",
        "confidence": 0.97,
        "artifactRef": "visual-index/ocr/confirmation-region.png"
      }
    ]
  }
}
```

Suggestion excerpt:

```json
{
  "command": "recording.suggest.conditions",
  "data": {
    "category": "conditions",
    "count": 1,
    "suggestions": [
      {
        "kind": "conditionCandidate",
        "title": "Replace fixed wait with OCR confirmation",
        "confidence": 0.86,
        "fallback": "Keep the original playable macro wait until the user accepts a reviewed condition.",
        "mutationPolicy": "Review required; no workflow or macro mutation until accepted.",
        "reviewActions": [
          {
            "actionName": "review.acceptSuggestion",
            "mutationBoundary": "draftPreviewRequired",
            "createsDraftPatch": true,
            "mutatesWorkflow": false
          },
          {
            "actionName": "review.rejectSuggestion",
            "mutationBoundary": "reviewLocal",
            "createsDraftPatch": false,
            "mutatesWorkflow": false
          }
        ],
        "reviewActionPresentations": [
          {
            "actionName": "review.acceptSuggestion",
            "summary": "review.acceptSuggestion · source visual-index/ocr/confirmation-region.png · Draft Preview required",
            "rows": [
              { "kind": "mutationBoundary", "label": "Mutation boundary", "value": "Draft Preview required" },
              { "kind": "mutationEffect", "label": "Effect", "value": "Creates reviewed draft patch" },
              { "kind": "artifact", "label": "Source artifact", "value": "visual-index/ocr/confirmation-region.png" }
            ]
          }
        ]
      }
    ]
  }
}
```

Frame query excerpt:

```json
{
  "command": "recording.eventsNear",
  "data": {
    "query": { "time": 2.4, "window": 0.25 },
    "events": [
      {
        "id": "74000000-0000-0000-0000-000000000007",
        "kind": "recordedEvent",
        "summary": "Clicked the checkout button",
        "relatedFrameIDs": [
          "74000000-0000-0000-0000-000000000004",
          "74000000-0000-0000-0000-000000000005"
        ]
      }
    ],
    "frames": [
      {
        "id": "74000000-0000-0000-0000-000000000004",
        "imageRef": "frames/000014-before-click.png",
        "relatedEventIDs": ["74000000-0000-0000-0000-000000000007"]
      },
      {
        "id": "74000000-0000-0000-0000-000000000005",
        "imageRef": "frames/000016-after-click.png",
        "observationIDs": ["74000000-0000-0000-0000-00000000000C"]
      }
    ]
  }
}
```

## 10. Implementation Log

- 2026-07-06: Created S4 workstream. At creation time no user-facing recording CLI was claimed complete. This file freezes the CLI-first, MCP-deferred boundary and defines the fixture-first MVP sequence.
- 2026-07-06: Implemented fixture-first `recording show`, `recording frames`, `recording frame show` and `recording events-near` over `SemanticRecordingFixture.checkoutBundle()`. Added `SemanticRecordingCLITests` for envelope schema, fixture mode, safe artifact refs and frame/event ids. Later entries add OCR/visual search, suggestion commands, asset extraction and fixture draft-from-recording; live catalog and App Knowledge stay future work.
- 2026-07-06: Implemented fixture-first `recording ocr search` and deterministic `recording suggest conditions` / `recording suggest waits` envelope support over `SemanticRecordingFixture.checkoutQueryResults()` and `checkoutSuggestions()`. Tests prove OCR observation ids, bounds, confidence, query result ids, safe refs, suggestion confidence/risk/fallback and review-only mutation policy. Later entries add explicit/default-root stored-bundle OCR/metadata visual search, metadata-only stored-bundle suggestions, asset extraction and fixture draft-from-recording; product-ready live catalog, cleanup suggestions and App Knowledge remain open.
- 2026-07-06: Implemented explicit read-only stored-bundle source support for `recording list`, `show`, `frames`, `frame show`, `events-near` and `ocr search` using S2 `RecordingBundleStore` catalog/load APIs. Commands accept `--recordings-root <path>` and loaded-bundle commands also accept `--bundle-path <dir>`; stored payloads keep `fixtureMode: false` and preserve source options in next actions. Later entries add stored metadata-only visual search, metadata-only stored suggestions, explicit-source asset extraction and fixture draft-from-recording; product-ready default root, live evidence, image-byte visual similarity and App Knowledge remain open.
- 2026-07-06: Implemented metadata-only `recording visual search` over persisted `RecordingVisualObservation` values. The pure `SemanticRecordingQueryEngine.visualSearch` path supports kind, label and optional text filters; CLI envelopes return observation ids, frame ids, bounds, labels, confidence/score and safe artifact refs for fixture and explicit stored-bundle sources. Image-byte visual similarity search remains open; fixture draft-from-recording lands in a later entry.
- 2026-07-06: Implemented explicit-source `recording asset extract` and `recording asset baseline`. Commands require a frame id, region, name and `--output-root`; stored bundle sources read artifacts from the bundle directory, while fixture extraction requires `--source-root`. The CLI crops the selected frame region, writes PNG assets under `assets/images` or `assets/baselines`, returns SHA-256 plus `AutomationWorkflowDraftVisualAssets`-compatible refs, and keeps workflow mutation behind Draft Preview/import.
- 2026-07-06: Implemented fixture/review-only `workflow draft from-recording`. `SemanticRecordingWorkflowDraftBuilder` reuses S3 Review suggestion-to-patch semantics to turn deterministic fixture suggestions into a `sparkle.workflow.draft.v1` condition task with recording evidence/action refs; the CLI supports `--fixture` / explicit stored source options, optional `--out`, `--name`, `--max-tasks` and `--suggestions-only`, returns validation warnings, and verified the written draft through `workflow draft validate` and `workflow draft simulate`. Product-ready stored/live draft synthesis remains open.
- 2026-07-06: Hardened the fixture OCR/suggestion query boundary after S4 first-slice review. `SemanticRecordingQueryEngine.deterministicOCRSearch` now returns availability, query echo, matches and unavailable reason, fixture CLI OCR owns checkout query evidence lookup, and deterministic suggestion results carry the original query plus unavailable reason. This keeps fixture OCR search and deterministic suggestions usable as a shared service while live catalog/search/suggestion synthesis stays deferred until S2 live evidence and Review alignment stabilize.
- 2026-07-06: S2 added first-pass stored bundle root/id consistency through `SemanticRecordingBundleDirectoryIdentity`; UUID bundle directories now have to match the manifest recording id when loaded through `RecordingBundleStore`, and catalog entries skip mismatched manifests. This removes the root/id policy blocker for explicit stored-bundle identity, but S4 product-ready live catalog remains deferred until authorized live evidence, cleanup/missing-artifact policy and Review alignment are ready.
- 2026-07-07: Added default-root/id read-only CLI first pass. `RecordingBundleStore.defaultRootDirectory` exposes `/Users/<user>/Library/Application Support/SparkleRecorder/SemanticRecordings`, `recording list --json` lists that root without requiring `--recordings-root`, loaded recording commands fall back to that root by UUID when no explicit source is provided, and default-root next actions omit temporary source options. Product-ready live catalog/search/suggestion still requires accepted live bundles and installed-app saved macro links.
- 2026-07-06: Aligned S4 suggestion JSON with S3 Review action semantics. Fixture `recording suggest ... --json` summaries now include Codable `reviewActions` for accept/reject/clear, preserving the same suggestion/frame/event/observation/artifact refs and mutation boundaries that Macro Review uses.
- 2026-07-06: Added S3 Review action presentations to S4 suggestion JSON. Fixture suggestions now expose `reviewActionPresentations` next to `reviewActions`, giving CLI/AI consumers the same row-level boundary/evidence display used by Macro Review while keeping mutation behind Draft Preview/import.
- 2026-07-06: Implemented fixture and explicit stored-bundle `recording explain`. The command returns read-only semantic-event key points, visual evidence summaries, evidence notes, safe artifact refs, source-option-preserving next actions and a mutation policy that keeps edits behind Review/Draft Preview; default/live product root selection and suggestion synthesis remain open.
- 2026-07-07: Added S4 maintenance safety and product evidence alignment. `SemanticRecordingCLISuggestionSummary` now caps suggestions without evidence refs at `0.49` confidence and appends a missing-evidence risk, covered by `SemanticRecordingCLITests.recordingSuggestionWithoutEvidenceStaysLowConfidence`; `semantic-recording-cli-low-token-transcript.md` records the fixture explain/OCR/visual/suggest/draft/validate/simulate/import dry-run chain returning compact ids and safe refs without image/video bytes.
- 2026-07-07: Added read-only readiness and saved-macro link audit commands. `recording readiness` exposes tolerant sidecar diagnostics plus `SemanticRecordingBundleReadiness` status/issues/follow-ups and artifact file evidence for fixture, explicit-root, bundle-path and default-root sources. `workflow macros --json` now carries `SavedMacro.semanticRecording`, and `recording macro-links --json` audits saved macro references against the selected/default recording root, returning linked/unlinked/failed/not-ready states, canonical path issues and artifact file status without image/video bytes. Product-ready live catalog still requires accepted live bundles and installed-app saved macro links.
- 2026-07-07: Recorded Workflow dynamic-delay boundary. `AutomationDependency.dynamicDelay` belongs to Workflow core/reducer/UI and can schedule downstream tasks from OCR/visual condition evidence; S4 can only consume/suggest that contract behind Review/Draft Preview boundaries and must not claim product-ready timer orchestration from recording queries alone.
- 2026-07-07: Added persisted stored-bundle deterministic suggestion synthesis. `SemanticRecordingQueryEngine.persistedSuggestions` turns persisted OCR/image/pattern/region/pixel observations into Review-only waits, locator candidates and conditions with deterministic ids, evidence refs and `availability: persistedBundle`, without reading image/video bytes or invoking Vision. `SemanticRecordingQueryTests.deterministicSuggestionsIncludePersistedBundleEvidenceProposals` and `SemanticRecordingCLITests.recordingSuggestionEnvelopeExposesPersistedStoredQueryContract` cover the core and CLI envelope paths. Product-ready live/default-root suggestions, cleanup suggestions and stored/live draft-from-recording remain open.
- 2026-07-08: Added suggestion artifact-file/deleted status first pass. `SemanticRecordingArtifactFileAuditor.summary` now includes `visualObservation` artifact refs and maps missing refs with `.userDeleted` suppression evidence to `deleted`; `RecordingBundleStore.applyRetentionPlan` appends `.userDeleted` suppression sidecars when confirmed pruning removes artifacts; `recording suggest` attaches `artifactFiles` when a persisted bundle directory is available; degraded suggestion envelopes emit `recordingArtifactsDegraded`; and `SemanticRecordingArtifactFileAuditTests`, `RecordingBundleStoreTests.prunedArtifactsReloadAsUserDeletedArtifactEvidence` plus `SemanticRecordingCLITests.recordingSuggestionEnvelopeSurfacesArtifactFileStatus` prove present/missing/deleted/empty status without exporting image/video bytes.

# S0 To S4 Final Gap Alignment And UI Focus

更新时间：2026-07-07
状态：S3 first-pass work paused; next stage focuses on S2 live evidence and UI/UX product polish
Owner：Recording / Workflow Evidence / Review handoff coordination / UI experience

本文用于回答两个具体问题：

1. S3 的 Review / Draft Preview first pass 告一段落之后，S0-S4 最终还差什么，哪些可以验收，哪些只能算 first pass 或 fixture/stored proof。
2. 后续 UI owner 应该如何接住后端逻辑，把 evidence、runtime、capture、draft 和 Review 体验打磨成用户能理解、能信任、能修正的产品流程。

结论先写清楚：S0 strict Workflow evidence gate 已关闭，S1 semantic recording bundle 合同 first pass 已完成，S3 fixture/stored Review UX first pass 已经足够支撑下一轮验证，S4 fixture/explicit stored-bundle low-token CLI first pass 已完成。现在缺的不是继续扩 S3 UI 或直接做 App Knowledge，而是 S2 生产一个可审阅的真实 semantic recording bundle，并用 live product evidence 证明普通录制能稳定写出 `.mov`、event-aligned keyframes、sidecars、OCR/window/AX observations、suppression/redaction evidence 和 saved macro link。S3/S4 的 product-ready live work 都要等这个证据。

我的后续职责收敛为 UI/UX owner：不在 SwiftUI 里重写后端语义，不直接做 capture/CLI/schema；重点是把后端已经形成的证据链翻译成清晰工作流，让用户知道系统看到了什么、为什么这样判断、哪些动作只是本地 review、哪些会进入 Draft Preview、哪些才是真正 import。

## 1. Current State

| Layer | Current State | What It Proves | What It Does Not Prove |
| --- | --- | --- | --- |
| S0 Workflow Evidence | Strict live audit closed at 13/13. Visual diagnostics, macro evidence, branch consistency and task reorder have live clips and sidecars. | Existing Workflow evidence affordances, Open/Reveal paths and capture-note discipline are trustworthy enough for semantic recording to reuse. | It does not prove semantic recording capture, live `.mov`, keyframes, Review from a live bundle, or App Knowledge. |
| S1 Contract/Core | `SemanticRecordingBundle` v0, safe refs, video/frame/timeline/events/suppression/source-runtime-comparison/query/suggestion value types and checkout fixture are done. | S2/S3/S4 can share the same evidence ids and refs without inventing parallel schemas. | It does not produce live files, run Vision/AX, write bundle sidecars, or choose product retention/default-root policy. |
| S2 App Capture | Core capture session, app-edge skeletons, experimental Recorder bridge, preflight, suppression/redaction, retention, sidecar loader/catalog, debug-smoke evidence and readiness audit have first passes. | The architecture can assemble, persist, reload and audit semantic recording bundles with fake or debug evidence. | Product-ready live capture is still unproven: ordinary recording has not produced accepted live `.mov` / keyframe / OCR/window/AX / redaction / cleanup evidence. |
| S3 Review UX | Macro Review projection, presenter, Run Detail opener, artifact status, frame region selection, frame-to-condition patches, Draft Preview handoff, pixel picking and action semantics first passes are done. | A bundle shaped like S1/S2 output can be reviewed, patched and handed to Draft Preview without direct workflow mutation. | Installed-app live Review evidence is still gated by S2 live bundles and stronger run/session association. |
| S4 CLI/AI | Fixture OCR/visual/search/suggestion, explicit stored-bundle read-only CLI, explicit-source asset extraction, review-only draft-from-recording and low-token transcript first passes are done. | AI/CLI can query local evidence ids, extract selected frame assets and generate review-only drafts without sending video/image bytes or mutating workflows directly. | Product-ready default/live catalog, stored/live suggestion synthesis, image-byte visual similarity, stored/live draft-from-recording and App Knowledge remain blocked on S2 live evidence, default root policy and Review acceptance semantics. |

## 1.1 Final S0-S4 Acceptance Posture

| Owner | Acceptance Posture |
| --- | --- |
| S0 | Closed for strict Workflow evidence. Keep monitoring only if Workflow evidence UI or product-evidence files change. Future Cookie Run bound-window acceptance is a separate product item, not a semantic recording blocker. |
| S1 | Contract first pass closed. Reopen only for explicit new fields required by S2 live producers, S3 Review, or S4 CLI after a written interface request. |
| S2 | Active blocker. Needs authorized live bundle/product evidence before semantic recording can be called product-ready or before S3/S4 live claims resume. |
| S3 | First pass paused. Maintain snapshots/action semantics; resume installed-app evidence only after S2 provides live bundle + `SavedMacro.semanticRecording` inputs. |
| S4 | First pass paused for product-ready live work. Maintain fixture/explicit stored-bundle CLI; resume default/live catalog/search/suggestion only after S2 live bundle/root policy and S3 Review boundaries stabilize. |

## 2. What S3 Being Paused Means

S3 should now be treated as a stable first-pass consumer, not the active producer of the next proof.

S3 should keep only maintenance work open:

- keep fixture snapshots current if S1/S2 bundle fields change
- preserve presenter-only file access and no raw SwiftUI path construction
- keep Review action semantics aligned with S4 payloads
- wait for S2 live bundle evidence before claiming installed-app product evidence

S3 should not keep expanding into broad UI/product scope until S2 provides live recording inputs:

- no new App Knowledge UI
- no direct live capture workaround inside SwiftUI
- no CLI-specific evidence identifiers
- no direct workflow mutation outside Draft Preview/import

## 2.1 S0-S3 UI Gap Map

| Stage | Backend / Evidence State | UI Gap | UI Owner Response |
| --- | --- | --- | --- |
| S0 | Workflow evidence strict gate is closed with live clips and sidecars. | Future UI changes can regress evidence trust if Open/Reveal, inline feedback or branch/diagnostic copy drifts. | Keep S0 as product-evidence discipline: every evidence surface needs visible status, nearby action feedback, fixture/live labeling and refreshed screenshots or clips when behavior changes. |
| S1 | Bundle ids, safe refs, source/runtime comparison, query/suggestion value types exist. | Raw ids/refs are too technical for users; showing them alone does not explain intent. | Render ids as traceable secondary evidence, but lead with user questions: "which recording?", "which frame?", "which region?", "why selected?", "what can I safely change?". |
| S2 | Capture, preflight, suppression, redaction, retention and loader/catalog have first passes. | Settings/preflight/retention screens risk feeling like debug panels rather than a product flow. | Polish ready/blocked/degraded/suppressed/redacted/cleanup-affected states into plain user decisions with exact next actions and no hidden file-system assumptions. |
| S3 | Review projection, Run Detail opener, region selection, Draft Preview handoff, Run Target provenance and action semantics exist. | Fixture/stored proof is not the same as installed-app confidence; Review can still feel dense and technical. | Keep Review evidence-first: Bundle Health, Run Target, frame timeline, evidence tiles, Teach actions and Draft actions should form one readable story before live evidence is claimed. |

用户逻辑要保持固定：先录制，再回看，再教学，再生成 draft，再预览/导入，再用运行证据诊断。UI 的工作不是把后端模型暴露给用户，而是把这个路径变短、变清楚、变不吓人。

## 3. Remaining Gaps From S0/S1 To S2

### Gap A: S0 Evidence Discipline -> S2 Product Evidence

S0 gave us the discipline: live clips, sidecars, fixture-vs-live labels, strict audit thinking. S2 still needs the equivalent live evidence set for semantic recording.

Needed S2 evidence:

- authorized `semantic-recording debug-smoke --json --require-ocr --require-window-or-ax --evidence-sidecar <sidecar.md>` run on macOS 15+
- resulting bundle directory preserved with `.mov`, keyframe PNGs, manifest and sidecars
- sidecar showing command plan, preflight state, persisted reload counts, sidecar diagnostics and readiness status
- recording-start blocked/degraded guidance evidence from the actual app shell
- redacted frame/video consumption evidence from safe synthetic rehearsal and later real sensitive/excluded scenarios
- live cleanup review/confirmation evidence before broad rollout

The current debug-smoke sidecar is a capture helper. It is not the S2 strict product gate by itself.

### Gap B: S1 Contract -> S2 Live Producer Completeness

S1 defines the fields. S2 must prove live producers fill them correctly.

Needed producer proof:

- `RecordingVideoSegment` from `SCRecordingOutput` with real file ref, start/end time, target and codec/container metadata
- `RecordingFrameReference` keyframes aligned to start/click/text/wait/stop events
- `RecordingTimelineEvent` and AI-safe `RecordingSemanticEvent` sidecars round-tripping through `RecordingBundleStore.loadBundle`
- persisted OCR observations from Vision on selected/event frames
- persisted window/AX observations for target-window captures when Accessibility is available
- persisted suppression records for sensitive/excluded/oversized contexts
- rendered redacted frame/video indexes when a redacting suppression exists
- `SemanticRecordingBundleReadiness` passing against the reloaded persisted bundle, not only the in-memory finish result

### Gap C: Experimental Recorder Bridge -> User-Visible Recording Path

The ordinary Recorder bridge exists behind a non-default `semanticRecordingEnabled` flag. Product-ready S2 still needs to prove the whole user path.

Needed app-flow proof:

- start recording with semantic visual evidence enabled from the app UI
- preflight blocks before countdown when required permissions are missing
- degraded mode continues with clear status when Accessibility is missing
- normal stop saves the playable macro and attaches `SavedMacro.semanticRecording`
- discard/cancel/failure removes temporary semantic bundle directories
- the saved macro can later open linked Macro Review through S3 presenter

Do not turn this on by default until the live evidence above is present and reviewed.

### Gap D: S2 Bundle Identity -> S3 And S4 Product Inputs

S2 has stable UUID directory identity and sidecar-aware loading. S3 and S4 can consume explicit paths today, but product discovery remains unfinished.

Needed handoff proof:

- default product root decision for semantic recordings
- visible or documented recording id policy for saved macros and later workflow runs
- installed-app Run Detail -> linked Macro Review evidence from a saved macro with semantic bundle metadata
- future per-run/session semantic recording id, not only saved macro-level metadata
- live catalog/search allowed only after root policy and live bundle readiness are stable

Until then, S3/S4 should keep using explicit bundle paths or fixtures for tests.

### Gap E: Privacy/Safety -> Product Trust

The pure suppression, playable sanitization and redaction layers exist. They still need live proof and one reviewed mutation decision.

Needed safety proof:

- Secure Input / focused password field suppresses semantic visual capture while ordinary macro recording continues
- excluded app/window/domain rules suppress semantic visual capture before attaching a bundle
- redacted frames and redacted `.mov` sidecars are preferred by Review/CLI while source refs remain traceable
- playback-preserving readable metadata withholding is visible in save/export/status behavior
- reviewed `textAnchor.text` mutation path is decided in S3 before automatic mutation is allowed

### Gap F: S4 Fixture/Stored CLI -> Product-Ready Live AI Collaboration

S4 already proves the low-token pattern: ids, safe refs, deterministic fixture queries, explicit stored-bundle reads and review-only draft output. The remaining gap is product scope, not command syntax.

Needed S4 proof:

- default live recording root and recording id policy
- live `recording list/show/explain/frames/frame show/events-near/ocr search/visual search` over accepted S2 bundles
- stored/live suggestion synthesis with clear `availability`, evidence refs and missing-artifact status
- image-byte visual similarity only after deterministic metadata search and asset extraction remain stable
- product-ready stored/live `workflow draft from-recording` that preserves Review/Draft Preview mutation boundaries
- App Knowledge only after there are enough accepted live bundles to group by app/surface/macro/anchor

S4 must not mark product-ready commands complete from fixture mode, explicit temporary roots or sidecar-only smoke evidence.

## 4. Next Practical Sequence

1. S2 preflight/evidence rehearsal: run preflight-only debug-smoke with sidecar locally and keep the blocked/degraded evidence if permissions are missing.
2. S2 authorized live bundle: run live debug-smoke on macOS 15+ with `--require-ocr --require-window-or-ax`, preserve the bundle and sidecar, and inspect readiness diagnostics.
3. S2 ordinary Recorder bridge proof: record from the app with `semanticRecordingEnabled`, stop normally, verify `SavedMacro.semanticRecording`, then open linked Macro Review.
4. S2 safety proof: rehearse synthetic redaction on safe content, then separately capture real sensitive/excluded-context suppression evidence.
5. S3 resume only after step 3: capture installed-app Review -> Draft Preview -> confirm import from a live bundle.
6. S4 resume product-ready live catalog/search/suggestion only after S2 default root/id policy and live bundle readiness are accepted.
7. Update `acceptance-checklist.md` after each proof; do not check live-product boxes from fixture, stored fixture, explicit debug-root or blocked preflight evidence.

## 5. Current Do / Do Not

Do now:

- stabilize S2 live evidence capture and readiness diagnostics
- keep S3 snapshots and action semantics aligned with existing S1/S2 fields
- keep S4 fixture/explicit stored-bundle CLI as the low-token query path
- update docs whenever a fixture proof becomes live product evidence
- keep `acceptance-checklist.md` as the final source for checkboxes; workstream docs can explain nuance but cannot silently imply a checkbox is done

Do not do yet:

- do not mark S2 product-ready from fake-client tests, fixture snapshots or blocked preflight sidecars
- do not make semantic recording default-on
- do not build product-ready live catalog/search before default root and live evidence exist
- do not start broad App Knowledge or MCP work before live bundles and Review acceptance stabilize
- do not let S3 SwiftUI construct raw paths or run Vision/ScreenCaptureKit directly
- do not check an acceptance item unless the cited evidence would survive a fresh audit from the current worktree

## 6. UI/UX Owner Focus Going Forward

后续 UI 工作的中心不是继续堆面板，而是把后端逻辑产品化：

- Evidence first: 每个建议、失败、等待、分支和 visual condition 都先显示证据，再显示可执行动作。
- Mutation boundary visible: `reviewLocal`、`packageAssetOnly`、`draftPreviewRequired`、`confirmedImport` 必须是用户能看懂的状态，不是只存在 JSON 里。
- Degraded is a state: missing artifact、suppressed evidence、redacted frame、cleanup affected、permission blocked 都要可见、可解释、可恢复。
- Projection only: SwiftUI 渲染 projection / presenter result，不拼 raw path，不跑 Vision，不调用 ScreenCaptureKit，不重新推导 reducer/runtime 语义。
- Teach, not configure: Review 和 Workflow authoring 应该像“教系统识别这个状态”，而不是像填写内部 schema。
- Dense but calm: Workflow / Review 是生产力界面，应该紧凑、可扫描、可重复操作，不做营销式 hero 或装饰性复杂布局。

近期 UI 打磨顺序：

1. Workflow page: wait/verify 显示 region box 和 condition 状态；click 才显示 click circle/pulse，避免用户把验证动作误解成点击。
2. Run Detail: branch evidence、macro evidence、visual diagnostics、semantic recording link 使用一致的 status / preview / Open / Reveal / missing pattern。
3. Macro Review: Run Target、Bundle Health、Evidence tiles、Teach System、Draft Actions 调整视觉层级，让用户第一眼知道当前录制、当前 frame、当前可安全动作。
4. Frame region picker: selection handles、bounds readout、candidate kind、clear/draft affordance 不遮挡画面；框选后的 draft action 要显示 mutation boundary。
5. Draft Preview handoff: package-local asset provenance、source frame/crop/digest 更容易读懂，避免用户以为 semantic bundle 内部文件就是长期 workflow 依赖。
6. Settings/preflight: ready/blocked/degraded、privacy exclusions、retention cleanup 变成面向用户的决策流，而不是工程状态列表。

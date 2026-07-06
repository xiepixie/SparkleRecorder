# S2 Live Evidence Playbook

更新时间：2026-07-07
状态：S2 live gate capture playbook; no live gate is closed by this document
Owner：S2 App Capture / Visual Index, with S3/S4 handoff consumers

本文把 S2 从 first pass 推到可验收 live product evidence 的操作路径固定下来。它不是新的愿景，也不是把 debug-smoke sidecar 当成完成证据；它是授权机器上关闭 S2 gate 前必须执行和保存的证据清单。

结论先写清楚：S2 只有在真实 macOS 15+ 授权环境里证明普通录制能写出可重载 semantic bundle，并能把 saved macro 关联到该 bundle 后，才能解锁 S3 installed-app Review 和 S4 product-ready live catalog/search/suggestion。Fixture、blocked preflight、explicit temp bundle、synthetic redaction rehearsal 都只能作为辅助证据。

## 1. Evidence Directory

建议把 S2 live evidence 放在：

```text
docs/semantic-recording-ai/live-evidence/
```

该目录可以按日期或场景建子目录，例如：

```text
docs/semantic-recording-ai/live-evidence/2026-07-07-checkout-smoke/
docs/semantic-recording-ai/live-evidence/2026-07-07-recorder-bridge/
docs/semantic-recording-ai/live-evidence/2026-07-07-suppression-redaction/
docs/semantic-recording-ai/live-evidence/2026-07-07-cleanup/
```

不要提交空 `.mov`、空 bundle、未填字段 sidecar 或含敏感内容的未脱敏录屏。不能保存真实敏感内容时，保存 sidecar、redacted refs、hash/count/readiness 结果和操作说明；真实 password/Secure Input/excluded-context evidence 仍要证明 suppression/redaction 行为发生过。

## 2. Required Capture Order

### Step 0: Build And Record Context

在授权机器上先记录工作树和构建来源：

```bash
git status --short --branch
swift build -Xswiftc -swift-version -Xswiftc 6
```

Sidecar 必须写明：

- commit or dirty worktree note
- app build/run source
- macOS version
- target app/window
- enabled permissions
- enabled experimental settings
- known gaps

### Step 1: Preflight Evidence

先跑 preflight-only，确认不会在权限缺失时误创建 bundle：

```bash
.build/debug/SparkleRecorder semantic-recording debug-smoke \
  --preflight-only \
  --json \
  --require-ocr \
  --require-window-or-ax \
  --evidence-sidecar docs/semantic-recording-ai/live-evidence/<run>/s2-preflight.md
```

Accepted evidence:

- sidecar includes `command plan`
- preflight status is ready, blocked, or degraded with exact issue rows
- blocked state does not create a bundle directory
- degraded state explains which capability is missing

Not enough to close S2:

- blocked preflight by itself
- preflight-only sidecar without a later finished bundle
- terminal copy/paste without a saved sidecar

### Step 2: Authorized Live Bundle Smoke

Run the live capture on macOS 15+ with the stricter policy:

```bash
.build/debug/SparkleRecorder semantic-recording debug-smoke \
  --json \
  --require-ocr \
  --require-window-or-ax \
  --evidence-sidecar docs/semantic-recording-ai/live-evidence/<run>/s2-live-smoke.md
```

Optional safe redaction rehearsal:

```bash
.build/debug/SparkleRecorder semantic-recording debug-smoke \
  --json \
  --require-ocr \
  --require-window-or-ax \
  --synthetic-redaction \
  --synthetic-redaction-reason safe-window-redaction-pipeline-rehearsal \
  --evidence-sidecar docs/semantic-recording-ai/live-evidence/<run>/s2-live-smoke-synthetic-redaction.md
```

Accepted evidence:

- command exits with finished status
- sidecar names the bundle directory and manifest path
- persisted reload status is available
- `persistedBundleCountCheck.status` is `matched`
- readiness policy includes video, keyframes, timeline, AI-safe events, OCR and window/AX requirement
- readiness status is ready, or any degraded status has a reviewed known-gap note that does not contradict the checked gate
- bundle directory contains real `.mov`, keyframe PNGs, manifest and sidecars
- `RecordingBundleStore.loadBundleTolerant` diagnostics show no corrupt required sidecar

Not enough to close S2:

- `--keyframes-only` run for the default video gate
- synthetic redaction rehearsal as replacement for real sensitive/excluded-context proof
- manifest-only bundle without sidecars
- in-memory finish counts without persisted reload evidence

### Step 3: Inspect Stored Bundle Through S4 Read-Only CLI

Use the stored-bundle commands only as inspection, not as product-ready S4 proof:

```bash
.build/debug/SparkleRecorder recording show <recording-uuid> --bundle-path <bundle-dir> --json
.build/debug/SparkleRecorder recording explain <recording-uuid> --bundle-path <bundle-dir> --json
.build/debug/SparkleRecorder recording frames <recording-uuid> --bundle-path <bundle-dir> --json
.build/debug/SparkleRecorder recording ocr search <recording-uuid> --bundle-path <bundle-dir> --text "<visible text>" --json
.build/debug/SparkleRecorder recording visual search <recording-uuid> --bundle-path <bundle-dir> --json
```

Use the recording UUID from the finished debug-smoke sidecar or bundle manifest. `--bundle-path` selects the source directory, but the CLI still requires the recording id and verifies that it matches the manifest id.

Accepted evidence:

- commands return `sparkle.cli.result.v1`
- output uses safe refs and evidence IDs
- OCR search reports `availability: persistedBundle`
- missing artifact state is explicit when an artifact is absent

Not enough to close S4:

- explicit `--bundle-path` proof as product-ready default/live catalog
- metadata-only visual search as image-byte similarity
- stored/live suggestions returning unavailable

### Step 4: Ordinary Recorder Bridge Proof

After the debug smoke bundle is accepted, prove the actual user recording path:

1. Enable the experimental visual evidence setting in the installed app.
2. Start an ordinary macro recording from the app UI.
3. Confirm preflight runs before countdown.
4. Stop normally.
5. Verify the playable macro is saved.
6. Verify `SavedMacro.semanticRecording` points to the persisted bundle manifest.
7. Open Macro Review from that saved macro without manual path guessing.

Accepted evidence:

- installed-app recording clip or screenshots for start/preflight/stop/save
- saved macro manifest excerpt or CLI/repository inspection proving `SavedMacro.semanticRecording`
- bundle directory reloads from the saved macro reference
- linked Macro Review opens through `SemanticRecordingReviewPresenter`
- discard/cancel/failure cleanup proof exists for a separate run or sidecar

Not enough to close S2:

- debug-smoke bundle that was never attached to a saved macro
- manually selecting a bundle path in Review as the only proof
- fake macro or fixture macro metadata

### Step 5: Safety, Redaction And Cleanup Proof

Capture these separately from the happy path:

- Secure Input or focused password field suppresses semantic visual capture while ordinary macro recording continues
- excluded app/window/domain rules suppress semantic capture before bundle attachment
- redacted frame/video sidecars are preferred by Review/CLI while source refs stay traceable
- playback-preserving readable macro metadata withholding is visible in save/export/status behavior
- manual cleanup review/confirmation works
- scheduled cleanup first-pass behavior is evidenced on launch or via a reviewed sidecar

Not enough to close safety gates:

- pure suppression tests without live context evidence
- synthetic redaction only
- cleanup dry-run without a reviewed destructive confirmation path
- automatic `textAnchor.text` mutation without an S3 reviewed mutation decision

## 3. Gate Matrix

| Gate | Minimum Evidence | Consumer Unblocked |
| --- | --- | --- |
| S2 authorized live bundle | `s2-live-smoke.md`, real bundle dir, `.mov`, keyframes, sidecars, persisted reload, readiness ready under OCR/window/AX policy | S3 can start installed-app Review evidence planning; S4 can start default-root/catalog planning |
| S2 ordinary Recorder bridge | app recording proof, `SavedMacro.semanticRecording`, normal stop save, cleanup on discard/cancel/failure, linked Review opens | S3 installed-app Review gate can be captured |
| S2 safety/privacy/cleanup | Secure Input/password/exclusion suppression, redacted frame/video consumption, metadata withholding, cleanup evidence | Product rollout can be considered after S3 Review mutation boundary |
| S2 root/id policy | documented default root, stable recording id policy, catalog audit behavior, explicit path deprecation point | S4 product-ready `recording list/show/...` can begin |
| S3 installed-app Review | saved-macro-linked live bundle opens, Bundle Health/Run Target/evidence tiles/Open/Reveal render | S3 live frame-to-condition evidence can begin |
| S4 product-ready live query | default root over accepted S2 bundles, safe refs, artifact availability, no image/video bytes by default | stored/live suggestions and draft synthesis can begin |

## 4. Update Rules

After each accepted proof:

1. Add the evidence file paths to `acceptance-checklist.md`.
2. Update `06-current-work-and-next-tasks.md`.
3. Update `14-s0-s4-final-gap-alignment.md` if an owner posture changes.
4. Update `workstreams/s2-app-capture-visual-index.md`.
5. If S3 or S4 is unblocked, update the affected workstream before starting implementation.

Do not check a live-product box from:

- fixture evidence
- blocked preflight evidence
- explicit temp bundle path only
- synthetic redaction rehearsal only
- tests that never touch live ScreenCaptureKit/Vision/AX/app UI
- docs that describe the intended behavior without saved artifacts

## 5. Handoff Package

When S2 is ready to hand a bundle to S3/S4, the handoff package should include:

- live bundle directory path
- manifest path
- evidence sidecar path
- command JSON output path if saved
- saved macro id/name and `SavedMacro.semanticRecording` metadata
- readiness status and issue summary
- known privacy/suppression/redaction notes
- accepted root/id policy note
- explicit statement of which gates remain open

S3 should use the handoff through app-edge presenter/store boundaries. S4 should use default-root/catalog work only after S2 root/id policy is accepted; until then, S4 remains limited to fixtures and explicit stored-bundle reads.

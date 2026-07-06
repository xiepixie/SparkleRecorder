# S2 App Capture And Visual Index

状态：active first pass
Owner：App-edge capture / Vision index / recording bundle storage
并行对象：S0 Workflow Evidence Closure, S1 Contract/Core, S3 Review UX

S2 的任务是把一次用户录制生产成 `SemanticRecordingBundle` 可消费的真实证据：`.mov` 视频、event-aligned keyframes、OCR/视觉/AX observations、suppression 和本地 bundle storage。S2 不负责 Review UI，也不负责 CLI/AI 命令命名；这些分别属于 S3/S4。

## Current First Pass

已完成：

- Core capture session contract: `SemanticRecordingCaptureSession`
- Fake-client tests: `SemanticRecordingCaptureTests`
- Core lifecycle/preflight gate: `SemanticRecordingLifecycle`
- App-edge live session runner: `LiveSemanticRecordingSession`
- Debug-only live smoke command: `semantic-recording debug-smoke`
- App-edge live client boundary: `LiveSemanticCaptureClient.live(bundleDirectory:)`
- Semantic recording permission preflight contract: `SemanticRecordingPreflight*`
- App-edge permission snapshot bridge: `SemanticRecordingPreflightClient.live`
- CLI-safe permission snapshot bridge: `SemanticRecordingPreflightClient.liveCommandLine`
- ScreenCaptureKit movie adapter skeleton: `ScreenCaptureKitMovieRecorder`
- ScreenCaptureKit keyframe PNG adapter skeleton: `ScreenCaptureKitFrameSource`
- Vision OCR frame indexer skeleton: `VisionRecordingIndexer`
- Bundle storage skeleton: `RecordingBundleStore`

当前 first pass 证明：

- fake movie client 可以生成一个 `RecordingVideoSegment`
- start / event / stop keyframes 可以按 `RecordingFrameReference` 写入 bundle
- `RecordedEvent` 会被映射到 `RecordingTimelineEvent` 和 AI-safe `RecordingSemanticEvent`
- keyframe-only 模式不会启动 movie recorder，也不会给 frame 写 `videoSegmentID`
- frame indexer 可以把 OCR observations 回填到同一个 bundle
- app-edge adapter 已按 macOS 15+ `SCRecordingOutput` / `SCScreenshotManager.captureImage` 路线编译通过
- preflight evaluator 区分 blocking 和 degraded：Input Monitoring / Screen Recording 阻塞 playable events、movie、keyframes、OCR；Accessibility 降级 AX/window metadata
- lifecycle gate 会在创建 capture session 前评估 preflight：blocking 不创建 session，degraded 返回给调用方但允许开始；权限补齐后 blocked start 可以重试
- live session runner 已把 PermissionCenter preflight、bundle directory creation、live ScreenCaptureKit/Vision capture client、core lifecycle 和 `RecordingBundleStore.write` 串成一个 app-edge internal entry point；blocking preflight 不创建 bundle directory
- `semantic-recording debug-smoke` 是 S2 调试入口：默认捕获显示器、写出 bundle directory 和 manifest path；它只做 live capture smoke，不提供 `recording show/frames/search` 等 S4 用户查询能力
- `semantic-recording debug-smoke --preflight-only` 是授权预检入口：使用 CLI-safe 系统权限快照，不创建 bundle directory，不触碰 ScreenCaptureKit，避免 CLI semaphore 等待 MainActor permission bridge 时卡住

尚未完成：

- 普通宏录制流程中接入 `LiveSemanticRecordingSession`
- 在授权机器上实际运行 `semantic-recording debug-smoke --json` 并保留 live `.mov` / keyframes / bundle sidecar 作为产品证据
- AX/window metadata snapshots
- suppression 自动生产：Secure Input、password fields、excluded apps/windows/domains
- retention/deletion UI 和存储策略
- preflight result 的用户可见 UI / degraded-mode guidance
- frame-derived asset copy into `AutomationWorkflowDraftVisualAssets`
- S3 Review UI integration
- S4 `recording show` / `recording frames`

## Accepted S1 Contract Usage

S2 当前只消费 S1 已接受的 value model，不改变 schema 语义：

| S1 Type | S2 Usage |
| --- | --- |
| `SemanticRecordingBundle` | session finish 时组装 bundle |
| `RecordingVideoSegment` | movie recorder finish 后提供 duration/codec/fileType/frameSize |
| `RecordingFrameReference` | start/event/stop keyframes，携带 safe `imageRef` |
| `RecordingTimelineEvent` | 每个 `RecordedEvent` 一个 timeline entry |
| `RecordingSemanticEvent` | AI-safe click/input/scroll/wait/condition candidate summary |
| `RecordingVisualObservation` | Vision OCR indexer 回填 `ocrText` observations |
| `RecordingCapturePolicy` | 支持 default video+keyframes 与 keyframe-only |
| `RecordingArtifactRef` | movie/keyframe/store 全部使用 safe relative refs |
| `SemanticRecordingPreflightPolicy` | 根据 capture policy 和权限快照评估 blocking/degraded capabilities |

如果 S2 后续需要新的 provider metadata，先写入 `metadata` 或 provider fields；只有当 S1 schema 无法表达时，才向 S1 发起 interface request。

## App-Edge Boundaries

Core target:

- `SemanticRecordingCapture.swift`
- `SemanticRecordingLifecycle.swift`
- session lifecycle
- preflight gating before capture session creation
- event/frame/video alignment
- fake-client tests
- no ScreenCaptureKit / Vision / AX / file IO

App target:

- `ScreenCaptureKitSemanticCapture.swift`
- `VisionRecordingIndexer.swift`
- `RecordingBundleStore.swift`
- `RecordingArtifactURL.swift`
- `LiveSemanticRecordingPreflight.swift`
- `LiveSemanticRecordingSession.swift`
- `main.swift` debug-only `semantic-recording debug-smoke`
- ScreenCaptureKit, Vision image loading, PNG writing, bundle directory writing
- PermissionCenter-based permission snapshot for app-edge preflight
- command-line permission snapshot for debug smoke preflight and live smoke startup
- app-edge session orchestration: preflight -> bundle directory -> live capture client -> lifecycle -> store write

SwiftUI:

- no direct Vision / ScreenCaptureKit / raw path construction in this pass
- S3 should consume bundle/store/presenter results later

## Live API Notes

`SCRecordingOutput` constraints from local SDK and Apple docs:

- macOS 15+ only
- one recording output per `SCStream`
- add recording output before `startCapture` to include first samples
- removing recording output or stopping capture ends the recording
- stream configuration updates while recording should be treated as recording-ending events

Current adapter follows the first-sample rule: `ScreenCaptureKitMovieRecorder.start` creates stream, creates `SCRecordingOutput`, calls `addRecordingOutput`, then starts capture.

`ScreenCaptureKitFrameSource` uses the same target resolver and writes PNG to the safe frame artifact ref requested by core.

`VisionRecordingIndexer` reads the stored frame PNG and emits normalized-frame OCR bounds. This is enough for OCR query fixtures and later frame-to-condition UI, but it is not a full pattern search system.

## Interface Requests

### To S0

S0 remains responsible for live Workflow evidence. S2 does not need to wait for S0 to keep building fake-client capture boundaries, but S2 should not claim product trust until S0 live evidence clips exist.

Current ask:

- when S0 records live clips, keep sidecars explicit about App build/run source and evidence source so S2 can reuse the capture template for semantic recording product evidence later.

### To S1

No schema change request yet.

Potential future request:

- retention/deletion metadata may need a first-class bundle policy field after storage UX is designed.
- AX/window snapshots may need explicit observation payload fields if `RecordingVisualObservation.metadata` becomes too lossy.

### To S3

S3 can start Review UI against `SemanticRecordingFixture.checkoutBundle()` and should not wait for live S2 capture. When S2 provides a live bundle directory, S3 should load through presenter/store boundaries rather than raw paths.

### To S4

S4 can start `recording show` / `recording frames` against fixture bundles after this S2 contract; live directories are not a blocker for fixture CLI.

## Verification

Current targeted verification:

```bash
swift test --scratch-path .build-test-s2 --enable-swift-testing --disable-xctest --filter 'SemanticRecordingCaptureTests'
swift test --scratch-path .build-test-s2 --enable-swift-testing --disable-xctest --filter 'SemanticRecordingCaptureTests|SemanticRecordingPreflightTests'
swift test --scratch-path .build-test-s2 --enable-swift-testing --disable-xctest --filter 'SemanticRecordingCaptureTests|SemanticRecordingPreflightTests|SemanticRecordingLifecycleTests'
swift build -Xswiftc -swift-version -Xswiftc 6
.build/debug/SparkleRecorder semantic-recording debug-smoke --duration 0 --json
.build/debug/SparkleRecorder semantic-recording debug-smoke --preflight-only --json
```

Observed status on 2026-07-06:

- `SemanticRecordingCaptureTests`: 4 tests passed
- `SemanticRecordingCaptureTests|SemanticRecordingPreflightTests`: 9 tests passed
- `SemanticRecordingCaptureTests|SemanticRecordingPreflightTests|SemanticRecordingLifecycleTests`: 13 tests passed
- Swift 6 build: passed
- `semantic-recording debug-smoke --duration 0 --json`: route/error-envelope smoke passed without touching ScreenCaptureKit; live capture smoke still needs an authorized macOS 15+ machine
- `semantic-recording debug-smoke --preflight-only --json`: verified in an isolated S2 patch tree; it returned quickly without creating a bundle or touching ScreenCaptureKit. On this machine it exited 2 with Input Monitoring blocked, Screen Recording authorized and Accessibility degraded.

## Next Tasks

1. Run `semantic-recording debug-smoke --preflight-only --json` locally before live capture to verify permissions and degraded capabilities.
2. Run `semantic-recording debug-smoke --json` on an authorized macOS 15+ machine and capture the resulting bundle directory as S2 live evidence.
3. Surface preflight/degraded-mode result in the app shell before starting semantic recording.
4. Wire `LiveSemanticRecordingSession` into the existing recording lifecycle behind a feature flag after debug-smoke evidence is captured.
5. Add AX/window snapshot adapter after video/keyframe smoke works.
6. Add suppression producer for secure input/password/excluded target paths before exposing user-facing semantic recording.
7. Define retention/deletion behavior before any broad user-visible rollout.

## Implementation Log

- 2026-07-06: Added `SemanticRecordingCaptureSession`, fake capture clients and `SemanticRecordingCaptureTests` to prove movie/keyframe/event alignment without real ScreenCaptureKit or Vision in unit tests.
- 2026-07-06: Added app-edge `LiveSemanticCaptureClient`, `ScreenCaptureKitMovieRecorder`, `ScreenCaptureKitFrameSource`, `VisionRecordingIndexer` and `RecordingBundleStore` skeletons. Build compiles against macOS 15+ ScreenCaptureKit APIs, but no live product evidence is claimed.
- 2026-07-06: Added `SemanticRecordingPreflight` value model/evaluator, live `PermissionCenter` bridge and `SemanticRecordingPreflightTests`; UI surfacing and ordinary `Recorder.swift` lifecycle wiring remain open.
- 2026-07-06: Added `SemanticRecordingLifecycle` and `SemanticRecordingLifecycleTests`; core now has an internal entry point that evaluates preflight before constructing the capture session, blocks Screen Recording/Input Monitoring failures without side effects, allows Accessibility-degraded capture, records/finishes through the wrapped session and supports retry after permissions change. Ordinary `Recorder.swift` wiring and user-visible preflight UI remain open.
- 2026-07-06: Added app-edge `LiveSemanticRecordingSession`; it evaluates live preflight before creating a bundle directory, constructs the live ScreenCaptureKit/Vision capture client only after preflight passes, delegates record/finish to `SemanticRecordingLifecycle`, and writes the finished bundle through `RecordingBundleStore`. This is an internal entry point for the next smoke/Recorder wiring slice, not live product evidence.
- 2026-07-06: Added `semantic-recording debug-smoke`; it starts `LiveSemanticRecordingSession`, records one synthetic event, finishes the bundle and prints JSON/plain output with bundle and manifest paths. Parser/error-envelope smoke is verified; real ScreenCaptureKit run is intentionally left as the next authorized-machine evidence step.
- 2026-07-06: Added CLI-safe preflight for `semantic-recording debug-smoke --preflight-only` and switched the debug smoke startup to `SemanticRecordingPreflightClient.liveCommandLine`, keeping App/UI `PermissionCenter` preflight on MainActor while avoiding CLI deadlock before live capture evidence is attempted.

# Owner B: Adapters / Persistence Workstream

Owner B owns the boundary between pure AutomationEngine state and the real macOS/app world. The job is to wrap Player, Scheduler, ResourceArbiter, and repository persistence as mockable clients that emit `AutomationAction` instead of mutating state directly.

## Owns

| Area | Files |
| --- | --- |
| Engine runtime shell | `Sources/SparkleRecorder/AutomationEngineRuntime.swift` |
| Runtime lifecycle session | `Sources/SparkleRecorder/AutomationRuntimeSession.swift` |
| Effect runner | `Sources/SparkleRecorder/AutomationEffectRunner.swift` |
| Resource arbitration | `Sources/SparkleRecorder/AutomationResourceArbiter.swift` |
| Player adapter | `Sources/SparkleRecorder/AutomationPlayerClient.swift` |
| Live Player bridge | `Sources/SparkleRecorder/LiveAutomationPlayerClient.swift` |
| Live condition evaluator | `Sources/SparkleRecorder/LiveAutomationConditionEvaluatorClient.swift` |
| Live runtime host | `Sources/SparkleRecorder/LiveAutomationRuntimeHost.swift` |
| Scheduler adapter | `Sources/SparkleRecorder/AutomationSchedulerClient.swift` |
| Repository client | `Sources/SparkleRecorder/AutomationRepositoryClient.swift` |
| Repository snapshot/refresh | `AutomationRepositorySnapshotClient` in `Sources/SparkleRecorder/AutomationRepositoryClient.swift` |
| Runtime handoff mailbox | `Sources/SparkleRecorder/AutomationRuntimeHandoff.swift`, `LiveAutomationRuntimeHost` polling |
| Persistence format | `AutomationPersistenceDocument` and `AutomationWorkflowPackageDocument` in `Sources/SparkleRecorder/AutomationRepositoryClient.swift` |
| Adapter tests | `Tests/SparkleRecorderTests/AutomationOwnerBClientTests.swift`, `Tests/SparkleRecorderTests/AutomationRuntimeSessionTests.swift` |

## Hard Boundaries

- Do not mutate `AutomationRunState` directly.
- Do not import SwiftUI.
- Do not start `Player` from scheduler directly; scheduler emits actions only.
- Do not let live clients hide failures as booleans; map them to `AutomationOutcome`.
- Do not persist runtime state back into `SavedMacro`.

## Inputs From Other Owners

| From | Input |
| --- | --- |
| Owner A | Accepted action/effect contract, run lifecycle semantics, terminal release ordering |
| Owner C | UI needs for progress, error text, run history display, repository refresh behavior |

## Outputs To Other Owners

| To | Output |
| --- | --- |
| Owner A | Fake client events for reducer tests, live-client failure cases that require new outcomes/actions |
| Owner C | Repository projections, run history fields, client status values suitable for display |

## Phase 1 Tasks

1. [x] Implement `ResourceArbiter` skeleton with foreground-input exclusivity.
2. [x] Implement idempotent release and `panicRelease(runID:)`.
3. [x] Define `PlayerClient` result/completion mapping into `AutomationOutcome`.
4. [x] Define `SchedulerClient` that emits `clockTick` and manual trigger actions.
5. [x] Define `AutomationRepositoryClient` with `automations.json` workflow load/save and append-only run history.
6. [x] Provide fake/in-memory clients for Swift Testing.
7. [x] Keep live clients thin until reducer behavior is stable.
8. [x] Consume Owner A `AutomationEffect` values in `AutomationEffectRunner` and emit only `AutomationAction` values back.
9. [x] Add `AutomationEngineRuntime` shell so manual actions, scheduler actions, reducer effects, and follow-up adapter actions share one path.
10. [x] Add `AutomationRuntimeSession` to restore repository state and own scheduler/player event tasks.
11. [x] Add `LiveAutomationRuntimeHost` and start it from `MenuBarController` app lifecycle.
12. [x] Add first-pass live OCR text condition evaluator without changing reducer state.
13. [x] Add repository snapshot/refresh result for UI-safe workflow/run-history loading.
14. [x] Support multi-resource requirements with batch lease handoff and partial-acquire cleanup.
15. [x] Add graceful runtime shutdown: active runs cancel through reducer/effects before background streams stop.
16. [x] Add contextual condition evaluation for previous outcomes, injected external signals, injected manual approval, and OCR search-region filtering.
17. [x] Add repository refresh state boundary with idle/loading/loaded/failed values and previous snapshot preservation.
18. [x] Persist reducer-approved workflow edits through `AutomationEffect.persistWorkflows`.
19. [x] Add OCR search-region coordinate spaces and runtime context injection for display/window/content remapping.
20. [x] Freeze `.sparkrec_workflow` as a static workflow package codec with version, duplicate ID, and DAG validation.
21. [x] Add App-host runtime handoff mailbox first pass for CLI manual-start/cancel-run delivery when the App is already running.

## Acceptance Criteria

- Only one foreground input lease can exist.
- Release is safe to call multiple times.
- Panic release can clear an orphaned lease by `runID`.
- Player/Scheduler clients never mutate state; they emit actions.
- Same macro can append multiple run records without changing `SavedMacro`.
- Repository tests use temporary directories.

## Interface Requests

- Resolved: Owner A reducer returns `AutomationEffect` values; orchestration should consume effects outside the reducer.
- Resolved: Owner A consumes `AutomationResourceLeaseResult.action(runID:at:)`, `AutomationPlayerStartResult.action(runID:at:)`, `AutomationPlayerCompletion.action(runID:at:)`, and `AutomationSchedulerEvent.action` without adding direct adapter calls inside the reducer.
- Resolved: Owner C reads run history through `AutomationRepositoryRefreshClient` / `AutomationRepositorySnapshotClient` value boundaries instead of loading screenshots, macro packages, or JSON files from SwiftUI.

## Accepted Contracts

- `AutomationOutcome` is the adapter output language.
- `AutomationTaskRun.id` is the `runID` for lease, Player, evidence, and run history correlation.
- `AutomationResourceLeaseStore` owns foreground-input lease exclusivity; release and panic release are idempotent.
- `AutomationSchedulerClient` emits scheduler events only; manual and timed starts map to `AutomationAction`.
- `AutomationPersistenceDocument` stores static workflows and append-only `AutomationTaskRun` history in `automations.json`.
- `AutomationWorkflowPackageDocument` stores exportable static workflows only. It never includes `AutomationTaskRun`, evidence, `SavedMacro.events`, or `.sparkrec` macro package payloads.
- `AutomationWorkflowPackage.encode/decode/validate` owns package compatibility checks: current version only, non-empty workflow list, no duplicate workflow IDs, and no invalid workflow DAGs.
- `SavedMacro` remains a static template; Owner B repository code does not mutate macro metadata or event payloads.
- `AutomationRepositorySnapshotClient.refresh` returns either `AutomationRepositorySnapshot` or `AutomationRepositoryRefreshFailure`; UI code should consume that value rather than catching repository throws in SwiftUI.
- `AutomationRepositoryRefreshClient` exposes `idle`, `loading`, `loaded`, and `failed` states. Loading/failed states preserve the previous snapshot so Owner C can keep rendering old data while showing progress/error state.
- Owner A emits live-work requests as `AutomationEffect`.
- Owner B must consume `requestResource`, `releaseResource`, `startPlayer`, `cancelPlayer`, `evaluateCondition`, `wait`, `sendNotification`, `persistWorkflows`, and `persistRun`.
- `AutomationEffect.evaluateCondition` carries `previousOutcomes` derived by Owner A from `AutomationTaskRun.upstreamRunIDs`; Owner B consumes that value through `AutomationConditionEvaluationRequest` and does not read reducer state.
- Owner B must return completion only as `AutomationAction` values, never direct state mutation.
- `AutomationTaskRun.executionID` links a chain of dependent runs.
- Owner C only needs evidence availability and run-history timing as metadata (`evidenceID` / `hasEvidence`, start/completion dates); failed playback `evidenceID` maps to macro package per-run evidence (`runs/<evidenceID>/manifest.json` / `report.json`), but screenshots and macro packages must still load only through app-edge presenters, not SwiftUI view bodies.
- `AutomationEffectRunner` is the adapter orchestration boundary; it receives effects and returns actions, but does not own reducer state.
- Single-resource requirements may emit `resourceLeaseAcquired`; multi-resource requirements emit `resourceLeasesAcquired` only after every required lease is acquired. If any resource is denied, Owner B releases already-acquired leases before emitting `resourceLeaseDenied`.
- `AutomationEngineRuntime` may hold `AutomationRunState`, but only mutates it by calling `AutomationReducer`; all live work remains behind Owner B clients.
- `AutomationRuntimeSession` owns runtime startup/shutdown: it loads `AutomationRepositoryClient.loadWorkflows` and `loadRunHistory`, starts `AutomationSchedulerClient.actions()`, starts `AutomationPlayerClient.events()`, and cancels active runs through reducer/effects before stopping background streams.
- `AutomationPlayerClient.events()` is the Player completion channel. Runtime consumes it through `runPlayerEvents()` and feeds resulting `AutomationAction` values back into the reducer.
- `AutomationPlayerStartRequest` inherits `SavedMacro.playbackContext` by default. Workflow playback must carry the saved macro's `surfaces` and `followWindowOffset` into `Player.play`, so bound-window macros wake/activate the same target app/window path as standalone Library/CLI playback. Callers may still pass an explicit `PlaybackContext` for tests or specialized replay.
- `cancelRun` for queued/running macro work emits `cancelPlayer`; Owner B calls `AutomationPlayerClient.cancel` and still lets reducer-owned terminal handling release leases and persist run history.
- `LiveAutomationPlayerClient` bridges existing `Player.play` detailed completion into `AutomationPlayerClient.events()`; it must not mutate `AutomationRunState`.
- `PlaybackRunEngine` owns the live Player outer loop boundary: plan loop, window activation/refresh, conflict abort, async step-runner handoff, progress callbacks, and failure evidence construction. It stays in `SparkleRecorderCore`.
- `LivePlaybackRunStepClient` owns live AppKit locator/OCR step execution and real event posting handoff. It stays in the app target, consumes `PlaybackRunStepRequest`, returns `PlaybackRunStepResult`, and uses core `PlaybackLocatorCache` for locator reuse without putting cache state back into `Player`.
- `PlaybackSynchronousRunEngine` owns the blocking CLI Player outer loop boundary. `LivePlaybackSynchronousRunStepClient` owns blocking AppKit locator/OCR step execution and event posting handoff. They keep `Player.playSynchronously` as a thin composition point.
- `LiveAutomationRuntimeHost` is app-target glue only. It wires `Player`, `WindowTracker`, `MacroRepositoryClient`, `AutomationRepositoryClient.fileBacked`, and timer scheduler into `AutomationRuntimeSession`; it must not be added to `SparkleRecorderCore`.
- `AutomationConditionEvaluatorClient.contextual` handles `previousOutcome`, injected `externalSignal`, injected `manualApproval`, and testable OCR closures. Context-only conditions return `AutomationConditionEvaluationEvidence` with predicate/signal/approval diagnostics through `evaluateResult`, while the legacy `evaluate` helper remains outcome-only.
- `LiveAutomationConditionEvaluatorClient` supports full-display OCR text matching through existing `ScreenCaptureService` and `VisionDetector`, filters matches by `AutomationOCRSearchRegionSpace`, maps OCR capture failures to `AutomationOutcome`, returns durable diagnostics for matched, not-matched, failed, and rejected terminal paths, and stays SwiftUI-free. `LiveAutomationRuntimeHost` accepts external signal, manual approval, and OCR region context providers from app/product code without letting SwiftUI call the evaluator directly.
- `AutomationSignalStore` / `AutomationExternalSignalSourceView` and `AutomationManualApprovalPresenter` are app-target sources for provider data; they feed Owner B clients and do not mutate reducer state.
- `AutomationRuntimeHandoffCommand` is a core value contract for App-host delivery. `AutomationRuntimeHandoffClient` may enqueue/load/remove commands from a file-backed mailbox or in-memory fake, but it never mutates reducer state directly.
- CLI `workflow run/cancel --handoff app` writes mailbox commands only; it does not run `Player` in the CLI process. `LiveAutomationRuntimeHost` consumes commands by dispatching their mapped `AutomationAction` through `AutomationRuntimeSession`, then removes successfully dispatched commands.
- The runtime handoff mailbox is a first pass, not a daemon. It writes command receipts so CLI/AI can query `workflow handoff status`; the status payload also reads repository run history to include run snapshots and workflow status for dispatched commands when possible. It still does not wake a non-running App, keep a CLI session alive, or provide push-style live progress/results.
- CLI `workflow acceptance bound-window` is the live product-acceptance bridge for real bound-window macros. Without confirmation it only validates that the selected workflow task resolves to a saved macro with playable events, saved surfaces, and a non-empty `SavedMacro.playbackContext`. With `--activate-target` it may ask AppKit to activate already-running bound target apps; with `--confirm-launch` it may launch missing target apps; with `--confirm-playback --handoff app` it only enqueues the production App-host manual-start command. It must not run `Player` inside the CLI process, and it must not be treated as a unit-test replacement because confirmation modes can activate apps and move real input through the App host.

## Planning Log

- 2026-07-05: Phase 0 contract exists; next work waits on Owner A reducer/effect shape.
- 2026-07-05: Owner B client skeletons landed with resource lease store, player result mapping, scheduler event mapping, JSON repository, and Swift Testing coverage.
- 2026-07-05: `AutomationEffectRunner` added for `AutomationEffect` consumption across resource, player, condition, wait, notification, and persistence effects.
- 2026-07-05: `AutomationEngineRuntime` added to loop reducer effects and follow-up actions; runtime tests cover manual/scheduler shared path and PlayerClient usage.
- 2026-07-05: Player completion stream added to `AutomationPlayerClient`; runtime tests cover `playerFinished` events completing and persisting macro runs.
- 2026-07-05: `LiveAutomationPlayerClient` added; existing `Player.play` now supports automation run IDs and detailed `AutomationPlayerCompletion`.
- 2026-07-05: `AutomationRuntimeSession` and `LiveAutomationRuntimeHost` added; menu-bar lifecycle now starts repository restore, scheduler ticks, and Player completion event consumption.
- 2026-07-05: `LiveAutomationConditionEvaluatorClient` added for first-pass OCR text conditions without importing SwiftUI or mutating reducer state.
- 2026-07-05: `AutomationRepositorySnapshotClient` added so Owner C can refresh workflows/run history as a value result without direct file IO.
- 2026-07-05: A/B resource handoff now supports multi-resource batches via `resourceLeasesAcquired`; partial acquisition is cleaned up before denial.
- 2026-07-05: Runtime shutdown now cancels active macro runs through `cancelPlayer`, releases leases, and persists cancelled run history before stopping streams.
- 2026-07-05: Condition evaluation now receives upstream outcomes in `AutomationEffect.evaluateCondition`, with contextual provider hooks for external signals and manual approval.
- 2026-07-05: Repository refresh gained a stateful UI-safe boundary so Owner C can display loading/error while retaining the last snapshot.
- 2026-07-05: Workflow edit persistence added through `persistWorkflows`, keeping UI edits behind reducer/effect/repository boundaries.
- 2026-07-05: `LiveAutomationRuntimeHost` now accepts external signal and manual approval providers so product/UI wiring can feed conditions without crossing the evaluator boundary.
- 2026-07-05: OCR search regions gained explicit display/window/content coordinate spaces plus a runtime context provider for live evaluator remapping.
- 2026-07-05: App-level external signal store and manual approval presenter now feed runtime host provider clients.
- 2026-07-05: `.sparkrec_workflow` package codec landed as an Owner B boundary for static workflow import/export; Owner C first pass now owns UI file pickers and conflict prompts, while final sharing placement remains product-layer polish.
- 2026-07-05: `PlaybackRunEngine` extracted the live Player outer loop from `Player.play`, with Swift Testing coverage for loop/progress callbacks, window refresh handoff, conflict abort, and failure evidence construction.
- 2026-07-05: `LivePlaybackRunStepClient` extracted live locator/OCR step execution and event posting handoff from `Player.play`; core `PlaybackLocatorCacheTests` cover cache key and reuse semantics.
- 2026-07-05: `PlaybackSynchronousRunEngine` and `LivePlaybackSynchronousRunStepClient` extracted the blocking CLI playback loop/step path from `Player.playSynchronously`, with Swift Testing coverage for loop/progress callbacks, conflict abort, failure evidence, and continuous-plan no-op behavior.
- 2026-07-06: `AutomationRuntimeHandoff` added a file-backed App-host mailbox first pass. CLI `workflow run/cancel --handoff app` enqueues manual-start/cancel-run commands; `LiveAutomationRuntimeHost` polls and dispatches them through the existing runtime session.
- 2026-07-06: Runtime handoff receipts/status added and then extended with repository-backed result context. `AutomationRuntimeHandoffReceipt` records dispatched/failed command handling plus created run IDs; `LiveAutomationRuntimeHost` atomically completes consumed commands with receipts; CLI `workflow handoff status <command-id>` returns pending/dispatched/failed/missing state plus `runs` snapshots and `workflowStatus` when the same repository has persisted run history. This gives AI a direct readback for created/running/terminal runs without turning the mailbox into a daemon or stream.
- 2026-07-06: Condition diagnostics artifact refs added. `AutomationConditionEvidenceArtifactWriter` saves live OCR/visual last-sample and watched-region PNGs under App Support `AutomationEvidence/<runID>/...`; `AutomationConditionEvidenceArtifactPresenter` resolves those safe relative refs for preview/open/reveal; `AutomationConditionEvaluationEvidence` persists relative refs only, so repository JSON stays value-based and SwiftUI does not call ScreenCapture/OCR/image providers or construct artifact paths itself.
- 2026-07-06: Live condition diagnostics were hardened for failure payloads. OCR capture failures now return explanatory `AutomationConditionEvaluationEvidence`; OCR/Vision failures after a screenshot save the last sample/crop when possible. Visual capture, bitmap decode, and configuration failures also return evidence with outcome, sample count, target description, diagnostic fields, and sample artifacts when a screenshot was available; bitmap-decode failure now saves the captured display sample and watched-region crop before returning the rejected payload.
- 2026-07-06: Context-only condition diagnostics now use the same result path. `AutomationConditionEvaluationEvidence.contextual` builds durable payloads for `previousOutcome`, external signal, and manual approval conditions, and both `AutomationConditionEvaluatorClient.contextual` and `LiveAutomationConditionEvaluatorClient` attach that payload to `evaluateResult`.
- 2026-07-06: Workflow macro playback now preserves bound-window context. `SavedMacro.playbackContext` centralizes the Library/CLI/Workflow mapping from macro `surfaces` + `followWindowOffset` to `PlaybackContext`, and `AutomationPlayerStartRequest` defaults to that context so App-host workflow runs can activate/refresh the same target window as standalone macro playback.
- 2026-07-06: Added `workflow acceptance bound-window` as an explicit live acceptance path for Cookie Run Kingdom-style workflows. The command emits `AutomationWorkflowBoundWindowAcceptancePayload` for CLI/AI review, validates the selected task/macro/surface context, optionally activates or launches the saved bound target app, and can enqueue confirmed playback through the App-host handoff mailbox instead of running Player from the CLI.

## Handoff Checklist

- [x] ResourceArbiter fake/live behavior documented.
- [x] Multi-resource batch handoff and partial-denial cleanup documented.
- [x] PlayerClient fake/live behavior documented.
- [x] SchedulerClient fake/live behavior documented.
- [x] Repository JSON format documented.
- [x] Workflow package codec documented.
- [x] Repository snapshot/refresh behavior documented.
- [x] Repository refresh state behavior documented.
- [x] Effect runner behavior documented.
- [x] Runtime reducer/effect/action loop documented.
- [x] Runtime shutdown cancellation path documented.
- [x] Contextual condition evaluator behavior documented.
- [x] OCR region coordinate-space resolver documented and covered by pure tests.
- [x] Player completion action stream documented.
- [x] Live Player bridge documented.
- [x] Playback live run engine boundary documented and covered by pure tests.
- [x] Live playback step runner boundary documented; locator cache/key behavior covered by pure tests.
- [x] Synchronous playback loop/step runner boundary documented and covered by pure tests.
- [x] Live condition evaluator first pass documented.
- [x] Runtime session and menu-bar lifecycle host documented.
- [x] Runtime App-host handoff mailbox and receipt/status first pass documented and covered by fake/file-backed tests.
- [x] Condition diagnostics payload, safe artifact path helper, context-only evidence payloads, live artifact writer, failure/rejected live payload behavior, and artifact presenter boundary documented; core tests cover Codable/backward compatibility/path normalization and contextual evidence, while app-edge writer/presenter/evaluator wiring are verified by Swift 6 build.
- [x] Workflow macro playback inherits `SavedMacro` window binding context before entering the live Player bridge.
- [x] Bound-window workflow acceptance CLI documented; static payload is covered by Swift Testing, while launch/activation/playback modes are opt-in live product acceptance only.
- [x] Adapter tests pass without moving mouse or invoking real OCR.

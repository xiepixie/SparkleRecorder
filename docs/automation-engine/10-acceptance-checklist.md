# Automation Engine Acceptance Checklist

每个阶段结束前按本文件验收。未满足项不能标记为完成。

## Baseline: Pre-Automation Modernization

- [x] Swift 6 package/target baseline is present in the current worktree.
- [x] Swift Testing baseline exists for core value and playback/recording helper tests.
- [x] Recording input is no longer directly tied to a main-run-loop event tap only.
- [x] Event tap startup can report failure back toward UI state.
- [x] High-frequency recording has bounded buffering before UI-facing processing.
- [x] Playback ordinary input steps can use `PlaybackStepExecutor`.
- [x] Playback failure evidence has a pure value boundary before screenshot/persistence.
- [x] Playback run lifecycle has a pure state machine for generation/progress/finish outcome.
- [x] SwiftUI editor selection projection has dedicated tests.

## Phase 0: Core Contract

- [x] `AutomationWorkflow` exists and is `Codable`, `Equatable`, `Sendable`.
- [x] `AutomationTask` exists and is `Codable`, `Equatable`, `Sendable`.
- [x] `AutomationTaskRun` exists and is `Codable`, `Equatable`, `Sendable`.
- [x] `AutomationDependency` exists and supports success/failure/timeout/cancel/condition triggers.
- [x] `AutomationOutcome` exists and distinguishes success, failure, cancel, timeout, resource conflict, permission denied, condition matched/not matched.
- [x] `AutomationEffect.evaluateCondition` carries prior outcomes needed for contextual conditions.
- [x] `SavedMacro` has no workflow runtime state.
- [ ] Workflow-level loops have an explicit contract for loop body, termination/limit and run evidence. Current DAG validation rejects self-dependencies and cycles, so loops are not accepted through dependency back-edges.
- [x] Swift Testing covers Codable roundtrip and Sendable smoke.

## Phase 1: Reducer

- [x] Reducer handles `clockTick(Date)`.
- [x] Reducer handles manual start.
- [x] Reducer handles resource acquired/denied.
- [x] Reducer handles player finished.
- [x] Reducer handles cancel.
- [x] Reducer emits `cancelPlayer` for queued/running macro cancellation.
- [x] Reducer includes completed upstream outcomes in condition evaluation effects.
- [x] Reducer handles workflow edit actions and emits `persistWorkflows`.
- [x] Reducer handles `moveTask` by persisting `AutomationTask.graphPosition`.
- [x] Terminal outcomes release lease before downstream resolution.
- [x] Downstream `earliestStartTime` cascades when upstream completes late.
- [x] Swift Testing covers success, failure, timeout, cancel, resource busy, condition true/false.

## Phase 2: ResourceArbiter

- [x] Only one foreground input lease can exist.
- [x] Release is idempotent.
- [x] Panic release by runID is supported.
- [x] Watchdog path can release orphaned lease.
- [x] Multi-resource requirements start only after a batch lease handoff.
- [x] Partial multi-resource acquisition releases already-acquired leases before denial.
- [x] Tests use fake arbiter.

## Phase 3: Player/Scheduler Clients

- [x] AutomationEngine uses `PlayerClient`, not `Player` directly.
- [x] `PlayerClient` maps Player completion into `AutomationOutcome`.
- [x] Live Player bridge emits completion as `AutomationAction`.
- [x] Scheduler emits actions, does not start Player directly.
- [x] Condition evaluator returns reducer actions through `AutomationEffectRunner`.
- [x] Live condition evaluator has first-pass OCR text matching without mutating reducer state.
- [x] Condition evaluator supports previous outcome context and injected external/manual providers without reading reducer state.
- [x] OCR condition failures map to `AutomationOutcome` instead of a hidden Bool.
- [x] OCR search regions support display/window/content coordinate spaces with pure tests and legacy JSON compatibility.
- [x] External signal and manual approval product sources feed runtime host provider clients without SwiftUI evaluator calls.
- [x] Effect runner consumes `AutomationEffect` values without mutating reducer state.
- [x] Manual and timed triggers share reducer path.
- [x] Runtime session starts scheduler and Player event streams from one lifecycle boundary.
- [x] Runtime session stops by cancelling active runs through reducer/effects before stopping streams.
- [x] `PlaybackRunEngine` owns the live Player outer loop boundary with pure tests for loop/progress/window/conflict/failure handoff.
- [x] `LivePlaybackRunStepClient` owns live locator/OCR step execution and event posting handoff; locator cache/key semantics are covered by pure tests.
- [x] `PlaybackSynchronousRunEngine` and `LivePlaybackSynchronousRunStepClient` own the CLI blocking playback loop/step boundary with pure tests for loop/progress/conflict/failure handoff.

## Phase 4: Persistence

- [x] `automations.json` load/save exists.
- [x] Runtime startup restores workflows and run history from repository.
- [x] Repository snapshot refresh returns projection-ready state.
- [x] Repository refresh failures are value results, not SwiftUI-thrown errors.
- [x] Repository refresh state exposes idle/loading/loaded/failed and preserves previous snapshots.
- [x] Workflow edits persist through repository client, not direct SwiftUI file IO.
- [x] `.sparkrec_workflow` package codec exports/imports static workflows without run history.
- [x] `.sparkrec_workflow` validation rejects unsupported versions, empty packages, duplicate workflow IDs, and invalid workflow DAGs.
- [x] Run history appends without modifying `SavedMacro`.
- [x] Same macro can produce multiple task runs.
- [x] Missing macro is represented safely.
- [x] Repository tests use temporary directories.

## Phase 5: UI

- [x] Automation UI reads reducer projection.
- [x] FlowGraph edges are drawn with Canvas.
- [x] Resource Timeline uses user-facing names, not internal channel numbers.
- [x] UI body avoids heavy DAG searches.
- [x] Drag interactions emit reducer actions.
- [x] Workflow creation emits reducer/persist actions from UI.
- [x] `SavedMacro` can be added as an automation task without storing runtime state in the macro.
- [x] FlowGraph dependency authoring can create and delete edges through reducer actions.
- [x] FlowGraph active-run cancellation emits reducer action, not direct Player calls.
- [x] Task inspector active-run cancellation emits reducer action, not direct Player calls.
- [x] Task inspector edits manual/once/repeating schedules.
- [x] Task inspector shows per-task run history with outcome reason, timing, attempts, execution chain, upstream count, evidence availability, and duration metadata without opening Player internals.
- [x] Condition inspector edits manual approval, external signal, OCR text, previous outcome, timeout, and polling fields.
- [x] OCR condition editing preserves existing region bounds while updating coordinate space.
- [x] Manual approval and external signal have product UI sources that feed provider clients, not the evaluator directly.
- [x] OCR region picker writes new display/window/content `searchRegion` bounds from a screen/window text selection.
- [x] OCR region picker writes arbitrary rectangle `searchRegion` bounds without requiring OCR text detection.
- [x] OCR region editor previews and micro-edits X/Y/W/H bounds.
- [x] OCR region editor explains multi-display display coordinates and window/content context availability.
- [x] Workflow package UI imports/exports `.sparkrec_workflow` through Owner B codec and persists imports through reducer actions.
- [x] Workflow package UI can export all workflows from the workflow list header.
- [x] Workflow package UI can share selected/all workflows through the macOS share sheet.
- [x] Workflow package import conflict UI offers Add Copies / Replace Existing instead of silently overwriting.
- [x] Workflow package import warns when workflows reference macros missing from the local library.

## Phase 6: Verification

- [x] `swift build -Xswiftc -swift-version -Xswiftc 6` passes.
- [x] `swift build -c release` passes.
- [x] `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest` test target/runner compiles.
- [x] `.build-test` is removed after verification.
- [x] `git diff --check` passes.

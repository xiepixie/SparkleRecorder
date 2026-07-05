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
- [x] SwiftUI editor selection projection has dedicated tests.

## Phase 0: Core Contract

- [ ] `AutomationWorkflow` exists and is `Codable`, `Equatable`, `Sendable`.
- [ ] `AutomationTask` exists and is `Codable`, `Equatable`, `Sendable`.
- [ ] `AutomationTaskRun` exists and is `Codable`, `Equatable`, `Sendable`.
- [ ] `AutomationDependency` exists and supports success/failure/timeout/cancel/condition triggers.
- [ ] `AutomationOutcome` exists and distinguishes success, failure, cancel, timeout, resource conflict, permission denied, condition matched/not matched.
- [ ] `SavedMacro` has no workflow runtime state.
- [ ] Swift Testing covers Codable roundtrip and Sendable smoke.

## Phase 1: Reducer

- [ ] Reducer handles `clockTick(Date)`.
- [ ] Reducer handles manual start.
- [ ] Reducer handles resource acquired/denied.
- [ ] Reducer handles player finished.
- [ ] Reducer handles cancel.
- [ ] Terminal outcomes release lease before downstream resolution.
- [ ] Downstream `earliestStartTime` cascades when upstream completes late.
- [ ] Swift Testing covers success, failure, timeout, cancel, resource busy, condition true/false.

## Phase 2: ResourceArbiter

- [ ] Only one foreground input lease can exist.
- [ ] Release is idempotent.
- [ ] Panic release by runID is supported.
- [ ] Watchdog path can release orphaned lease.
- [ ] Tests use fake arbiter.

## Phase 3: Player/Scheduler Clients

- [ ] AutomationEngine uses `PlayerClient`, not `Player` directly.
- [ ] `PlayerClient` maps Player completion into `AutomationOutcome`.
- [ ] Scheduler emits actions, does not start Player directly.
- [ ] Manual and timed triggers share reducer path.

## Phase 4: Persistence

- [ ] `automations.json` load/save exists.
- [ ] Run history appends without modifying `SavedMacro`.
- [ ] Same macro can produce multiple task runs.
- [ ] Missing macro is represented safely.
- [ ] Repository tests use temporary directories.

## Phase 5: UI

- [ ] Automation UI reads reducer projection.
- [ ] FlowGraph edges are drawn with Canvas.
- [ ] Resource Timeline uses user-facing names, not internal channel numbers.
- [ ] UI body avoids heavy DAG searches.
- [ ] Drag interactions emit reducer actions.

## Phase 6: Verification

- [ ] `swift build -Xswiftc -swift-version -Xswiftc 6` passes.
- [ ] `swift build -c release` passes.
- [ ] `swift test --scratch-path .build-test --enable-swift-testing --disable-xctest` test target/runner compiles.
- [ ] `.build-test` is removed after verification.
- [ ] `git diff --check` passes.

# Owner A: Core / Reducer Workstream

Owner A 是状态语义 owner。目标是把 AutomationEngine 做成纯、确定、可测试的状态机，让时间、手动启动、依赖、资源、Player 结果、条件判断和取消都通过 `AutomationAction` 收敛。

## Owns

| Area | Files |
| --- | --- |
| Core contract evolution | `Sources/SparkleRecorder/AutomationContract.swift` |
| Reducer | future `Sources/SparkleRecorder/AutomationReducer.swift` |
| Projection contract | future `Sources/SparkleRecorder/AutomationProjection.swift` |
| Reducer tests | future `Tests/SparkleRecorderTests/AutomationReducerTests.swift` |
| Contract tests | `Tests/SparkleRecorderTests/AutomationContractTests.swift` |

## Hard Boundaries

- Do not call real `Player`, `Scheduler`, `ResourceArbiter`, OCR, file system, AppKit, or SwiftUI.
- Do not store volatile UI state in `AutomationRunState`.
- Do not add runtime fields to `SavedMacro`.
- Do not decide UI layout or persistence format details.

## Inputs From Other Owners

| From | Input |
| --- | --- |
| Owner B | `resourceLeaseAcquired`, `resourceLeasesAcquired`, `resourceLeaseDenied`, `playerStarted`, `playerFinished`, scheduler tick/manual trigger, repository load result |
| Owner C | Projection needs, visible status labels, timeline grouping requirements |

## Outputs To Other Owners

| To | Output |
| --- | --- |
| Owner B | Accepted action names, run lifecycle rules, release ordering, effect requests |
| Owner C | Read-only projection shape, task/run status model, dependency edge state, user-facing status labels |

## Phase 1 Tasks

1. [x] Add `AutomationReducer.reduce(state:action:)`.
2. [x] Decide whether reducer returns `[AutomationEffect]` or mutates state only.
3. [x] Handle `clockTick(Date)` and manual start by creating planned/queued runs.
4. [x] Handle resource acquired/denied without calling the arbiter directly.
5. [x] Handle `playerFinished` and `conditionEvaluated` as terminal outcomes.
6. [x] Release or mark lease release before downstream dependency resolution.
7. [x] Cascade downstream `earliestStartTime` when upstream completes late.
8. [x] Add deterministic Swift Testing coverage for success/failure/timeout/cancel/resource busy/condition true/false.
9. [x] Add static workflow edit actions and reducer-backed task node movement.

## Acceptance Criteria

- Reducer tests do not use real time, mouse, keyboard, OCR, or file system.
- Same `macroID` can produce multiple independent `AutomationTaskRun` values.
- Terminal outcomes cannot leave a foreground-input lease attached to a run.
- Downstream task times shift deterministically after late upstream completion.
- UI projection can be computed without walking the full graph inside SwiftUI `body`.

## Interface Requests

- Owner B should consume `AutomationEffect.requestResource`, `releaseResource`, `startPlayer`, `cancelPlayer`, `evaluateCondition`, `wait`, `sendNotification`, `persistWorkflows`, and `persistRun`.
- Owner A should include upstream `AutomationOutcome` values in `AutomationEffect.evaluateCondition.previousOutcomes`, derived only from reducer state and `AutomationTaskRun.upstreamRunIDs`.
- Owner B should emit only `AutomationAction` values back into the reducer after live work completes.
- Owner C should render `AutomationViewProjection.overview(from:)` rather than recomputing graph status in SwiftUI.
- Owner C should translate UI intents through `AutomationViewIntent`, including `startTask -> manualStart` and `moveTask -> moveTask`.

## Accepted Contracts

- `AutomationContract.swift` is the shared Phase 0 contract.
- All external stimuli enter as `AutomationAction`.
- `AutomationReducer.reduce(state:action:environment:)` returns `AutomationReducerResult`.
- `AutomationEffect` is the handoff language from Owner A to Owner B.
- `resourceLeasesAcquired` is the batch resource handoff for multi-resource requirements; reducer starts the task only after the complete lease set arrives.
- `cancelRun` for queued/running macro work emits `cancelPlayer` before terminal release/persist effects; adapters cancel live Player but do not mutate reducer state.
- `evaluateCondition` carries `previousOutcomes` so Owner B can evaluate `.previousOutcome` without reading `AutomationRunState`.
- `AutomationTaskRun.executionID` groups downstream runs with the root run that spawned them.
- `AutomationTaskRun.upstreamRunIDs` records which terminal upstream runs unlocked a downstream run.
- `AutomationViewProjection.overview(from:)` is the read-only projection contract for Owner C.
- Static workflow edit actions (`upsertWorkflow`, `deleteWorkflow`, `upsertTask`, `deleteTask`, `upsertDependency`, `deleteDependency`) are pure reducer actions; accepted edits emit `persistWorkflows`.
- `AutomationViewIntent.startTask` is the UI-facing contract for manual FlowGraph starts; it maps to `AutomationAction.manualStart`.
- `AutomationAction.moveTask` persists `AutomationTask.graphPosition` and emits `persistWorkflows` for Owner C node-position edits.
- Owner C expects edge status, node positions, and Canvas endpoints to remain projection outputs; SwiftUI must not recompute dependency logic or graph layout in `body`.

## Planning Log

- 2026-07-05: Phase 0 contract exists; next work is reducer and deterministic tests.
- 2026-07-05: Phase 1 reducer/effect/projection contract implemented with deterministic Swift Testing coverage.
- 2026-07-05: A/B condition handoff now includes completed upstream outcomes for contextual condition evaluation.
- 2026-07-05: Reducer edit contract now includes static workflow edits and `moveTask` for C FlowGraph node-position persistence.
- 2026-07-05: UI manual start is now represented as `AutomationViewIntent.startTask`, keeping FlowGraph run buttons on the reducer path.

## Handoff Checklist

- [x] Reducer API documented.
- [x] Effect model documented, if introduced.
- [x] Owner B knows which effects/actions to implement.
- [x] Owner C has stable projection types.
- [x] `AutomationReducerTests` pass.

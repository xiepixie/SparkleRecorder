# Owner 1: Engine, Runtime, And AI CLI

Owner 1 负责 Workflow 页面背后的可运行语义和 AI 可调用接口。这个 owner 合并 core reducer、runtime adapter、persistence、condition evaluator 和 CLI-first AI interface，都在这一侧收口。

## Owns

| Area | Files |
| --- | --- |
| Core workflow contract | `Sources/SparkleRecorder/AutomationContract.swift` |
| Reducer semantics | `Sources/SparkleRecorder/AutomationReducer.swift` |
| Projection shape | `Sources/SparkleRecorder/AutomationViewProjection.swift` |
| Runtime/effect runner | `Sources/SparkleRecorder/AutomationEffectRunner.swift`, `AutomationRuntimeSession.swift`, `AutomationEngineRuntime.swift` |
| Resource arbitration | `Sources/SparkleRecorder/AutomationResourceArbiter.swift` |
| Scheduler | `Sources/SparkleRecorder/AutomationSchedulerClient.swift` |
| Condition evaluator | `Sources/SparkleRecorder/LiveAutomationConditionEvaluatorClient.swift` |
| Repository/package | `Sources/SparkleRecorder/AutomationRepositoryClient.swift` |
| AI interface | future workflow CLI commands |
| Tests | `AutomationReducerTests`, `AutomationOwnerBClientTests`, `AutomationRuntimeSessionTests`, `AutomationViewProjectionTests` |

## Hard Boundary

- Do not import SwiftUI in core/runtime logic.
- Do not call live Player/OCR/file IO from reducer tests.
- Do not let CLI write internal state directly; import must compile draft into accepted workflow values and persist through repository/reducer boundaries.
- Do not build MCP in this phase.
- Do not ask UI to infer scheduler, dependency, retry, timeout, or resource queue semantics.

## Next Tasks

1. [ ] Repeating schedule occurrence model: one scheduled task creates multiple independent `AutomationTaskRun` values.
2. [ ] Resource waiting semantics: resource busy should queue/wait by policy, not become terminal failure by default.
3. [ ] Timeout watchdog action/effect contract: task-level timeout produces `.timedOut` and releases leases before downstream resolution.
4. [ ] Retry reducer semantics: failure/timeout can create next attempt while preserving execution/run history.
5. [ ] Join policy: support `all`, `any`, and `firstMatched` for multi-input nodes.
6. [ ] Visual condition core spec and evaluator first pass: region change, image appears/disappears, pixel/color match.
7. [ ] Projection fields for UI: user-facing status labels, countdown/next run, retry attempt, join status, resource waiting reason.
8. [ ] Workflow draft schema validator.
9. [ ] Macro catalog export for AI: ID, name, tags, duration, resource requirement, description.
10. [ ] CLI commands: `workflow macros`, `workflow draft validate`, `workflow draft simulate`, `workflow import`, `workflow export`.
11. [ ] Fine-grained draft editing commands from [../05-cli-product-contract.md](../05-cli-product-contract.md).

## Outputs To Owner 2

- Ready-for-UI capability notices.
- Projection fields and fixtures.
- Accepted `AutomationAction` / `AutomationEffect` changes.
- Validation warnings keyed by draft task/dependency key.
- Simulation output for AI draft preview and timeline preview.

## Requests From Owner 2

Record requests here only as a summary. The canonical request must live in [../02-backend-frontend-contract.md](../02-backend-frontend-contract.md).

| Request | Status | Link / Notes |
| --- | --- | --- |
| Semantic edge labels for trigger/outcome | proposed | Needs projection field, not UI recomputation. |
| `waitingForResource` queue/resume state | proposed | Needed before final timeline interaction. |
| `nextScheduledOccurrence` | proposed | Needed for schedule inspector and timeline. |
| `timeoutCountdown` | proposed | Needed for running condition/macro nodes. |
| `retryAttemptSummary` | proposed | Needed for run history and node badge. |

## Ready-For-UI Notice Queue

No next-stage capability is ready-for-ui yet. First candidates:

- `workflow macros --format json`.
- `workflow draft validate draft.json --json`.
- macro resolution warnings for missing/ambiguous macros.
- `resourceWaitingReason` projection.
- `nextScheduledOccurrence` projection.

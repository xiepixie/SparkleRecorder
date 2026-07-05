# Owner 2: Product UI And Workflow UX

Owner 2 负责把 Workflow 页面做成用户能完成任务的产品界面。当前页面不能按完成验收；下一阶段先用 fixture 重建可用交互，再接 live projection。

## Owns

| Area | Files |
| --- | --- |
| Main workflow page | `Sources/SparkleRecorder/AutomationMainView.swift`, `AutomationMainContentView.swift` |
| Graph UI | `AutomationFlowGraphView.swift`, `AutomationFlowGraphNodeView.swift`, `AutomationFlowGraphEdgeCanvas.swift` |
| Timeline UI | `AutomationResourceTimelineView.swift`, `AutomationTimelineItemView.swift` |
| Inspector | `AutomationInspectorView.swift`, `AutomationTaskInspectorView.swift`, `AutomationDependencyInspectorView.swift` |
| UI intent boundary | `AutomationViewIntent.swift`, accepted `AutomationAction` edit/start/cancel/move cases |
| Import/export/AI entry | `AutomationWorkflowPackagePresenter.swift`, future AI draft preview UI |
| UI tests/fixtures | `AutomationViewProjectionTests`, future fixture/snapshot/performance tests |

## Hard Boundary

- Do not call Player, scheduler, repository, arbiter, or condition evaluator directly.
- Do not implement scheduler, dependency, retry, timeout, or resource queue semantics in SwiftUI.
- Do not run graph searches or file IO inside SwiftUI `body`.
- Do not depend on drag-only interaction; every critical edit needs a button/menu/inspector path.
- Do not treat a backend capability as real until Owner 1 marks it `ready-for-ui`.
- Do not use saturated full-width control backgrounds for ordinary Workflow controls.
- Do not wrap normal nodes, edge rows, or toolbar actions in `.controlSurface` just to make them louder; reserve emphasis for selected, dangerous, or live-running states.

## Next Tasks

1. [ ] Redesign page layout around left palette, center graph, bottom timeline, right inspector.
2. [ ] Build fixture-driven drag-and-drop orchestration: drag macros from Macro Library into graph/list, move tasks, connect dependencies, delete, select.
3. [ ] Add non-drag controls: move node, reorder, connect from inspector, duplicate, disable.
4. [ ] Make dependency lines semantic: success/failure/timeout/condition labels, arrows, and restrained color accents.
5. [ ] Build visual dependency graph states: arrows, indentation, or `If...Then...Else` grouping for condition flows.
6. [ ] Build runtime feedback states: running outline/progress, planned/running/waiting/completed/failed/timeout timeline states.
7. [ ] Inspector supports schedule, retry, timeout, resource, condition, dependency trigger/delay.
8. [ ] AI draft preview UI consumes the same validate/simulate JSON described in [../05-cli-product-contract.md](../05-cli-product-contract.md).
9. [ ] Visual style pass: remove Web-like high-saturation full-surface buttons and keep Pro macOS restraint.
10. [ ] Performance pass: Canvas edges, stable node sizes, no DAG traversal in `body`.

## Outputs To Owner 1

- Projection gaps.
- Action/intent requests.
- Fixture state requests.
- Validation warning display requirements.
- User-facing labels and error wording.
- CLI preview fields needed by the UI before import.
- Visual design exceptions when an interaction truly needs emphasis.

## Requests To Owner 1

Record detailed requests in [../02-backend-frontend-contract.md](../02-backend-frontend-contract.md), then summarize here.

| Request | Status | Why |
| --- | --- | --- |
| Semantic edge labels | proposed | FlowGraph needs trigger/outcome labels without recomputing dependencies. |
| Resource waiting reason | proposed | Timeline needs “等待鼠标键盘空闲” instead of technical lease state. |
| Next scheduled occurrence | proposed | Users need to see what will run next. |
| Draft validation warnings by key | proposed | AI import preview needs to highlight exact task/dependency errors. |
| Simulation timeline output | proposed | AI draft should be previewed before import. |
| CLI result envelope stability | proposed | UI and AI should read the same validation/simulation structure. |

## Ready-For-Backend Queue

These are UI needs waiting for backend contracts:

- Semantic edge labels for trigger/outcome.
- `waitingForResource` queue/resume state.
- `nextScheduledOccurrence`.
- `timeoutCountdown`.
- `retryAttemptSummary`.
- `draftValidationWarnings` keyed by task/dependency key.
- `draftSimulationTimeline` matching CLI simulate output.

## Visual Design Rules

- Treat Workflow as a Pro macOS production surface, not a Web dashboard.
- Ordinary nodes and toolbar controls should be quiet: light border, subtle material, minimal fill.
- Use color only as semantic accent for success/failure/timeout/running/waiting, not as large decoration.
- Selected and running states may use a restrained outline, hairline progress, or breathing stroke.
- Avoid full-width saturated backgrounds and Bootstrap-like button blocks.
- Runtime animation must not resize cards, shift layout, or distract from the graph.

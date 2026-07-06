# Owner C: UI / Performance Workstream

Owner C owns how users understand and edit automation. The first UI goal is not a flashy graph; it is a clear, fast, read-only projection of workflows, runs, resources, dependencies, and evidence. Editing and drag interactions come only after reducer projection is stable.

## Owns

| Area | Files |
| --- | --- |
| Projection-facing UI models | `Sources/SparkleRecorder/AutomationViewProjection.swift`, `Sources/SparkleRecorder/Automation*Projection.swift`, `Sources/SparkleRecorder/AutomationProjectionFixture.swift`, `Sources/SparkleRecorder/AutomationOverviewModel.swift` |
| Automation entry view | `Sources/SparkleRecorder/AutomationMainView.swift`, `Sources/SparkleRecorder/AutomationMainContentView.swift` |
| Authoring inspector | `Sources/SparkleRecorder/AutomationInspectorView.swift`, `Sources/SparkleRecorder/AutomationWorkflowInspectorView.swift`, `Sources/SparkleRecorder/AutomationTaskInspectorView.swift`, `Sources/SparkleRecorder/AutomationTaskRunHistoryView.swift`, `Sources/SparkleRecorder/AutomationTaskRunRowView.swift`, `Sources/SparkleRecorder/AutomationTaskRunDisplay.swift`, `Sources/SparkleRecorder/AutomationDependencyInspectorView.swift`, `Sources/SparkleRecorder/AutomationMacroTaskLibraryView.swift` |
| FlowGraph drawing/editing | `Sources/SparkleRecorder/AutomationFlowGraphView.swift`, `Sources/SparkleRecorder/AutomationFlowGraphEdgeCanvas.swift`, `Sources/SparkleRecorder/AutomationFlowGraphEdgeListView.swift`, `Sources/SparkleRecorder/AutomationFlowGraphNodeView.swift` |
| Resource Timeline | `Sources/SparkleRecorder/AutomationResourceTimelineView.swift`, `Sources/SparkleRecorder/AutomationTimelineItemView.swift` |
| UI action boundary | `Sources/SparkleRecorder/AutomationViewIntent.swift`, `AutomationAction.manualStart`, `AutomationAction.moveTask`, workflow/task/dependency edit actions |
| Provider source UI | `Sources/SparkleRecorder/AutomationExternalSignalSourceView.swift`, `Sources/SparkleRecorder/AutomationSignalStore.swift`, `Sources/SparkleRecorder/AutomationManualApprovalPresenter.swift` |
| OCR region picker UI | `Sources/SparkleRecorder/AutomationOCRRegionPicker.swift`, `Sources/SparkleRecorder/AutomationOCRRegionPickerOverlay.swift`, `Sources/SparkleRecorder/Components/Editor/TextPickerOverlay.swift` |
| Workflow package UI | `Sources/SparkleRecorder/AutomationWorkflowPackagePresenter.swift` |
| UI tests/snapshots | `Tests/SparkleRecorderTests/AutomationViewProjectionTests.swift` |

## Hard Boundaries

- Do not call `Player`, scheduler, repository, or arbiter directly.
- Do not run graph searches or dependency resolution inside SwiftUI `body`.
- Do not create one View per dependency line when Canvas can draw the full line layer.
- Drag editing may only submit reducer-bound actions; transient drag state stays local until gesture end.
- Do not use internal channel numbers as primary user-facing names.

## Inputs From Other Owners

| From | Input |
| --- | --- |
| Owner A | Stable projection types, task/run statuses, dependency edge statuses, reducer action names |
| Owner B | Run history display fields, evidence availability, repository refresh states, condition provider hooks for manual approval/external signals |

## Outputs To Other Owners

| To | Output |
| --- | --- |
| Owner A | Projection gaps, user-facing status language, interaction actions needed for editing |
| Owner B | Evidence/run-history fields needed for UI, loading/error states needed from repository, product UI source for manual approval/external signal providers |

## Phase 1 Tasks

1. [x] Define read-only Automation overview from reducer projection.
2. [x] Design Resource Timeline labels around human resources: foreground input, screen capture, waiting, completed.
3. [x] Draw dependencies with a single Canvas layer.
4. [x] Show run evidence/outcome without opening Player internals.
5. [x] Add lightweight projection tests before full UI interaction tests.
6. [x] Defer drag-to-edit until reducer action contract is ready.

## Acceptance Criteria

- Main Automation view can render from a static projection fixture.
- UI body does not perform DAG traversal or file IO.
- Dependency lines are batched through Canvas.
- Timeline makes resource conflicts understandable without exposing internal lease machinery.
- User can distinguish scheduled, waiting, running, failed, cancelled, timed out, and blocked states.

## Interface Requests

- Resolved: Owner A/C projection contract is `AutomationViewProjection.overview(from:)`.
- Resolved: Owner A preserves precomputed node positions, edge statuses, Canvas endpoints, status counts, and user-facing status labels when the live reducer projection is wired in.
- Resolved: Task node manual run uses `AutomationViewIntent.startTask` -> `AutomationAction.manualStart`; runtime host dispatches it through the same reducer/effect path as scheduler starts.
- Resolved: Task node movement uses `AutomationAction.moveTask`; reducer persists `AutomationTask.graphPosition`, and projection reads it before falling back to automatic DAG layout.
- Resolved: Owner B exposes repository refresh states through `AutomationRepositoryRefreshClient`, with previous snapshots retained for loading/error display.
- Resolved: Owner B exposes evidence availability and run-history metadata through `AutomationTaskRun.evidenceID`, `AutomationTaskNodeProjection.hasEvidence`, `AutomationResourceTimelineItem.hasEvidence`, and run timing fields without loading screenshots eagerly.
- Resolved: Manual approval prompts feed B through `AutomationManualApprovalPresenter`, and external signal status feeds B through `AutomationSignalStore` / `AutomationExternalSignalSourceView`; SwiftUI still does not call live adapters directly.

## Accepted Contracts

- UI only dispatches `AutomationAction` or view-intent actions translated by the reducer layer.
- First milestone is read-only projection; node-position drag editing is limited to `AutomationAction.moveTask`.
- Read-only UI should use `AutomationViewProjection.overview(from:)`.
- `AutomationWorkflowProjection`, `AutomationTaskNodeProjection`, `AutomationDependencyEdgeProjection`, and `AutomationResourceTimelineItem` are the first stable projection types.
- UI should display run chains with `AutomationTaskRun.executionID` when it needs to group dependent runs.
- UI should consume `AutomationRepositoryRefreshState` for loading/error display rather than calling repository throws APIs.
- SwiftUI views consume `AutomationOverviewProjection`; graph layout, latest-run selection, edge status, and timeline lane mapping stay outside `body`.
- `AutomationMainView` may be initialized with `AutomationRepositorySnapshotClient` or `LiveAutomationRuntimeHost`; `AutomationOverviewModel` converts snapshots/runtime state to `AutomationViewProjection.overview(from:)`.
- Main window workspace navigation exposes Automation beside Library; the menu-bar popover remains focused on the lightweight macro library.
- FlowGraph task run buttons emit `AutomationViewIntent.startTask`, which maps to reducer-owned `.manualStart`.
- FlowGraph active-run cancel buttons emit reducer-owned `AutomationAction.cancelRun`; SwiftUI does not call Player cancellation directly.
- Task inspector active-run cancel buttons emit reducer-owned `AutomationAction.cancelRun`; SwiftUI does not call Player cancellation directly.
- FlowGraph node drag uses transient gesture offset, snaps on gesture end, then emits `AutomationAction.moveTask`.
- Dependency lines are drawn by a single Canvas layer from precomputed endpoints.
- Resource Timeline labels are user-facing (`Needs mouse and keyboard`, `Screen capture`, `Waiting`, `Completed`) and do not expose channel numbers.
- Task inspector run history consumes only per-task `AutomationTaskRun` values and displays timing, outcome reason, attempts, execution chain, upstream count, evidence availability, and duration metadata without loading screenshots or Player objects.
- Manual approval UI and external signal indicators feed provider/view-intent boundaries; SwiftUI views still do not call the condition evaluator directly.
- Product UI injects external signal, manual approval, and OCR region context provider clients into `LiveAutomationRuntimeHost`; views still consume projection/action boundaries rather than evaluator APIs.
- App runtime wiring provides frontmost window/content OCR context to Owner B so window/content `searchRegion` spaces can resolve at evaluation time.
- Workflow/task/dependency authoring emits reducer actions only: create workflow, add macro/condition task, connect/delete dependencies, rename workflow/task, update dependency trigger/delay, and save task schedule/condition/retry/timeout fields.
- External signal toggles are product source state only; condition evaluation consumes them through `AutomationExternalSignalClient`.
- Manual approval prompts are product source UI only; condition evaluation consumes them through `AutomationManualApprovalClient`.
- OCR region picking is product source UI: `AutomationOCRRegionPicker` may use the existing text picker overlay and macro surface metadata, but saving still goes through `AutomationAction.upsertTask`.
- Workflow package import/export is product UI over Owner B's `AutomationWorkflowPackage` codec; SwiftUI must not invent package fields or bypass reducer persistence. Missing local macro references may be surfaced as a product warning, but the package still does not carry macro payloads.
- Draft Preview may display fixed-count loop draft rows (`Loop`, repeat count, body step count), but loop expansion remains a core draft/import projection concern; SwiftUI must not implement loop execution or graph back-edges.

## Planning Log

- 2026-07-05: Phase 0 contract exists; UI work waits for Owner A projection shape.
- 2026-07-05: Owner C delivered the read-only projection fixture, Canvas FlowGraph, Resource Timeline, and projection tests. Live reducer wiring and drag editing remain deferred to the reducer/action contract.
- 2026-07-05: Owner B delivered repository refresh state values for C loading/error UI without direct file IO.
- 2026-07-05: Owner C wired `AutomationMainView` to reducer projections via snapshot refresh and added reducer-backed task node drag movement.
- 2026-07-05: Owner C added main-window Automation workspace wiring, live runtime projection refresh, and reducer-backed manual task start from FlowGraph nodes.
- 2026-07-05: Owner B exposed runtime-host provider injection for external signal/manual approval handoff without SwiftUI evaluator calls.
- 2026-07-05: Owner C first-pass authoring UI now creates workflows/tasks/dependencies, edits schedule/condition parameters, and uses app provider views for external signals/manual approvals without direct adapter calls.
- 2026-07-05: Owner C added OCR Pick Text Region authoring and `.sparkrec_workflow` import/export product UI without changing Owner B package semantics.
- 2026-07-05: OCR Draw Region authoring added for arbitrary rectangle `searchRegion` bounds without depending on live OCR detection results.
- 2026-07-05: Owner C connected active-run cancellation in FlowGraph/task inspector and added missing-local-macro warnings during workflow package import without changing package semantics.
- 2026-07-05: Owner C added all-workflow package export from the workflow list header while keeping selected-workflow export in the inspector.
- 2026-07-05: Owner C added OCR region preview/micro-editing plus display/window/content context hints, and added selected/all workflow package sharing through macOS share sheet.
- 2026-07-05: Owner C added task inspector run history/detail rows for outcome reason, lifecycle timing, attempts, execution chain, upstream count, evidence availability, and duration metadata without crossing into Player/evidence payload loading.
- 2026-07-06: Owner A/B exposed durable condition diagnostics with optional sample artifact refs. Owner C may render `AutomationTaskRun.conditionEvidence` and route artifact preview/open/reveal through `AutomationConditionEvidenceArtifactPresenter`, but SwiftUI must not call ScreenCapture, OCR, evaluator clients, image providers, or ad-hoc artifact path builders for diagnostics. Failure/rejected condition runs can now still carry explanatory evidence; UI should show the payload when present and only label diagnostics missing when `conditionEvidence == nil`.
- 2026-07-07: Draft Preview projection now labels fixed-count loop draft rows and summarizes repeat/body counts. It still consumes validation/simulation/import projections only; product loop authoring UI and run-evidence presentation remain future work.

## Handoff Checklist

- [x] Static projection fixture renders.
- [x] FlowGraph line layer uses Canvas.
- [x] Resource Timeline labels reviewed for user clarity.
- [x] No direct Player/Scheduler/Repository calls in SwiftUI views.
- [x] Repository refresh state boundary identified for live loading/error UI.
- [x] Automation UI can refresh reducer projection through `AutomationRepositorySnapshotClient`.
- [x] Automation UI can read live runtime reducer state through `LiveAutomationRuntimeHost`.
- [x] FlowGraph node run emits `AutomationViewIntent.startTask` / `.manualStart`.
- [x] FlowGraph node cancel emits `AutomationAction.cancelRun`.
- [x] Task inspector cancel emits `AutomationAction.cancelRun` for the latest active task run.
- [x] Task inspector shows run history/outcome/evidence metadata from `AutomationTaskRun` without opening Player internals.
- [x] FlowGraph node drag emits `AutomationAction.moveTask` after grid snap.
- [x] FlowGraph node linking emits `upsertDependency`; inspector delete emits `deleteDependency`.
- [x] External signal source UI feeds provider state, not reducer state.
- [x] Task inspector edits manual/once/repeating schedule, retry attempts, task timeout, and condition timeout/polling.
- [x] Condition authoring covers manual approval, external signal, screen text, and previous outcome sources.
- [x] Manual approval prompts feed provider clients, not evaluator APIs.
- [x] OCR condition editing preserves existing region bounds and writes `AutomationOCRSearchRegionSpace`.
- [x] OCR region picker authoring writes new `searchRegion` bounds from a screen/window text selection.
- [x] OCR Draw Region authoring writes arbitrary rectangle bounds through `AutomationOCRSearchRegionSelection`.
- [x] OCR region editor previews and micro-edits existing `searchRegion` bounds.
- [x] OCR region editor explains multi-display and window/content context availability.
- [x] Workflow package import/export uses Owner B codec and reducer edit actions.
- [x] Workflow list header can export all workflows as one `.sparkrec_workflow` package.
- [x] Workflow package sharing uses the same Owner B codec and does not add macro payloads.
- [x] Workflow package import warns when referenced macro IDs are absent from the local macro library.
- [x] Performance risks documented before adding drag interactions.

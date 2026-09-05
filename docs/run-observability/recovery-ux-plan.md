# Run Recovery UX Contract

Updated: 2026-07-18

## User Journey

The Runs surface must let a user move through four questions without leaving the context of the selected execution:

1. What happened?
2. Is the attached evidence actually readable from disk?
3. What is the safest next action?
4. Did that action start, succeed, or fail?

## Evidence Health Contract

- `evidenceID` identifies the report produced by playback. It does not prove that report, manifest, or screenshot persistence succeeded.
- Owner B returns a structured persistence result after canonical per-run evidence writing.
- Owner A stores that result on `AutomationTaskRun` and checkpoints it before the terminal outcome is processed.
- Owner C derives `available`, `partial`, `failed`, `pruned`, and `not recorded` presentation from persisted state. It must not label an ID alone as available evidence.
- A missing screenshot with a readable report is partial evidence, not a total failure.
- The per-run manifest is the canonical commit marker. Failure to update legacy latest aliases does not invalidate committed per-run evidence.
- Old run records without a persistence result remain `unknown`; UI may attempt an app-edge load but must not claim availability before that load succeeds.

## Action Contract

- Evidence actions open the exact run/evidence ID. A failed event index is carried into the evidence surface as diagnostic focus.
- Cancel execution dispatches cancellation for every active run in the selected execution and reports partial command failures.
- Retry execution means starting the workflow again from every enabled root task under one new execution ID. It never means silently starting only the failed task.
- Permission actions open the matching macOS settings pane.
- Timeout, resource policy, missing macro, target application, and cancellation review actions open the matching workflow task.
- Storage repair opens Run History settings and retains the persistence error text.
- `Open Workflow` remains a secondary action where workflow editing is meaningful; it is not the universal primary action.

## Feedback Contract

- Destructive cancellation requires confirmation.
- Commands expose in-progress state, disable duplicate submission, and show localized success/failure feedback in the selected execution detail.
- After cancel or retry dispatch, Runs refreshes from runtime state rather than synthesizing an optimistic execution.

## Acceptance

- Evidence save tests cover complete success, report-only partial success, and complete failure.
- Reducer/repository tests prove evidence health survives checkpoint round trips.
- Run Center tests cover command selection for every semantic recommended action.
- Runtime tests prove workflow retry creates one execution ID across all enabled root tasks.
- Cancellation tests prove every active run in one execution is targeted and terminal runs are ignored.
- English and Simplified Chinese catalogs cover all new status, command, confirmation, and feedback strings.

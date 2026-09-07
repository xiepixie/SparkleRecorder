# Run Observability And Recovery

Updated: 2026-07-18

## Product Outcome

Users should be able to answer five questions without opening Console or reading JSON:

1. Did the automatic run trigger when expected?
2. Is it running, waiting, or already finished?
3. Which workflow, task, attempt, or macro event needs attention?
4. What evidence supports the reported result?
5. Should the user retry, fix permissions, restore a macro, inspect the target app, or edit the automation?

The primary Library entry is **Runs**. It opens an execution-oriented surface rather than a task-oriented log viewer. Workflow remains the advanced authoring and graph surface.

## Current State

- Task-run checkpoints use the append-only `automation-runs.jsonl` journal. Legacy embedded `automations.json` history remains readable and migrates lazily on the next history mutation. Both forms preserve run ID, `executionID`, task identity, attempts, outcome, timing, condition evidence, branch evidence, optional interruption context, and optional macro evidence binding.
- Macro packages persist per-run reports and screenshots under `Macros/<macro-id>.sparkrec/runs/<evidence-id>/`.
- Library exposes only the latest macro report. Workflow exposes task-local history, capped visually to five rows.
- Planned/waiting/queued/running checkpoints, persistence failures, crash reconciliation, evidence persistence health, and run/evidence retention are implemented. Canonical report/manifest/screenshot health is checkpointed before the terminal outcome; legacy records without health remain explicitly unverified until loaded.
- Semantic recording retention is separate and must not be presented as general run-history cleanup.

## Accepted UX Contract

### Runs Entry

- Library window exposes a visible **Runs** command alongside Review and Run automatically.
- The command remains available with zero macros because repository load failures and historical runs are still meaningful.
- The sheet refreshes from the live runtime when available and falls back to the repository snapshot.

### Information Architecture

- Status navigation combines total, needs-attention, running, and succeeded counts with the matching filters so the same concepts are not repeated in two stacked controls.
- Execution list: workflow name, full activity date/time, status, failure task when relevant, evidence availability, task progress, and attempt count.
- Detail pane prioritizes plain-language failure cause and the recommended next action before dates, counts, evidence availability, run ID, and the step/attempt timeline.
- Empty state distinguishes no history from a filter with no matches.
- Load failure keeps the previous successful snapshot visible and labels it as stale.
- The root surface fills tall host windows and stays top-aligned; 820x580 remains the minimum supported layout.

### Failure Focus

The first actionable failure is selected by task execution order, then attempt. The projection must preserve the original `AutomationOutcome`; UI text must not infer success from missing error text.

Recommended actions are semantic values owned by Core:

- grant permission;
- restore missing macro;
- inspect target application/window;
- inspect failed macro event and evidence;
- adjust timeout or resource policy;
- retry execution;
- review cancellation;
- wait or cancel an active execution.

UI maps those values to localized copy and app-edge commands. Core does not import SwiftUI or access files.

## Architecture Contract

- Owner A owns `AutomationRunCenterProjection`, execution grouping, status precedence, failure focus, and recommended action semantics.
- Owner B owns live/repository snapshot loading, persistence health, crash reconciliation, evidence inventory, and retention application.
- Owner C owns Library entry, run-center layout, filters, selection, stale/error states, and evidence navigation.
- SwiftUI receives projections and dispatches commands. It does not read `automations.json`, enumerate macro packages, or calculate execution outcomes.
- Existing task-run detail and evidence presenters may be reused after the execution and run identity has been selected by Core.

## Delivery Slices

1. Execution projection and Library run center using durable run checkpoints. Implemented in the current worktree.
2. Durable queued/started checkpoints, persistence-failure feedback, startup interruption reconciliation, and report/screenshot/manifest evidence-write health. Implemented.
3. Unified run/evidence retention planner, cleanup preview, protected recent evidence, two-phase cleanup, a daily eligibility limit, and hourly eligibility rechecks while the app remains open. Whole-store usage is shown by reports, screenshots, condition evidence, manifests/other evidence, and history index. Orphan sweep remains open.
4. Context-specific recovery commands are implemented for exact evidence review, execution cancellation, workflow retry, permissions, Run History settings, and focused Workflow editing. Default failure notifications and an exportable privacy-filtered support bundle remain future work.

The Runs surface must not claim that an absent run proves the scheduler never attempted execution. Persistence failure stops later live effects and remains visible in runtime state instead of silently continuing an unaudited automation.

## Verification

- Pure tests cover grouping, status precedence, failure focus, action recommendation, sorting, and filters.
- Model tests cover live-state preference, repository fallback, stale snapshot preservation, and refresh failure.
- UI verification covers populated, empty, filtered-empty, loading, stale, and narrow layouts.
- Persistence and retention slices require fake repositories/filesystems and injected clocks; tests never touch Application Support.

## Retention Defaults

- Successful run evidence: 30 days.
- Run evidence needing attention: 90 days. This includes failures, interruptions, timeouts, permission denial, resource conflicts, missing macros, and rejected runs.
- Lightweight run-history metadata: 365 days.
- Lightweight run-history metadata targets at most 10,000 records by default, with the oldest eligible terminal records removed first. Active/protected records can temporarily keep the total above that target.
- Zero/"Never" disables the selected age limit; the metadata capacity target remains active.
- Active runs, the latest workflow execution, the latest run needing attention, and the latest evidence for each macro are protected.
- Cleanup first persists `pendingDeletion`, then deletes only validated artifact directories, and finally persists `pruned`. A failed deletion is retried on the next preview or daily check.
- Automatic cleanup is enabled by default, can be disabled without changing retention values, and exposes the last result plus the next eligible check in Settings.
- Storage usage uses allocated file size. Settings shows whole-store usage and its report/screenshot breakdown; Run Center shows the selected execution's evidence size.
- A terminal execution exposes destructive secondary commands, never primary recovery actions: delete ending screenshots while retaining reports, delete all evidence while retaining explanatory run metadata, or delete the run records and their evidence. Active executions cannot be deleted.
- Performance and migration contracts are recorded in [performance-plan.md](performance-plan.md).
- Evidence truthfulness and recovery command semantics are recorded in [recovery-ux-plan.md](recovery-ux-plan.md).

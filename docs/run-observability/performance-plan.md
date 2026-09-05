# Run History Performance Optimization

Updated: 2026-07-18

## Baseline Before This Slice

- Local sample: 30 run records, 122,968-byte `automations.json`, 105 evidence files, and about 102 MB total App Support data.
- Runtime scheduler ticked every 30 seconds and scanned archived run history once per scheduled task.
- Runs UI polled every two seconds and rebuilt its full projection on `MainActor` even when state was unchanged.
- Each durable checkpoint decoded and atomically rewrote the complete persistence document.

## Implemented State

1. `automations.json` remains the workflow document and legacy run-history migration source.
2. `automation-runs.jsonl` becomes the append-only checkpoint journal. A checkpoint appends one compact versioned entry and synchronizes it before a later live effect starts.
3. The repository actor keeps a run-ID index in memory. Journal replay is last-write-wins, tolerates only a torn final line, and periodic compaction atomically rewrites one latest entry per retained run.
4. Existing installations migrate lazily on the first run-history mutation. Old JSON remains readable before migration; migration clears embedded history only after the journal is durably written.
5. Retention transitions compact the journal atomically and keep the existing two-phase artifact deletion contract.
6. Runtime snapshots expose a monotonic revision. Runs UI skips projection and visible loading-state updates when the revision is unchanged, and builds changed projections off `MainActor`.
7. Scheduler occurrence lookup builds one `(workflowID, taskID) -> represented start times` index per tick instead of rescanning all runs for every scheduled task.
8. Metadata retention has both age and a default 10,000-record count limit. Protected/active evidence remains protected; oldest unprotected terminal metadata is removed first.
9. The app performs the retention cleanup once on startup when eligible and rechecks eligibility hourly while it remains open; the pure planner still limits actual cleanup to once per day.
10. Successful OCR/template locator diagnostics use debug logging; failures and lifecycle checkpoints retain their existing visibility.

## Risks And Recovery

- A malformed non-final journal line is a repository error; silently skipping durable history is forbidden.
- A torn final line is ignored on replay because the preceding synchronized entries remain valid.
- Compaction uses atomic replacement. Failure leaves the previous journal and in-memory run state unchanged.
- Journal migration and compaction are covered with scratch-directory tests; tests never touch Application Support.
- Runtime revision is an optimization hint, not persisted state and not part of reducer semantics.

## Acceptance Checks

- Appending a checkpoint after migration does not rewrite `automations.json`.
- Legacy embedded history migrates without losing workflows, run fields, attempts, or evidence bindings.
- Replaying repeated checkpoint entries returns one latest run per run ID in stable first-seen order.
- Compaction bounds journal entry amplification while preserving latest values.
- An unchanged two-second Runs poll does not replace the projection or toggle visible loading state.
- A changed runtime revision rebuilds projection outside `MainActor` and updates selection deterministically.
- Scheduler tests prove one pre-indexed represented-start lookup across many tasks.
- Retention tests prove the metadata count cap while preserving active/latest/failure/evidence protections.

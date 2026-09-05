# Run Observability Acceptance Checklist

Updated: 2026-07-18

## Slice 1: Runs UX

- [x] Library window has a visible Runs entry.
- [x] Runs are grouped by `executionID`, not presented as unrelated task rows.
- [x] Running, attention, succeeded, and total counts are accurate.
- [x] All, Needs attention, Running, and Succeeded filters are deterministic.
- [x] The first actionable failure identifies workflow, task, attempt, and macro event when available.
- [x] Detail view presents one concrete recommended next action.
- [x] Evidence availability is shown without direct file access from SwiftUI.
- [x] Loading, empty, filtered-empty, refresh-failed, and stale states are distinct.
- [x] Narrow layouts do not overlap or truncate primary status text.
- [x] Tall windows keep the run center top-aligned without an empty header gap.
- [x] Status counts act as filters instead of duplicating a second segmented control.
- [x] Failure cause and recommended action appear before technical run metadata.
- [x] Run-center UI keys and known internal playback messages have English and Simplified Chinese coverage.

## Slice 2: Runtime Durability

- [x] Queued and started checkpoints are durable before live side effects begin.
- [x] Persistence failure becomes reducer state and visible UI feedback.
- [x] Repository writes are idempotent by run ID.
- [x] Startup reconciles non-terminal persisted runs as interrupted.
- [x] Cleanup outcome is attached to the retained run record.
- [x] Evidence persistence health is checkpointed before the terminal run and distinguishes complete, partial, failed, and legacy-unverified evidence.
- [x] Recommended actions map to exact evidence review, execution-wide cancellation, workflow retry, permission settings, Run History settings, or focused Workflow editing.
- [x] Cancellation requires confirmation and command execution exposes progress, refresh, and localized feedback.

## Slice 3: Retention

- [x] Run metadata, macro run evidence, and condition evidence share one cleanup preview.
- [x] Active, latest workflow, latest failure, and latest macro evidence are protected.
- [x] Pruned artifacts retain a lightweight explanatory record.
- [x] Cleanup uses an injected evaluation date and never waits on wall-clock time in tests.
- [x] Settings exposes separate success, failure, and metadata policies plus a size-estimated cleanup confirmation.
- [x] Automatic cleanup runs at most daily and retries interrupted two-phase deletions.
- [x] Long-running app sessions recheck cleanup eligibility without requiring a restart.
- [x] Metadata count is bounded independently of age while protected runs remain intact.
- [x] Settings shows total allocated run storage with report, screenshot, condition-evidence, other-evidence, and history-index breakdowns.
- [x] Automatic cleanup can be disabled and exposes its last result and next eligible check.
- [x] A terminal execution can delete screenshots only, all evidence, or run records plus evidence after a size-aware confirmation.
- [x] Screenshot-only deletion changes durable evidence health to report-only without hiding the report.
- [x] Active execution deletion is rejected by the persistence boundary even if UI validation is bypassed.
- [ ] Orphan artifacts without retained run metadata are inventoried and swept.

## Slice 4: Performance

- [x] Run checkpoints append one synchronized versioned journal entry instead of rewriting the workflow document.
- [x] Legacy embedded history migrates lazily and torn final journal entries recover safely.
- [x] Retention and journal amplification trigger atomic compaction.
- [x] Unchanged Runs polling skips projection work and visible loading updates.
- [x] Changed Runs projections are built outside `MainActor`.
- [x] Scheduler represented occurrences are indexed once per tick.
- [x] Ten-thousand-record scheduler and run-center projection fixtures have direct tests.

## Gates

- [x] Focused Swift Testing passes (91 cross-layer tests).
- [x] Full Swift Testing passes (720 tests in 88 suites).
- [x] Swift 6 build passes.
- [x] `git diff --check` passes.
- [x] Documentation status matches implemented slices.

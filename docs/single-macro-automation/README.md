# Single Macro Automation

Updated: 2026-07-15

## Product Goal

The primary automation path starts from one saved macro in Library. A user should not need to understand Workflow graphs to run a recorded ten-minute routine on a schedule.

The complete path is:

1. Choose **Run automatically** on a macro.
2. Choose daily, weekly, interval, or one-time timing.
3. Review the exact next run time and target application behavior.
4. Run a five-second preview without creating a schedule.
5. Save the schedule and remain in Library.
6. Inspect the latest result and ending screenshot from that macro in Library.

Library cards show whether automatic running is configured and the next occurrence. Reopening the sheet edits the existing values instead of starting from defaults. Historical duplicate one-macro schedules are disclosed and merged on save.

Workflow remains the runtime and persistence implementation for this first pass. It is not the authoring surface for a single scheduled macro.

## Scheduling Contract

- **Daily** runs at a selected local wall-clock time.
- **Weekly** runs on a selected local weekday and wall-clock time.
- **Interval** starts at a selected date/time and repeats by the chosen interval.
- **Once** runs at one selected date/time.
- The schedule sheet always shows the next occurrence before save.
- SparkleRecorder must be running for the schedule to fire. This first pass does not wake a logged-out Mac or launch the scheduler through a daemon.
- Missed occurrences use **latest only** semantics. When SparkleRecorder becomes available, at most the most recent due occurrence starts; older missed days never queue as catch-up runs.
- Daily and weekly anchors are normalized to the same next occurrence shown in the sheet. Choosing an earlier wall-clock time today therefore starts tomorrow/next week instead of immediately treating the new plan as missed.

## Preview Contract

- Preview counts down from five seconds and can be cancelled before playback starts.
- Preview runs the complete saved macro once through an injected app-edge action.
- Preview does not persist a Workflow or alter the future schedule.
- Preview uses the same target-application preparation and evidence behavior as a scheduled run.

## Target Application Lifecycle

- A bound application can be opened when it is not running, then its bound window is awaited before input begins.
- Cleanup policy is task-scoped and backward compatible. Existing workflows keep applications open.
- New single-macro schedules default to **quit if this run launched it**.
- SparkleRecorder must never quit a target application that was already running before preparation.
- Target preparation returns a session containing only bundle identifiers launched by that run. Cleanup consumes that session after evidence capture.
- Each scheduled occurrence uses a task-level playback loop override of one. Library loop controls, including infinite playback, cannot prevent an automatic run from reaching cleanup.

## Evidence Contract

- A terminal run has a report. A successful scheduled or preview run also attempts one ending screenshot of the bound target window.
- Screenshot failure does not change a successful playback into a failed run; the report remains available and the UI states that no image was captured.
- Success and failure reports use the existing per-run evidence package and bind the run ID as `evidenceID`.
- Library provides a latest-run evidence surface with status, time, duration, screenshot preview, and open/reveal actions.
- Advanced Workflow screenshot actions remain a separate future authoring capability.

## Ownership

- Owner A: task cleanup/evidence policy persistence, player request handoff, successful run `evidenceID` binding, pure compatibility tests.
- Owner B: application preparation session, safe cleanup, success capture/persistence, preview app-edge execution, fake-client tests.
- Owner C: schedule decision flow, countdown state, next-run explanation, Library evidence entry and presentation.

## Acceptance Checks

- [x] Daily timing resolves through the existing schedule occurrence engine from the selected local anchor.
- [x] Weekly timing resolves to the next selected weekday and local time.
- [x] Interval and one-time modes show the exact next run.
- [x] Five-second preview can be cancelled and creates no Workflow.
- [x] A missing bound application opens and playback waits for its window.
- [x] Only an application launched by this run is eligible for cleanup.
- [x] Evidence capture happens before cleanup.
- [x] Successful and failed reports are discoverable from Library.
- [x] Saving returns to Library and confirms the next run time.
- [x] Library cards expose configured/paused state and refresh the next-run label while visible.
- [x] Reopening restores the existing schedule and application lifecycle choices.
- [x] Duplicate one-macro schedules are merged on save and all are removed when automatic running is turned off.
- [x] Scheduled and preview runs execute the complete macro exactly once even if Library playback loops differ.
- [x] Missed daily/weekly/interval occurrences never accumulate into a catch-up queue.
- [x] The displayed next daily/weekly occurrence is the exact anchor persisted on save.
- [ ] Targeted tests, full Swift Testing, Swift 6 build, and `git diff --check` pass, except documented pre-existing failures.

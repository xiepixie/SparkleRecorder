# Library Quick Schedule UX

Updated: 2026-07-14

## Current Friction

Scheduling a recorded macro currently requires the user to leave Library, create or select a workflow, add the macro as a task, select that task, open the Run inspector, configure its schedule, and save the task. The Library-level Workflow shortcut does not preserve which recording the user intended to automate.

The underlying contract remains task-scoped: `SavedMacro` is a reusable recording, `AutomationTask` is its workflow instance, and `AutomationSchedule` belongs to the task. This polish must not write workflow state back into `SavedMacro` or introduce a second scheduler path.

## Accepted Product Flow

1. A Library recording card exposes a first-level Schedule action beside Play and Edit.
2. Schedule opens a compact sheet already bound to that macro.
3. The sheet defaults to Every Day and asks for a time; Once and Custom Interval are secondary modes.
   When the macro has a bound application, it also offers a target-app policy and defaults new quick schedules to Open if needed.
4. The preview uses existing Automation schedule occurrence semantics.
5. Confirming creates one workflow with one enabled macro task through `AutomationAction.upsertWorkflow`.
6. After persistence succeeds, the app stays in Library and reports the next run.
7. The sheet states that scheduled runs require SparkleRecorder to remain open. It does not imply OS wake, login-item, or daemon support.

## Daily Macro Path

For the primary single-recording use case, Workflow is an implementation detail rather than a user concept:

- Quick Schedule defaults to Every Day and asks only for a time.
- The saved macro name becomes the internal workflow name; the sheet does not ask users to name a workflow.
- Once and Custom Interval remain available as secondary schedule modes.
- A successful save stays in Library and reports the next run instead of navigating into Workflow authoring.
- Long recordings are scheduled as one macro task and play with their recorded timing; users do not need to split a ten-minute claim/check-in flow into nodes.
- Bound recordings continue to default to Open if needed.

Multi-selection keeps the Sequence builder path. Its initial execution order must follow the visible Library order instead of `Set` iteration order.

## Workflow Schedule Surface

The Resource Timeline schedule editor remains the primary lightweight schedule surface. It must:

- stay visible for the workflow start task even when that task is currently manual;
- identify the task whose schedule is being edited;
- expose the task Enabled switch next to schedule controls so activation is not split across Inspector tabs;
- submit only accepted `AutomationAction.upsertTask` edits;
- keep detailed task policies and run history in Inspector;
- disclose that the current scheduler runs while SparkleRecorder is open.

## Boundaries

- No workflow-level `enabled` or schedule persistence field is added.
- Target application behavior is task-scoped. Existing tasks decode as Activate if running; new Quick Schedule tasks explicitly use Open if needed unless the user changes it.
- No SwiftUI view calls Player, scheduler, repository, or file IO directly.
- Library creation dispatches an accepted reducer action through `LiveAutomationRuntimeHost`.
- Scheduling does not promise app wake or background launch.
- Existing task schedules and repository JSON remain compatible.

## Acceptance Checks

- A single macro can become a once or repeating scheduled workflow from Library in one sheet.
- The created task references the selected macro, is enabled, requests foreground input, and carries the chosen schedule.
- A bound macro defaults to Open if needed; launch failure or a missing window rejects the run before input playback.
- Invalid empty names and repeat counts below one cannot be submitted.
- Save failures remain visible beside the sheet action.
- Successful creation stays in Library and reports the next scheduled occurrence.
- Multi-selected sequence order matches Library display order.
- Timeline schedule editing targets the existing scheduled task before falling back to the workflow root task.
- The Timeline activation switch updates only the target task through `AutomationAction.upsertTask`.
- Focused pure tests cover quick-workflow construction and schedule previews.

## Implementation Evidence

Implemented in the current worktree on 2026-07-14.

- `AutomationQuickScheduleDraft` builds the single-task workflow and previews occurrences through core schedule semantics.
- Library cards, compact rows, and the current-macro action strip open `AutomationQuickScheduleSheet`.
- Successful creation dispatches `AutomationAction.upsertWorkflow`, stays in Library, and reports the next occurrence through the existing status overlay.
- Multi-selection sequence order now follows the visible Library order; the sequence builder defaults to a once schedule one hour ahead and uses non-misleading Create Workflow copy.
- The Timeline editor now supports Off/Once/Repeat, resolves an existing scheduled task before falling back to the workflow root, exposes the task Enabled switch, and states the current App-open runtime requirement.
- `AutomationQuickScheduleTests`, `AutomationScheduleOccurrenceTests`, and `AutomationReducerTests` pass together (42 tests).
- The existing idle Workflow product-evidence renderer was run at 1680 px to verify the Timeline controls do not overlap the graph, timeline, or inspector.
- Target application policy now round-trips through workflow JSON and AI draft export/import. The live adapter launches by bundle identifier, waits up to 10 seconds for the recorded window, and returns a rejected outcome before Player starts if preparation fails. Focused reducer/Owner B/draft/quick-schedule/target-app suites pass together (111 tests).

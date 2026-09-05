# Automation Management Page

Updated: 2026-07-18

## Problem

The first catalog pass rendered every workflow as one wide row. It exposed projection fields but did not support the user's management loop: select an automation, understand what it does, edit or pause it, inspect recent executions, open evidence or logs, and delete it safely. Icon-only run/edit controls and a create menu were insufficient for primary commands.

## Target Interaction

The Automation workspace uses a native master-detail layout:

- Master list: compact automation identity, tier, enabled state, next run, and latest execution status.
- Detail: selected automation summary, labeled primary commands, schedule/composition state, recent executions, evidence health, and destructive actions.
- Create is one labeled primary menu with `From Macro Library` and `Advanced Workflow` choices.
- Edit routes by tier: Quick Schedule, Quick Sequence, or Workflow Editor.
- Delete always confirms with the automation name and explains that macro assets and saved run history remain.
- Recent executions are grouped by `executionID`, not by internal task node. Selecting an execution opens run details; evidence opens from that execution context.
- Global Runs remains available for cross-automation investigation. Automation detail shows a filtered operational view first.

## User Vocabulary

- `Automation`: the managed user goal.
- `Macro`: reusable recorded input used by an automation.
- `Sequence`: a linear automation editing tier.
- `Workflow Editor`: advanced editing mode.
- `Run`: one execution of an automation.
- `Evidence`: screenshots/reports bound to a run.
- `Diagnostics`: technical condition, failure, and persistence details inside run detail. The primary page does not use `log` as an unexplained generic destination.

## Acceptance

- [x] Selection is stable across projection refresh and repaired after deletion.
- [x] Primary Run and Edit commands have visible labels.
- [x] Pause/Resume updates Core-projected entry tasks through reducer actions.
- [x] Delete uses a named confirmation and reducer-owned workflow deletion.
- [x] Detail shows schedule, composition, current status, recent execution count, and evidence readiness.
- [x] Recent executions are workflow-filtered `AutomationExecutionProjection` values.
- [x] A run detail exposes steps/attempts, failure focus, user-facing diagnostics, and evidence entry.
- [x] Empty automation and empty run-history states have clear next actions.
- [x] English and Simplified Chinese strings are complete.
- [x] A 1440 x 900 product screenshot confirms the master-detail hierarchy without clipping or overlap.
- [x] Projection, interaction, localization, full tests, Swift 6, and release checks pass.

## Boundaries

- SwiftUI receives `AutomationCatalogProjection` and `AutomationRunCenterProjection`; it does not group raw runs or traverse dependency graphs.
- Evidence file loading remains in `AutomationTaskRunEvidencePresenter`.
- Delete/pause/run actions stay on accepted `AutomationAction` reducer paths.
- Macro files and run-history retention are not deleted when deleting an automation.

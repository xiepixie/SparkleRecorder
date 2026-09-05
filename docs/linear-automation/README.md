# Quick Linear Automation

Updated: 2026-07-18

## Product Boundary

SparkleRecorder exposes three authoring levels:

1. Quick Schedule: one macro and one schedule.
2. Quick Sequence: a small ordered list of macros with simple waits or OCR text gates.
3. Workflow: branches, joins, parallel resources, reusable visual assets, advanced retry policy, and graph editing.

Quick Sequence is not a second runtime. It compiles into an ordinary `AutomationWorkflow` and uses the existing reducer, scheduler, Player, condition evaluator, evidence, and Runs center.

## User Contract

- A card or multi-selection can enter Quick Sequence directly from Library.
- The sequence editor starts with the selected macros and can add any saved Library macro.
- Start preparation opens the bound application, waits a bounded settling period after its window appears, and can insert an existing login/navigation macro as the first step.
- Steps are explicitly ordered and can be moved or removed without entering a graph.
- Each link supports exactly one simple continuation: continue immediately after success, wait a fixed duration after success, or wait until screen text appears with a timeout.
- Screen-text waits reuse the existing OCR text picker and rectangle picker. Picking text fills the recognized text and watched region; users may still edit the text, choose contains/exact matching, redraw the region, or intentionally search the whole target screen.
- Timing supports manual, daily, weekly, once, and interval schedules and shows the exact next occurrence.
- Each macro plays one complete pass, launches its bound application when needed, and uses latest-only missed-run semantics.
- Target applications remain open between steps. Workflow-session-wide final cleanup is future work; the UI must not promise it until the runtime owns a shared launch session across task runs.
- Saving keeps the user in Library and reports the next run. `Advanced edit` saves the same workflow and then opens it in Workflow.

## Architecture

- Pure draft values, editor mutations, save intents, and document generation are testable app-target values; the output is `AutomationWorkflowDraftDocument`. Their physical extraction from the SwiftUI sheet file remains cleanup work.
- SwiftUI owns row ordering and accepted user inputs only.
- `LibraryMainView` compiles the document through `AutomationWorkflowDraftImporter`, dispatches `.upsertWorkflow`, and optionally navigates to Workflow.
- OCR gates use the existing `ocrText` condition, `AutomationOCRRegionPicker`, and `AutomationScreenRegionPicker`. A picked region is stored as a draft visual asset and referenced by the condition, preserving its display/window/content coordinate space through import; no parallel OCR evaluator exists in Quick Sequence.

## Acceptance

- [x] One or multiple selected macros open as an ordered sequence.
- [x] Macro order, add, and remove work without Workflow.
- [x] Immediate, delay, and OCR text continuations compile to the expected tasks and dependencies.
- [x] OCR text picking and freeform region drawing reuse the existing authoring overlays, and region references round-trip through draft visual assets.
- [x] Manual/daily/weekly/once/interval schedule attaches only to the first macro.
- [x] Saving stays in Library; advanced editing opens Workflow only when requested.
- [x] A cancellable five-second action saves and manually starts the same compiled sequence.
- [x] Invalid names, empty sequences, past one-time dates, invalid intervals, delays, OCR text, and OCR timeouts block saving with localized feedback.
- [x] English and Simplified Chinese catalogs cover the complete surface.
- [x] Focused tests, full Swift Testing suite (705 tests), Swift 6 build, localization catalog validation, and whitespace checks pass.
- [x] Release install and launch verification pass.
- [ ] Move the pure sequence draft/editor/save-intent values into a non-SwiftUI source file; behavior is directly tested, so this is maintainability cleanup rather than a release blocker.

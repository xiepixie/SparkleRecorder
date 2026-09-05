# Automation Startup Readiness

Updated: 2026-07-19

## Problem

Opening an application does not mean its target page is ready. A newly launched app may still be restoring a session, showing a login screen, loading content, or waiting for navigation. Starting the first recorded input as soon as a matching window appears makes scheduled runs fragile and gives users no useful distinction between launch failure, preparation failure, and the intended task.

## User Model

A simple automation has three phases:

1. **Open**: launch or activate the application and find its bound window.
2. **Prepare**: allow the page to settle, then run optional login/navigation macros and wait for observable OCR text between steps.
3. **Do the task**: run the user's actual macro steps, capture the result, and apply the configured application cleanup.

Quick Schedule exposes a bounded `Wait after opening` control for a single macro. Quick Sequence exposes the same start-readiness control and explains that login/navigation macros belong at the start of the ordered step list. Existing OCR continuations remain the preferred observable readiness gate after a preparation macro. Branching authentication, CAPTCHA/manual approval, alternative pages, and recovery paths remain Workflow concerns.

## Contract

- `AutomationTask.targetApplicationReadyDelay` is a persisted duration from 0 through 60 seconds.
- Missing values decode as 0 so existing workflows retain their behavior.
- `AutomationPlayerStartRequest` carries the normalized delay to the live adapter.
- The live adapter waits only after target application preparation succeeds and before posting macro input.
- Cancellation during readiness waiting cleans up the exact application process launched by that run and does not start playback.
- Preview and scheduled execution use the same player request contract.

## Boundaries

- Owner A owns the persisted task field and normalization.
- Owner B owns request propagation, cancellable waiting, cleanup, and runtime tests.
- Owner C owns the Quick Schedule and Quick Sequence controls, explanatory copy, and document round-trip tests.
- OCR readiness continues to use existing condition tasks and the existing OCR evaluator. This feature does not create another screen-recognition path.

## Acceptance

- [x] Old task JSON decodes to zero readiness delay.
- [x] Draft export/import preserves readiness delay.
- [x] Quick Schedule creates and restores the selected delay.
- [x] Quick Sequence applies the delay only to the first macro and restores it.
- [x] Live playback waits after application preparation and honors cancellation cleanup.
- [x] UI separates fixed startup waiting, ordered preparation macros, observable OCR readiness, and advanced branching.
- [x] English and Simplified Chinese strings are complete.
- [x] A 900 x 720 product screenshot confirms the preparation, steps, and timing hierarchy without clipping.
- [x] Focused tests, full tests, Swift 6, screenshot, and Release install pass.

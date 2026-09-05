# Automation Library

Updated: 2026-07-18

## Product Model

SparkleRecorder has four user-facing objects:

1. Macro Library: reusable recorded actions.
2. Automations: deployed user goals that may run one macro, a linear sequence, or an advanced workflow.
3. Workflow Editor: the advanced editor for one automation, not a separate asset library.
4. Runs: execution history, evidence, and diagnostics for automations.

An automation list item maps to one `AutomationWorkflow`. Internal `AutomationTask` values remain steps inside that automation and must not become top-level Library rows.

## Presentation Tiers

- Single macro: exactly one macro task and no dependency graph.
- Linear sequence: a connected, non-branching chain made from macro steps, simple dependency delays, and OCR text gates.
- Advanced workflow: branching, joins, notifications, visual or provider conditions, disconnected graphs, or other structures that cannot be edited without losing meaning.

Classification is a pure core projection over the current workflow structure. Existing persistence remains compatible. A simple automation may be promoted to the Workflow Editor without changing runtime identity.

## Entry Contract

- The main window keeps stable Library and Automation workspaces.
- Library is macro-first. One or more selected macros use `Create Automation` as the shared creation language; scheduling and sequencing are configuration choices, not separate asset types.
- Automation opens a catalog first. It shows every automation regardless of tier, with type, macro/step counts, enabled state, next occurrence, current/latest status, and evidence availability.
- Opening a catalog item enters the editor for that automation. Advanced items enter the Workflow Editor; simple-item editing may progressively use dedicated sheets as their round-trip editors mature.
- Creating an advanced workflow is secondary. Creating an ordinary automation starts from selected macros in Library.
- Runs stays a modal operational surface and may be opened globally or filtered from an automation.

## Acceptance

- [x] Automation workspace opens to a catalog, not directly to an empty graph editor.
- [x] Catalog rows are automation/workflow scoped, never macro scoped or task-node scoped.
- [x] Single, linear, and advanced structures classify deterministically in pure tests.
- [x] Every row shows name, tier, macro/step count, enabled state, next run, latest status, and evidence availability without loading evidence files.
- [x] Opening an item preserves workflow identity and routes single-macro items to Quick Schedule, linear items to Quick Sequence, and advanced items to Workflow Editor.
- [x] Workflow Editor provides a clear return path to the catalog.
- [x] Library uses stable Automation and Runs entry labels; the Automation entry does not change meaning with current macro selection.
- [x] Library creation language converges on `Create Automation` for card and multi-selection entry points.
- [x] English and Simplified Chinese catalogs cover the new surface.
- [x] Projection, localization, full Swift Testing (710 tests), Swift 6 build, 1440 x 900 catalog rendering, release install, and signed-app launch checks pass.

## Boundaries

- SwiftUI renders projection values and dispatches accepted actions; it does not classify graphs, inspect repository files, or call Player/scheduler/OCR directly.
- This change does not introduce a second automation persistence model.
- Runs and evidence remain execution scoped by `executionID` / `evidenceID`.
- Macro editing remains separate because it edits reusable recorded input, not automation scheduling or graph state.

The management-page interaction and run-inspection contract lives in [01-management-page.md](01-management-page.md).
